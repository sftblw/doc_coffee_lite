defmodule DocCoffeeLite.Translation do
  @moduledoc """
  The Translation context (Ecto Version).
  """

  import Ecto.Query, warn: false
  require Logger
  alias DocCoffeeLite.Repo

  alias DocCoffeeLite.Translation.Project
  alias DocCoffeeLite.Translation.SourceDocument
  alias DocCoffeeLite.Translation.DocumentNode
  alias DocCoffeeLite.Translation.TranslationGroup
  alias DocCoffeeLite.Translation.TranslationUnit
  alias DocCoffeeLite.Translation.TranslationRun
  alias DocCoffeeLite.Translation.BlockTranslation
  alias DocCoffeeLite.Translation.PolicySet
  alias DocCoffeeLite.Translation.GlossaryTerm
  alias DocCoffeeLite.Translation.Workers.TranslationGroupWorker
  alias DocCoffeeLite.Translation.RunCreator

  # --- Project ---

  def list_projects do
    Repo.all(from p in Project, order_by: [desc: p.updated_at])
  end

  def get_project!(id), do: Repo.get!(Project, id)

  def create_project(attrs) do
    %Project{}
    |> Project.changeset(attrs)
    |> Repo.insert()
  end

  def update_project(%Project{} = project, attrs) do
    project
    |> Project.changeset(attrs)
    |> Repo.update()
  end

  # --- Runtime ---
  
  def reset_stuck_jobs do
    import Ecto.Query
    {count, _} = from(j in "oban_jobs", 
                      where: j.state == "executing" and j.worker == "DocCoffeeLite.Translation.Workers.TranslationGroupWorker")
                 |> Repo.update_all(set: [state: "available"])
    
    if count > 0, do: Logger.info("Recovered #{count} stuck translation jobs.")
    :ok
  end

  def start_translation(project_id) do
    Logger.info("Starting translation for project #{project_id}")
    
    with {:ok, _} <- update_project_status_force(project_id, "running"),
         run <- get_latest_run(project_id),
         _ <- Logger.info("Found run: #{inspect(run.id)}"),
         {:ok, run} <- ensure_run_running(run, project_id),
         {:ok, run} <- refresh_run_llm_snapshot(run),
         groups <- list_groups(project_id),
         _ <- Logger.info("Enqueuing #{length(groups)} groups"),
         strategy <- determine_strategy(run) do
      enqueue_groups(run.id, groups, strategy)
    else
      err ->
        Logger.error("Failed to start translation: #{inspect(err)}")
        err
    end
  end

  defp refresh_run_llm_snapshot(run) do
    case DocCoffeeLite.Translation.LlmSelector.snapshot(run.project_id, allow_missing?: true) do
      {:ok, snapshot} ->
        {1, _} = from(r in TranslationRun, where: r.id == ^run.id)
                 |> Repo.update_all(set: [llm_config_snapshot: snapshot, updated_at: DateTime.utc_now()])
        {:ok, %{run | llm_config_snapshot: snapshot}}
      _ -> {:ok, run}
    end
  end

  def pause_translation(project_id) do
    Logger.info("Pausing translation for project #{project_id}")
    with {:ok, _} <- update_project_status_force(project_id, "paused"),
         run <- get_latest_run(project_id) do
      if run, do: update_run_status_force(run.id, "paused")
      :ok
    end
  end

  def update_project_status_force(project_id, status) do
    {count, _} = from(p in Project, where: p.id == ^project_id)
                 |> Repo.update_all(set: [status: status, updated_at: DateTime.utc_now()])
    if count == 1, do: {:ok, :updated}, else: {:error, :not_found}
  end

  def update_run_status_force(run_id, status) do
    updates = [status: status, updated_at: DateTime.utc_now()]
    updates = if status == "running", do: Keyword.put(updates, :started_at, DateTime.utc_now()), else: updates
    
    {count, _} = from(r in TranslationRun, where: r.id == ^run_id)
                 |> Repo.update_all(set: updates)
    if count == 1, do: {:ok, :updated}, else: {:error, :not_found}
  end

  def get_latest_run(project_id) do
    Repo.one(from r in TranslationRun, where: r.project_id == ^project_id, order_by: [desc: r.inserted_at], limit: 1)
  end

  defp ensure_run_running(nil, project_id) do
    RunCreator.create(project_id, status: "running")
  end
  defp ensure_run_running(run, _project_id) do
    update_run_status_force(run.id, "running")
    {:ok, Repo.get!(TranslationRun, run.id)}
  end

  defp list_groups(project_id) do
    Repo.all(from g in TranslationGroup, where: g.project_id == ^project_id, order_by: [asc: g.position])
  end

  defp determine_strategy(run) do
    if has_llm_configs?(run.llm_config_snapshot), do: "llm", else: "noop"
  end

  defp has_llm_configs?(%{"configs" => configs}) when is_map(configs) do
    Enum.any?(configs, fn {_type, tiers} ->
      is_map(tiers) and Enum.any?(tiers, fn {_tier, config} -> is_map(config) and map_size(config) > 0 end)
    end)
  end
  defp has_llm_configs?(_), do: false

  defp enqueue_groups(run_id, groups, strategy) do
    jobs = Enum.map(groups, fn group ->
      TranslationGroupWorker.new(%{
        "run_id" => run_id,
        "group_id" => group.id,
        "strategy" => strategy
      })
    end)
    Oban.insert_all(jobs)
    :ok
  end

  # --- Progress & Status Management ---

  def update_project_progress(project_id) do
    total = Repo.aggregate(from(u in TranslationUnit, 
      join: g in assoc(u, :translation_group), 
      where: g.project_id == ^project_id), :count, :id)
      
    completed = Repo.aggregate(from(u in TranslationUnit, 
      join: g in assoc(u, :translation_group), 
      where: g.project_id == ^project_id and u.status == "translated"), :count, :id)

    progress = if total > 0, do: round((completed / total) * 100), else: 0
    
    # Update Project DB (use direct update_all for reliability)
    status = if progress == 100, do: "ready", else: "running"
    from(p in Project, where: p.id == ^project_id) 
    |> Repo.update_all(set: [progress: progress, status: status, updated_at: DateTime.utc_now()])

    # If 100%, also mark the latest run as ready
    if progress == 100 do
      case get_latest_run(project_id) do
        nil -> :ok
        run -> update_run_status_force(run.id, "ready")
      end
    end

    # Broadcast via PubSub
    Phoenix.PubSub.broadcast(DocCoffeeLite.PubSub, "project:#{project_id}", {:progress_updated, progress, completed, total})
    
    {:ok, progress, completed, total}
  end

  # --- Others (Ecto Boilerplate) ---

  def create_source_document(attrs) do
    %SourceDocument{} |> SourceDocument.changeset(attrs) |> Repo.insert()
  end

  def get_source_document!(id), do: Repo.get!(SourceDocument, id)

  def create_document_node(attrs) do
    %DocumentNode{} |> DocumentNode.changeset(attrs) |> Repo.insert()
  end

  def get_document_node!(id), do: Repo.get!(DocumentNode, id)

  def create_translation_group(attrs) do
    %TranslationGroup{} |> TranslationGroup.changeset(attrs) |> Repo.insert()
  end

  def get_translation_group!(id), do: Repo.get!(TranslationGroup, id)

  def create_translation_unit(attrs) do
    %TranslationUnit{} |> TranslationUnit.changeset(attrs) |> Repo.insert()
  end

  def get_translation_unit!(id), do: Repo.get!(TranslationUnit, id)

  def get_translation_run!(id), do: Repo.get!(TranslationRun, id)

  def create_block_translation(attrs) do
    %BlockTranslation{} |> BlockTranslation.changeset(attrs) |> Repo.insert()
  end

  def create_policy_set(attrs) do
    %PolicySet{} |> PolicySet.changeset(attrs) |> Repo.insert()
  end

  def create_glossary_term(attrs) do
    %GlossaryTerm{} |> GlossaryTerm.changeset(attrs) |> Repo.insert()
  end
end
