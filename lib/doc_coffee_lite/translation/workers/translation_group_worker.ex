defmodule DocCoffeeLite.Translation.Workers.TranslationGroupWorker do
  @moduledoc """
  Processes TranslationGroups sequentially and writes BlockTranslations.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 100,
    unique: [
      fields: [:worker, :args],
      keys: [:run_id, :group_id],
      period: 60,
      states: [:available, :scheduled, :retryable, :executing]
    ]

  import Ecto.Query
  require Logger

  alias DocCoffeeLite.Repo
  alias DocCoffeeLite.Translation.Project
  alias DocCoffeeLite.Translation.TranslationGroup
  alias DocCoffeeLite.Translation.TranslationUnit
  alias DocCoffeeLite.Translation.TranslationRun
  alias DocCoffeeLite.Translation.BlockTranslation
  alias DocCoffeeLite.Translation.LlmClient

  @default_batch_size 10
  @pending_statuses ["pending", "queued", "translating"]
  @pause_snooze_seconds 10

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"run_id" => run_id, "group_id" => group_id} = args}) do
    batch_size = normalize_batch_size(Map.get(args, "batch_size"))
    strategy = Map.get(args, "strategy", "noop")

    with {:ok, run, group, project} <- load_state(run_id, group_id),
         {:ok, group} <- ensure_active(run, group, project) do
      
      # 1. Ensure group is marked as running
      {:ok, group} = ensure_group_running(group)
      
      # 2. Fetch one batch
      units = fetch_units(group, batch_size)
      
      if units == [] do
        finalize_group(group)
      else
        # 3. Process the batch (No more internal recursion)
        case process_units(run, group, units, strategy) do
          {:ok, _group} ->
            # 4. Check if there is more work to do
            if has_more_units?(group.id) do
              # 5. Enqueue the NEXT batch job
              __MODULE__.new(args) |> Oban.insert()
              :ok
            else
              # Refresh and finalize if truly done
              {:ok, _, group, _} = load_state(run_id, group_id)
              finalize_group(group)
            end

          {:pause, _group} ->
            {:snooze, @pause_snooze_seconds}

          {:error, reason} ->
            {:error, reason}
        end
      end
    else
      {:pause, _group} ->
        {:snooze, @pause_snooze_seconds}
      
      {:error, :not_found} ->
        # Run or group deleted
        :ok
    end
  end

  # Remove process_group/5 entirely as it is no longer used

  defp process_units(run, group, units, strategy) do
    Enum.reduce_while(units, {:ok, group}, fn unit, {:ok, group} ->
      case process_unit(run, group, unit, strategy) do
        {:ok, group} -> {:cont, {:ok, group}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp process_unit(run, group, unit, strategy) do
    # Reload project on each unit to get the latest target_lang and state
    project = Repo.get(Project, run.project_id)
    
    # 1. Double check if we should still be running
    case ensure_active(run, group, project) do
      {:ok, _group} ->
        # 2. Mark as translating
        {:ok, unit} = set_unit_status(unit, "translating")

        # 3. Perform translation
        translation_result =
          case strategy do
            "llm" -> llm_translate(run, unit, project)
            _ -> {unit.source_text || "", unit.source_markup || "", %{}}
          end

        # 4. Save result
        with {:ok, _block} <- save_translation_result(run, unit, translation_result, strategy),
             {:ok, _unit} <- set_unit_status(unit, "translated"),
             {:ok, group} <- advance_group_cursor(group, unit) do
          DocCoffeeLite.Translation.update_project_progress(run.project_id)
          {:ok, group}
        end

      {:pause, group} ->
        {:halt, {:pause, group}}
    end
  end

  defp has_more_units?(group_id) do
    Repo.exists?(from u in TranslationUnit, 
      where: u.translation_group_id == ^group_id and u.status in ^@pending_statuses)
  end

  defp save_translation_result(run, unit, {text, markup, resp}, strategy) do
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
      translated_text: text,
      translated_markup: markup,
      placeholders: unit.placeholders || %{},
      llm_response: sanitized_resp,
      metrics: %{},
      metadata: %{"strategy" => strategy, "source_hash" => unit.source_hash}
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
    query = from u in TranslationUnit,
      where: u.translation_group_id == ^group.id and u.position >= ^cursor and u.status in ^@pending_statuses,
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
      true -> {:ok, group} # Simplified: resume_group_if_needed removed for brevity or can be added
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
    {1, _} = from(g in TranslationGroup, where: g.id == ^group.id)
             |> Repo.update_all(set: Keyword.new(attrs) |> Keyword.put(:updated_at, DateTime.utc_now()))
    {:ok, Map.merge(group, attrs)}
  end

  defp set_unit_status(unit, status) do
    {1, _} = from(u in TranslationUnit, where: u.id == ^unit.id)
             |> Repo.update_all(set: [status: status, updated_at: DateTime.utc_now()])
    {:ok, %{unit | status: status}}
  end

  defp notify([]), do: :ok
  defp notify(notifications), do: Logger.info("Notifications: #{inspect(notifications)}") # Simplified for Lite

  defp translation_metadata(unit, strategy) do
    %{
      "strategy" => strategy,
      "source_hash" => unit.source_hash
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp llm_translate(run, unit, project) do
    source = unit.source_text # Use protected text instead of raw markup
    target_lang = project.target_lang || "Korean"

    case LlmClient.translate(run.llm_config_snapshot, source, usage_type: :translate, target_lang: target_lang) do
      {:ok, translated_text, llm_response} ->
        # Restore HTML tags from [[1]] placeholders
        translated_markup = DocCoffeeLite.Translation.Placeholder.restore(translated_text, unit.placeholders || %{})
        {translated_text, translated_markup, llm_response}

      {:error, reason} ->
        {unit.source_text, unit.source_markup, %{"error" => inspect(reason)}}
    end
  end

  defp normalize_batch_size(nil), do: @default_batch_size
  defp normalize_batch_size(val) when is_integer(val), do: val
  defp normalize_batch_size(_), do: @default_batch_size
end
