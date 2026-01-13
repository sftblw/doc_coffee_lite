defmodule DocCoffeeLite.Translation do
  @moduledoc """
  The Translation context.
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
    Repo.all(Project)
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

  def start_translation(project_id) do
    Logger.info("Starting translation for project #{project_id}")
    
    with {:ok, _} <- update_project_status_force(project_id, "running"),
         run <- get_latest_run(project_id),
         {:ok, run} <- ensure_run_running(run, project_id),
         groups <- list_groups(project_id),
         strategy <- determine_strategy(run) do
      enqueue_groups(run.id, groups, strategy)
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

  defp update_project_status_force(project_id, status) do
    {count, _} = from(p in Project, where: p.id == ^project_id)
                 |> Repo.update_all(set: [status: status, updated_at: DateTime.utc_now()])
    if count == 1, do: {:ok, :updated}, else: {:error, :not_found}
  end

  defp update_run_status_force(run_id, status) do
    updates = [status: status, updated_at: DateTime.utc_now()]
    updates = if status == "running", do: Keyword.put(updates, :started_at, DateTime.utc_now()), else: updates
    
    {count, _} = from(r in TranslationRun, where: r.id == ^run_id)
                 |> Repo.update_all(set: updates)
    if count == 1, do: {:ok, :updated}, else: {:error, :not_found}
  end

  defp get_latest_run(project_id) do
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
    if run.llm_config_snapshot && map_size(run.llm_config_snapshot) > 0, do: "llm", else: "noop"
  end

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

  # --- Others ---

  def create_source_document(attrs) do
    %SourceDocument{}
    |> SourceDocument.changeset(attrs)
    |> Repo.insert()
  end

  def create_document_node(attrs) do
    %DocumentNode{}
    |> DocumentNode.changeset(attrs)
    |> Repo.insert()
  end

  def create_translation_group(attrs) do
    %TranslationGroup{}
    |> TranslationGroup.changeset(attrs)
    |> Repo.insert()
  end

  def create_translation_unit(attrs) do
    %TranslationUnit{}
    |> TranslationUnit.changeset(attrs)
    |> Repo.insert()
  end

  def create_translation_run(attrs) do
    %TranslationRun{}
    |> TranslationRun.changeset(attrs)
    |> Repo.insert()
  end

  def create_block_translation(attrs) do
    %BlockTranslation{}
    |> BlockTranslation.changeset(attrs)
    |> Repo.insert()
  end

  def create_policy_set(attrs) do
    %PolicySet{}
    |> PolicySet.changeset(attrs)
    |> Repo.insert()
  end

  def create_glossary_term(attrs) do
    %GlossaryTerm{}
    |> GlossaryTerm.changeset(attrs)
    |> Repo.insert()
  end

  def get_source_document!(id), do: Repo.get!(SourceDocument, id)
  def get_document_node!(id), do: Repo.get!(DocumentNode, id)
  def get_translation_group!(id), do: Repo.get!(TranslationGroup, id)
  def get_translation_unit!(id), do: Repo.get!(TranslationUnit, id)
  def get_translation_run!(id), do: Repo.get!(TranslationRun, id)
  def get_block_translation!(id), do: Repo.get!(BlockTranslation, id)
  def get_policy_set!(id), do: Repo.get!(PolicySet, id)
  def get_glossary_term!(id), do: Repo.get!(GlossaryTerm, id)

end