defmodule DocCoffeeLite.Translation.Workers.TranslationGroupWorker do
  @moduledoc """
  Processes TranslationGroups sequentially and writes BlockTranslations.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 100

  import Ecto.Query
  require Logger

  alias DocCoffeeLite.Repo
  alias DocCoffeeLite.Translation.Project
  alias DocCoffeeLite.Translation.TranslationGroup
  alias DocCoffeeLite.Translation.TranslationUnit
  alias DocCoffeeLite.Translation.TranslationRun
  alias DocCoffeeLite.Translation.BlockTranslation
  alias DocCoffeeLite.Translation.LlmClient
  alias DocCoffeeLite.Translation.AutoHealer
  alias DocCoffeeLite.Translation.SimilarityGuard

  @pending_statuses ["pending", "queued", "translating"]
  @pause_snooze_seconds 10
  @similarity_retry_key "similarity_retry_count"
  @max_similarity_retries 1

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"run_id" => run_id, "group_id" => group_id} = args}) do
    # 1. Configuration from Env
    strategy = Map.get(args, "strategy", "noop")

    with {:ok, run, group, project} <- load_state(run_id, group_id),
         {max_units, max_chars} <- batch_limits(run),
         {:ok, group} <- ensure_active(run, group, project) do
      # 2. Ensure group is marked as running
      {:ok, group} = ensure_group_running(group)

      # 3. Fetch candidates (we fetch max_units to try and batch them)
      units = fetch_units(group, max_units)
      num_units = length(units)

      if num_units == 0 do
        finalize_group(group)
      else
        # 4. Form a "True Batch" based on char limits
        {batch_to_process, _remaining} = build_sub_batch(units, max_chars)
        Logger.info("[Batch] Processing #{length(batch_to_process)} units for group #{group.id}")

        # 5. Process the batch in one go
        case process_true_batch(run, group, batch_to_process, strategy, project) do
          :ok ->
            # 6. Update group cursor to the next unit after this batch
            last_unit = List.last(batch_to_process)
            advance_group_cursor(group, last_unit)

            # 7. Re-enqueue if we filled a full batch OR if DB says more exist
            if num_units == max_units or has_more_units?(group.id) do
              __MODULE__.new(args) |> Oban.insert()
              :ok
            else
              {:ok, _, group, _} = load_state(run_id, group_id)
              finalize_group(group)
            end

          {:error, reason} ->
            {:error, reason}
        end
      end
    else
      {:pause, _group} ->
        {:snooze, @pause_snooze_seconds}

      {:error, :not_found} ->
        :ok
    end
  end

  defp build_sub_batch(units, max_chars) do
    Enum.reduce_while(units, {[], 0}, fn unit, {acc, current_chars} ->
      unit_len = String.length(unit.source_text || "")
      new_total = current_chars + unit_len

      cond do
        # Always include at least one unit
        acc == [] ->
          {:cont, {[unit], unit_len}}

        new_total <= max_chars ->
          {:cont, {acc ++ [unit], new_total}}

        true ->
          {:halt, {acc, current_chars}}
      end
    end)
    |> then(fn {acc, _} -> {acc, units -- acc} end)
  end

  defp batch_limits(run) do
    default_units = env_int("LLM_BATCH_MAX_UNITS", 500)
    default_chars = env_int("LLM_BATCH_MAX_CHARS", 4000)
    settings = llm_settings(run.llm_config_snapshot, :translate)

    max_units = setting_int(settings, "batch_max_units") || default_units
    max_chars = setting_int(settings, "batch_max_chars") || default_chars

    {max_units, max_chars}
  end

  defp llm_settings(%{"configs" => configs}, usage_type) do
    type_config = Map.get(configs, to_string(usage_type), %{})
    config = Map.get(type_config, "cheap") || Map.get(type_config, "expensive") || %{}
    Map.get(config, "settings") || %{}
  end

  defp llm_settings(_, _usage_type), do: %{}

  defp env_int(key, default) do
    key
    |> System.get_env()
    |> setting_int()
    |> case do
      nil -> default
      value -> value
    end
  end

  defp setting_int(%{} = settings, key), do: settings |> Map.get(key) |> setting_int()
  defp setting_int(_settings, _key), do: nil

  defp setting_int(value) when is_integer(value) and value > 0, do: value

  defp setting_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} when int > 0 -> int
      _ -> nil
    end
  end

  defp setting_int(_), do: nil

  defp process_true_batch(run, group, units, "llm", project) do
    # 1. Mark all as translating
    Enum.each(units, &set_unit_status(&1, "translating"))

    # 2. Combine sources: [[p_1]]Source[[/p_1]]\n[[p_2]]... 
    combined_source =
      units
      |> Enum.map(fn u -> "[[#{u.unit_key}]]#{u.source_text}[[/#{u.unit_key}]]" end)
      |> Enum.join("\n")

    target_lang = project.target_lang || "Korean"
    expected_keys = Enum.map(units, & &1.unit_key)
    prev_context = group.context_summary

    # 3. Call LLM once with previous context
    case LlmClient.translate(run.llm_config_snapshot, combined_source,
           usage_type: :translate,
           target_lang: target_lang,
           expected_keys: expected_keys,
           prev_context: prev_context
         ) do
      {:ok, result, new_summary, llm_response} ->
        # 4. Update the group with the NEW context summary for the next batch
        if new_summary do
          update_group(group, %{context_summary: new_summary})
        end

        # 5. Parse and save each unit
        result =
          Enum.reduce_while(units, :ok, fn unit, :ok ->
            # Result can be a map (structured) or a string (raw blob)
            translated_text =
              case result do
                %{} = map ->
                  Map.get(map, unit.unit_key) || unit.source_text

                blob when is_binary(blob) ->
                  extract_unit_content(blob, unit.unit_key) || unit.source_text
              end

            translated_markup =
              DocCoffeeLite.Translation.Placeholder.restore(
                translated_text,
                unit.placeholders || %{}
              )

            case save_translation_result(
                   run,
                   unit,
                   {translated_text, translated_markup, llm_response},
                   "llm"
                 ) do
              {:ok, _} ->
                set_unit_status(unit, "translated")
                {:cont, :ok}

              {:error, %SimilarityGuard.SimilarityError{} = error} ->
                Logger.warning(
                  "Translation too similar for unit #{unit.id} (#{unit.unit_key}): #{error.ratio}"
                )

                {:halt, {:error, error}}

              {:error, reason} ->
                {:halt, {:error, reason}}
            end
          end)

        case result do
          :ok ->
            DocCoffeeLite.Translation.update_project_progress(run.project_id)
            :ok

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Batch translation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp process_true_batch(run, _group, units, _strategy, _project) do
    # Noop strategy: individual processing is fine
    Enum.each(units, fn unit ->
      translation_result = {unit.source_text || "", unit.source_markup || "", %{}}
      save_translation_result(run, unit, translation_result, "noop")
      set_unit_status(unit, "translated")
    end)

    DocCoffeeLite.Translation.update_project_progress(run.project_id)
    :ok
  end

  defp extract_unit_content(blob, unit_key) do
    escaped_key = Regex.escape(unit_key)
    # The pattern matches exactly from [[key]] to [[/key]]
    pattern = "\\[\\[#{escaped_key}\\]\\](.*?)\\[\\[\\/#{escaped_key}\\]\\]"

    case Regex.run(Regex.compile!(pattern, "s"), blob) do
      [_, content] -> String.trim(content)
      _ -> nil
    end
  end

  defp has_more_units?(group_id) do
    Repo.exists?(
      from u in TranslationUnit,
        where: u.translation_group_id == ^group_id and u.status in ^@pending_statuses
    )
  end

  defp save_translation_result(run, unit, {text, _markup_ignored, resp}, strategy) do
    # 1. Auto-Heal the text (fix brackets, restore whitespace structure)
    {healed_text, healing_status} =
      case AutoHealer.heal(unit.source_text, text) do
        {:ok, healed} -> {healed, "ok"}
        {:error, %AutoHealer.HealError{}} -> {text, "healing_failed"}
      end

    {similarity_state, similarity_ratio, similarity_level} =
      case SimilarityGuard.classify(unit.source_text, healed_text) do
        {:ok, ratio, level} -> {:ok, ratio, level}
        {:skip, ratio, :skip} -> {:skip, ratio, :skip}
      end

    llm_validation =
      case {similarity_state, similarity_level} do
        {:ok, :high} ->
          validate_similarity_with_llm(run, unit, healed_text, similarity_ratio)

        _ ->
          {:ok, :skipped}
      end

    case llm_validation do
      {:error, %SimilarityGuard.SimilarityError{} = error} ->
        {:error, error}

      _ ->
        # 2. Restore placeholders using the HEALED text
        translated_markup =
          DocCoffeeLite.Translation.Placeholder.restore(healed_text, unit.placeholders || %{})

        sanitized_resp =
          case resp do
            %{"raw" => raw} when is_binary(raw) -> %{"raw_summary" => String.slice(raw, 0, 1000)}
            %{} = map -> Map.take(map, ["role", "content", "status", "usage"])
            _ -> %{}
          end

        metadata = %{
          "strategy" => strategy,
          "source_hash" => unit.source_hash,
          "healing_status" => healing_status
        }

        metadata =
          if similarity_state == :ok do
            Map.merge(metadata, %{
              "similarity_ratio" => similarity_ratio,
              "similarity_level" => to_string(similarity_level)
            })
          else
            metadata
          end

        metadata =
          case llm_validation do
            {:ok, status} -> Map.put(metadata, "llm_similarity_check", to_string(status))
            {:error, _} -> Map.put(metadata, "llm_similarity_check", "failed")
          end

        attrs = %{
          translation_run_id: run.id,
          translation_unit_id: unit.id,
          status: "translated",
          translated_text: healed_text,
          translated_markup: translated_markup,
          placeholders: unit.placeholders || %{},
          llm_response: sanitized_resp,
          metrics: %{},
          metadata: metadata
        }

        try do
          %BlockTranslation{}
          |> BlockTranslation.changeset(attrs)
          |> Repo.insert(
            on_conflict: {:replace_all_except, [:id, :inserted_at]},
            conflict_target: [:translation_run_id, :translation_unit_id]
          )
        rescue
          e ->
            Logger.error("DATABASE INSERT EXCEPTION: #{inspect(e)}")
            {:error, e}
        end
    end
  end

  defp load_state(run_id, group_id) do
    run = Repo.get(TranslationRun, run_id)
    group = Repo.get(TranslationGroup, group_id)

    if run && group && run.project_id == group.project_id do
      project = Repo.get(Project, group.project_id)
      {:ok, run, group, project}
    else
      {:error, :not_found}
    end
  end

  defp fetch_units(group, batch_size) do
    cursor = group.cursor || 0

    query =
      from u in TranslationUnit,
        where:
          u.translation_group_id == ^group.id and u.position >= ^cursor and
            u.status in ^@pending_statuses,
        order_by: [asc: u.position],
        limit: ^batch_size

    Repo.all(query)
  end

  defp ensure_group_running(group) do
    if group.status in ["pending", "queued"] do
      update_group(group, %{status: "running"})
    else
      {:ok, group}
    end
  end

  defp finalize_group(group) do
    update_group(group, %{status: "ready", progress: 100})
  end

  defp ensure_active(run, group, project) do
    cond do
      project.status == "paused" -> pause_group(group)
      run.status == "paused" -> pause_group(group)
      project.status != "running" -> pause_group(group)
      run.status != "running" -> pause_group(group)
      true -> {:ok, group}
    end
  end

  defp pause_group(group) do
    if group.status != "paused" do
      update_group(group, %{status: "paused"})
      {:pause, %{group | status: "paused"}}
    else
      {:pause, group}
    end
  end

  defp advance_group_cursor(group, unit) do
    position = unit.position || 0
    cursor = max(group.cursor || 0, position + 1)
    update_group(group, %{cursor: cursor})
  end

  defp update_group(group, attrs) do
    {1, _} =
      from(g in TranslationGroup, where: g.id == ^group.id)
      |> Repo.update_all(set: Keyword.new(attrs) |> Keyword.put(:updated_at, DateTime.utc_now()))

    {:ok, Map.merge(group, attrs)}
  end

  defp set_unit_status(unit, status) do
    {1, _} =
      from(u in TranslationUnit, where: u.id == ^unit.id)
      |> Repo.update_all(set: [status: status, updated_at: DateTime.utc_now()])

    {:ok, %{unit | status: status}}
  end

  defp validate_similarity_with_llm(run, unit, healed_text, ratio) do
    src = scrub_for_llm(unit.source_text)
    dst = scrub_for_llm(healed_text)

    case LlmClient.classify_translation(run.llm_config_snapshot, src, dst,
           usage_type: :validation
         ) do
      {:ok, :not_translated} ->
        if allow_similarity_retry?(unit) do
          bump_similarity_retry(unit)

          {:error,
           %SimilarityGuard.SimilarityError{
             level: :high,
             ratio: ratio,
             message: "LLM NOT_TRANSLATED"
           }}
        else
          _ = mark_unit_dirty(unit)
          {:ok, :not_translated_max_retries}
        end

      {:ok, status} ->
        {:ok, status}

      {:error, reason} ->
        Logger.warning("LLM similarity check failed for unit #{unit.id}: #{inspect(reason)}")
        {:ok, :ambiguous}
    end
  end

  defp allow_similarity_retry?(unit) do
    count =
      case unit.metadata do
        %{} = metadata -> Map.get(metadata, @similarity_retry_key, 0)
        _ -> 0
      end

    count < @max_similarity_retries
  end

  defp bump_similarity_retry(unit) do
    metadata =
      case unit.metadata do
        %{} = map -> map
        _ -> %{}
      end

    count = Map.get(metadata, @similarity_retry_key, 0)
    new_metadata = Map.put(metadata, @similarity_retry_key, count + 1)

    from(u in TranslationUnit, where: u.id == ^unit.id)
    |> Repo.update_all(set: [metadata: new_metadata, updated_at: DateTime.utc_now()])

    :ok
  end

  defp mark_unit_dirty(unit) do
    from(u in TranslationUnit, where: u.id == ^unit.id)
    |> Repo.update_all(set: [is_dirty: true, updated_at: DateTime.utc_now()])
  end

  defp scrub_for_llm(text) when is_binary(text) do
    text
    |> String.replace(~r/\[\[[^\]]+\]\]/u, "")
    |> String.trim()
  end

  defp scrub_for_llm(_), do: ""
end
