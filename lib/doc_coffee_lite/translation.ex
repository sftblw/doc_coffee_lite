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

  def delete_project(%Project{} = project) do
    Repo.delete(project)
  end

  def change_project(%Project{} = project, attrs \\ %{}) do
    Project.changeset(project, attrs)
  end

  def reset_project(project_id) do
    Repo.transaction(fn ->
      # 1. Find all translation unit IDs for this project
      unit_ids_query =
        from u in TranslationUnit,
          join: g in assoc(u, :translation_group),
          where: g.project_id == ^project_id,
          select: u.id

      unit_ids = Repo.all(unit_ids_query)

      # 2. Delete all block translations for these units
      from(bt in BlockTranslation, where: bt.translation_unit_id in ^unit_ids)
      |> Repo.delete_all()

      # 3. Reset all units to pending
      from(u in TranslationUnit, where: u.id in ^unit_ids)
      |> Repo.update_all(
        set: [status: "pending", is_dirty: false, updated_at: DateTime.utc_now()]
      )

      # 4. Reset all group cursors and progress
      from(g in TranslationGroup, where: g.project_id == ^project_id)
      |> Repo.update_all(
        set: [cursor: 0, progress: 0, status: "pending", updated_at: DateTime.utc_now()]
      )

      # 5. Reset project progress and status
      from(p in Project, where: p.id == ^project_id)
      |> Repo.update_all(set: [progress: 0, status: "draft", updated_at: DateTime.utc_now()])
    end)

    :ok
  end

  # --- Runtime ---

  def reset_stuck_jobs do
    import Ecto.Query

    {count, _} =
      from(j in "oban_jobs",
        where:
          j.state == "executing" and
            j.worker == "DocCoffeeLite.Translation.Workers.TranslationGroupWorker"
      )
      |> Repo.update_all(set: [state: "available"])

    if count > 0, do: Logger.info("Recovered #{count} stuck translation jobs.")
    :ok
  end

  def start_translation(project_id) do
    Logger.info("Starting translation for project #{project_id}")

    with {:ok, _} <- update_project_status_force(project_id, "running"),
         :ok <- prepare_dirty_units(project_id),
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

  defp prepare_dirty_units(project_id) do
    # 1. Find all dirty units for this project
    dirty_query =
      from u in TranslationUnit,
        join: g in assoc(u, :translation_group),
        where: g.project_id == ^project_id and u.is_dirty == true

    dirty_units = Repo.all(dirty_query)

    if dirty_units != [] do
      # 2. Reset status to pending and is_dirty to false
      unit_ids = Enum.map(dirty_units, & &1.id)

      from(u in TranslationUnit, where: u.id in ^unit_ids)
      |> Repo.update_all(
        set: [status: "pending", is_dirty: false, updated_at: DateTime.utc_now()]
      )

      # 3. Rewind group cursors to the minimum position of reset units
      dirty_units
      |> Enum.group_by(& &1.translation_group_id)
      |> Enum.each(fn {group_id, units} ->
        min_pos = units |> Enum.map(& &1.position) |> Enum.min()

        from(g in TranslationGroup, where: g.id == ^group_id)
        |> Repo.update_all(set: [cursor: min_pos, updated_at: DateTime.utc_now()])
      end)
    end

    :ok
  end

  defp refresh_run_llm_snapshot(run) do
    case DocCoffeeLite.Translation.LlmSelector.snapshot(run.project_id, allow_missing?: true) do
      {:ok, snapshot} ->
        {1, _} =
          from(r in TranslationRun, where: r.id == ^run.id)
          |> Repo.update_all(set: [llm_config_snapshot: snapshot, updated_at: DateTime.utc_now()])

        {:ok, %{run | llm_config_snapshot: snapshot}}

      _ ->
        {:ok, run}
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
    {count, _} =
      from(p in Project, where: p.id == ^project_id)
      |> Repo.update_all(set: [status: status, updated_at: DateTime.utc_now()])

    if count == 1, do: {:ok, :updated}, else: {:error, :not_found}
  end

  def update_run_status_force(run_id, status) do
    updates = [status: status, updated_at: DateTime.utc_now()]

    updates =
      if status == "running",
        do: Keyword.put(updates, :started_at, DateTime.utc_now()),
        else: updates

    {count, _} =
      from(r in TranslationRun, where: r.id == ^run_id)
      |> Repo.update_all(set: updates)

    if count == 1, do: {:ok, :updated}, else: {:error, :not_found}
  end

  def get_latest_run(project_id) do
    Repo.one(
      from r in TranslationRun,
        where: r.project_id == ^project_id,
        order_by: [desc: r.inserted_at],
        limit: 1
    )
  end

  defp ensure_run_running(nil, project_id) do
    RunCreator.create(project_id, status: "running")
  end

  defp ensure_run_running(run, _project_id) do
    update_run_status_force(run.id, "running")
    {:ok, Repo.get!(TranslationRun, run.id)}
  end

  defp list_groups(project_id) do
    Repo.all(
      from g in TranslationGroup, where: g.project_id == ^project_id, order_by: [asc: g.position]
    )
  end

  defp determine_strategy(run) do
    if has_llm_configs?(run.llm_config_snapshot), do: "llm", else: "noop"
  end

  defp has_llm_configs?(%{"configs" => configs}) when is_map(configs) do
    Enum.any?(configs, fn {_type, tiers} ->
      is_map(tiers) and
        Enum.any?(tiers, fn {_tier, config} -> is_map(config) and map_size(config) > 0 end)
    end)
  end

  defp has_llm_configs?(_), do: false

  defp enqueue_groups(run_id, groups, strategy) do
    jobs =
      Enum.map(groups, fn group ->
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
    total =
      Repo.aggregate(
        from(u in TranslationUnit,
          join: g in assoc(u, :translation_group),
          where: g.project_id == ^project_id
        ),
        :count,
        :id
      )

    completed =
      Repo.aggregate(
        from(u in TranslationUnit,
          join: g in assoc(u, :translation_group),
          where: g.project_id == ^project_id and u.status == "translated"
        ),
        :count,
        :id
      )

    progress = if total > 0, do: round(completed / total * 100), else: 0

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
    Phoenix.PubSub.broadcast(
      DocCoffeeLite.PubSub,
      "project:#{project_id}",
      {:progress_updated, progress, completed, total}
    )

    {:ok, progress, completed, total}
  end

  # --- Others (Ecto Boilerplate) ---

  def list_source_documents, do: Repo.all(SourceDocument)

  def create_source_document(attrs) do
    %SourceDocument{} |> SourceDocument.changeset(attrs) |> Repo.insert()
  end

  def get_source_document!(id), do: Repo.get!(SourceDocument, id)

  def update_source_document(%SourceDocument{} = source_document, attrs) do
    source_document
    |> SourceDocument.changeset(attrs)
    |> Repo.update()
  end

  def delete_source_document(%SourceDocument{} = source_document) do
    Repo.delete(source_document)
  end

  def change_source_document(%SourceDocument{} = source_document, attrs \\ %{}) do
    SourceDocument.changeset(source_document, attrs)
  end

  def list_document_nodes, do: Repo.all(DocumentNode)

  def create_document_node(attrs) do
    %DocumentNode{} |> DocumentNode.changeset(attrs) |> Repo.insert()
  end

  def get_document_node!(id), do: Repo.get!(DocumentNode, id)

  def update_document_node(%DocumentNode{} = document_node, attrs) do
    document_node
    |> DocumentNode.changeset(attrs)
    |> Repo.update()
  end

  def delete_document_node(%DocumentNode{} = document_node) do
    Repo.delete(document_node)
  end

  def change_document_node(%DocumentNode{} = document_node, attrs \\ %{}) do
    DocumentNode.changeset(document_node, attrs)
  end

  def list_translation_groups, do: Repo.all(TranslationGroup)

  def create_translation_group(attrs) do
    %TranslationGroup{} |> TranslationGroup.changeset(attrs) |> Repo.insert()
  end

  def get_translation_group!(id), do: Repo.get!(TranslationGroup, id)

  def update_translation_group(%TranslationGroup{} = group, attrs) do
    group
    |> TranslationGroup.changeset(attrs)
    |> Repo.update()
  end

  def delete_translation_group(%TranslationGroup{} = group) do
    Repo.delete(group)
  end

  def change_translation_group(%TranslationGroup{} = group, attrs \\ %{}) do
    TranslationGroup.changeset(group, attrs)
  end

  def list_translation_units, do: Repo.all(TranslationUnit)

  def create_translation_unit(attrs) do
    %TranslationUnit{} |> TranslationUnit.changeset(attrs) |> Repo.insert()
  end

  def get_translation_unit!(id), do: Repo.get!(TranslationUnit, id)

  def update_translation_unit(%TranslationUnit{} = unit, attrs) do
    unit
    |> TranslationUnit.changeset(attrs)
    |> Repo.update()
  end

  def delete_translation_unit(%TranslationUnit{} = unit) do
    Repo.delete(unit)
  end

  def change_translation_unit(%TranslationUnit{} = unit, attrs \\ %{}) do
    TranslationUnit.changeset(unit, attrs)
  end

  def list_translation_runs, do: Repo.all(TranslationRun)

  def create_translation_run(attrs) do
    %TranslationRun{} |> TranslationRun.changeset(attrs) |> Repo.insert()
  end

  def update_translation_run(%TranslationRun{} = run, attrs) do
    run
    |> TranslationRun.changeset(attrs)
    |> Repo.update()
  end

  def delete_translation_run(%TranslationRun{} = run) do
    Repo.delete(run)
  end

  def change_translation_run(%TranslationRun{} = run, attrs \\ %{}) do
    TranslationRun.changeset(run, attrs)
  end

  def list_block_translations, do: Repo.all(BlockTranslation)

  def get_block_translation!(id), do: Repo.get!(BlockTranslation, id)

  def delete_block_translation(%BlockTranslation{} = block_translation) do
    Repo.delete(block_translation)
  end

  def change_block_translation(%BlockTranslation{} = block_translation, attrs \\ %{}) do
    BlockTranslation.changeset(block_translation, attrs)
  end

  def list_units_for_similarity_scan(project_id, opts \\ []) do
    search = Keyword.get(opts, :search)

    latest_bt_query =
      from b in BlockTranslation,
        distinct: b.translation_unit_id,
        order_by: [asc: b.translation_unit_id, desc: b.inserted_at]

    query =
      from u in TranslationUnit,
        join: g in assoc(u, :translation_group),
        where: g.project_id == ^project_id,
        order_by: [asc: g.position, asc: u.position],
        preload: [block_translations: ^latest_bt_query]

    query
    |> apply_review_search_filter(search)
    |> Repo.all()
  end

  def mark_units_dirty([]), do: {0, nil}

  def mark_units_dirty(unit_ids) do
    from(u in TranslationUnit, where: u.id in ^unit_ids)
    |> Repo.update_all(set: [is_dirty: true, updated_at: DateTime.utc_now()])
  end

  def list_units_for_review(project_id, opts \\ []) do
    offset = Keyword.get(opts, :offset, 0)
    limit = Keyword.get(opts, :limit, 100)
    search = Keyword.get(opts, :search)

    # Subquery to get the latest block translation for each unit using DISTINCT ON
    latest_bt_query =
      from b in BlockTranslation,
        distinct: b.translation_unit_id,
        order_by: [asc: b.translation_unit_id, desc: b.inserted_at]

    query =
      from u in TranslationUnit,
        join: g in assoc(u, :translation_group),
        where: g.project_id == ^project_id,
        order_by: [asc: g.position, asc: u.position]

    # APPLY FILTER FIRST
    query =
      query
      |> apply_review_search_filter(search)
      |> apply_dirty_filter(Keyword.get(opts, :only_dirty, false))

    # THEN APPLY PAGINATION
    query =
      from u in query,
        offset: ^offset,
        limit: ^limit,
        preload: [:translation_group, block_translations: ^latest_bt_query]

    Repo.all(query)
  end

  def count_units_for_review(project_id, search, opts \\ []) do
    query =
      from u in TranslationUnit,
        join: g in assoc(u, :translation_group),
        where: g.project_id == ^project_id

    query
    |> apply_review_search_filter(search)
    |> apply_dirty_filter(Keyword.get(opts, :only_dirty, false))
    |> Repo.aggregate(:count, :id)
  end

  defp apply_dirty_filter(query, true) do
    from u in query, where: u.is_dirty == true
  end

  defp apply_dirty_filter(query, _), do: query

  defp apply_review_search_filter(query, search) do
    if search && search != "" do
      pattern = "%#{search}%"

      from u in query,
        where:
          ilike(coalesce(u.source_text, ""), ^pattern) or
            fragment(
              "EXISTS (SELECT 1 FROM block_translations bt WHERE bt.translation_unit_id = ? AND bt.translated_text ILIKE ?)",
              u.id,
              ^pattern
            )
    else
      query
    end
  end

  def count_dirty_units(project_id) do
    Repo.aggregate(
      from(u in TranslationUnit,
        join: g in assoc(u, :translation_group),
        where: g.project_id == ^project_id and u.is_dirty == true
      ),
      :count,
      :id
    )
  end

  def mark_all_filtered_dirty(project_id, search) do
    query =
      from u in TranslationUnit,
        join: g in assoc(u, :translation_group),
        where: g.project_id == ^project_id

    query =
      query
      |> apply_review_search_filter(search)
      # We need to subquery or use IDs because update_all doesn't support joins/distinct well in all cases
      |> select([u], u.id)

    ids = Repo.all(query)

    from(u in TranslationUnit, where: u.id in ^ids)
    |> Repo.update_all(set: [is_dirty: true, updated_at: DateTime.utc_now()])
  end

  def bulk_replace_translations(project_id, search, find_str, replace_str) do
    if find_str == "", do: :ok, else: do_bulk_replace(project_id, search, find_str, replace_str)
  end

  defp do_bulk_replace(project_id, search, find_str, replace_str) do
    # Get all latest block translations for filtered units
    latest_bt_query =
      from b in BlockTranslation,
        distinct: b.translation_unit_id,
        order_by: [asc: b.translation_unit_id, desc: b.inserted_at]

    query =
      from u in TranslationUnit,
        join: g in assoc(u, :translation_group),
        where: g.project_id == ^project_id,
        preload: [block_translations: ^latest_bt_query]

    units = query |> apply_review_search_filter(search) |> Repo.all()

    Repo.transaction(fn ->
      Enum.each(units, fn unit ->
        case get_latest_translation(unit) do
          nil ->
            :ok

          bt ->
            new_text = String.replace(bt.translated_text, find_str, replace_str)

            if new_text != bt.translated_text do
              update_block_translation(bt, %{translated_text: new_text})
            end
        end
      end)
    end)
  end

  def get_latest_translation(unit) do
    case unit.block_translations do
      [bt | _] -> bt
      _ -> nil
    end
  end

  def update_block_translation(%BlockTranslation{} = bt, attrs) do
    bt
    |> BlockTranslation.changeset(attrs)
    |> Repo.update()
  end

  def get_translation_run!(id), do: Repo.get!(TranslationRun, id)

  def create_block_translation(attrs) do
    %BlockTranslation{} |> BlockTranslation.changeset(attrs) |> Repo.insert()
  end

  def list_policy_sets, do: Repo.all(PolicySet)

  def get_policy_set!(id), do: Repo.get!(PolicySet, id)

  def create_policy_set(attrs) do
    %PolicySet{} |> PolicySet.changeset(attrs) |> Repo.insert()
  end

  def update_policy_set(%PolicySet{} = policy_set, attrs) do
    policy_set
    |> PolicySet.changeset(attrs)
    |> Repo.update()
  end

  def delete_policy_set(%PolicySet{} = policy_set) do
    Repo.delete(policy_set)
  end

  def change_policy_set(%PolicySet{} = policy_set, attrs \\ %{}) do
    PolicySet.changeset(policy_set, attrs)
  end

  def list_glossary_terms, do: Repo.all(GlossaryTerm)

  def get_glossary_term!(id), do: Repo.get!(GlossaryTerm, id)

  def create_glossary_term(attrs) do
    %GlossaryTerm{} |> GlossaryTerm.changeset(attrs) |> Repo.insert()
  end

  def update_glossary_term(%GlossaryTerm{} = glossary_term, attrs) do
    glossary_term
    |> GlossaryTerm.changeset(attrs)
    |> Repo.update()
  end

  def delete_glossary_term(%GlossaryTerm{} = glossary_term) do
    Repo.delete(glossary_term)
  end

  def change_glossary_term(%GlossaryTerm{} = glossary_term, attrs \\ %{}) do
    GlossaryTerm.changeset(glossary_term, attrs)
  end
end
