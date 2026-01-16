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

  @pending_statuses ["pending", "queued", "translating"]
  @pause_snooze_seconds 10

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"run_id" => run_id, "group_id" => group_id} = args}) do
    # 1. Configuration from Env
    max_units = String.to_integer(System.get_env("LLM_BATCH_MAX_UNITS", "500"))
    max_chars = String.to_integer(System.get_env("LLM_BATCH_MAX_CHARS", "4000"))
    strategy = Map.get(args, "strategy", "noop")

    with {:ok, run, group, project} <- load_state(run_id, group_id),
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
        Enum.each(units, fn unit ->
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

          save_translation_result(
            run,
            unit,
            {translated_text, translated_markup, llm_response},
            "llm"
          )

          set_unit_status(unit, "translated")
        end)

        DocCoffeeLite.Translation.update_project_progress(run.project_id)
        :ok

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

    # 2. Restore placeholders using the HEALED text
    translated_markup =
      DocCoffeeLite.Translation.Placeholder.restore(healed_text, unit.placeholders || %{})

    sanitized_resp =
      case resp do
        %{"raw" => raw} when is_binary(raw) -> %{"raw_summary" => String.slice(raw, 0, 1000)}
        %{} = map -> Map.take(map, ["role", "content", "status", "usage"])
        _ -> %{}
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
      metadata: %{
        "strategy" => strategy,
        "source_hash" => unit.source_hash,
        "healing_status" => healing_status
      }
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
end
