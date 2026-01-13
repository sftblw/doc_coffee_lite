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

    with {:ok, run, group, project} <- load_state(run_id, group_id) do
      process_group(run, group, project, batch_size, strategy)
    end
  end

  defp process_group(_run, %TranslationGroup{status: "ready"}, _project, _batch_size, _strategy),
    do: :ok

  defp process_group(run, group, project, batch_size, strategy) do
    case ensure_active(run, group, project) do
      {:ok, group} ->
        with {:ok, group} <- ensure_group_running(group),
             units <- fetch_units(group, batch_size) do
          case units do
            [] ->
              finalize_group(group)

            _ ->
              case process_units(run, group, units, strategy) do
                {:ok, group} ->
                  # Recurse immediately after refreshing state
                  with {:ok, run, group, project} <- load_state(run.id, group.id) do
                    process_group(run, group, project, batch_size, strategy)
                  end

                {:pause, _group} ->
                  {:snooze, @pause_snooze_seconds}

                {:error, reason} ->
                  {:error, reason}
              end
          end
        end

      {:pause, _group} ->
        {:snooze, @pause_snooze_seconds}
    end
  end

  defp process_units(run, group, units, strategy) do
    Enum.reduce_while(units, {:ok, group}, fn unit, {:ok, group} ->
      case load_state(run.id, group.id) do
        {:ok, run, group, project} ->
          case ensure_active(run, group, project) do
            {:ok, group} ->
              case process_unit(run, group, unit, strategy) do
                {:ok, group} -> {:cont, {:ok, group}}
                {:error, reason} -> {:halt, {:error, reason}}
              end

            {:pause, group} ->
              {:halt, {:pause, group}}
          end

        {:error, reason} ->
          Logger.error("TranslationGroupWorker failed to refresh state: #{inspect(reason)}")
          {:halt, {:error, reason}}
      end
    end)
  end

  defp process_unit(run, group, unit, strategy) do
    Logger.info("Processing unit #{unit.id} (strategy: #{strategy})")
    # 1. Mark as translating (quick DB update)
    {:ok, unit} = set_unit_status(unit, "translating")

    # 2. Perform translation
    Logger.info("Calling LLM for unit #{unit.id}...")
    translation_result =
      case strategy do
        "llm" ->
          llm_translate(run, unit)

        _ ->
          Logger.info("Using noop strategy for unit #{unit.id}")
          {unit.source_text || "", unit.source_markup || "", %{}}
      end

    {text, _markup, _resp} = translation_result
    Logger.info("Translation completed for unit #{unit.id} (length: #{String.length(text)})")

    # 3. Save result and update status
    Logger.info("Saving translation result for unit #{unit.id}...")
    Repo.transaction(fn ->
      with {:ok, block} <- save_translation_result(run, unit, translation_result, strategy),
           _ = Logger.info("Block saved: #{block.id}"),
           {:ok, _unit} <- set_unit_status(unit, "translated"),
           {:ok, group} <- advance_group_cursor(group, unit) do
        group
      else
        {:error, reason} -> 
          Logger.error("Failed to save unit #{unit.id}: #{inspect(reason)}")
          Repo.rollback(reason)
      end
    end)
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

  defp llm_translate(run, unit) do
    source = unit.source_text # Use protected text instead of raw markup

    case LlmClient.translate(run.llm_config_snapshot, source, usage_type: :translate) do
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
