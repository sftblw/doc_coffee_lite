defmodule DocCoffeeLite.Translation.Workers.ProjectPrepareWorker do
  @moduledoc """
  Prepares an uploaded project in the background.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [
      fields: [:worker, :args],
      keys: [:project_id],
      period: 60,
      states: [:available, :scheduled, :retryable, :executing]
    ]

  require Logger

  alias DocCoffeeLite.Repo
  alias DocCoffeeLite.Epub
  alias DocCoffeeLite.Translation
  alias DocCoffeeLite.Translation.Project
  alias DocCoffeeLite.Translation.SourceDocument
  alias DocCoffeeLite.Translation.Segmenter
  alias DocCoffeeLite.Translation.Persistence
  alias DocCoffeeLite.Translation.PolicyGenerator
  alias DocCoffeeLite.Translation.GlossaryCollector
  alias DocCoffeeLite.Translation.RunCreator

  @prepare_error_key "prepare_error"

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"project_id" => project_id, "source_document_id" => source_document_id}
      }) do
    
    with project <- Translation.get_project!(project_id),
         source_document <- Translation.get_source_document!(source_document_id),
         :ok <- ensure_empty_work_dir(source_document.work_dir),
         {:ok, session} <- Epub.open(source_document.source_path, source_document.work_dir),
         {:ok, %{tree: tree, groups: groups}} <- Segmenter.segment(:epub, session),
         {:ok, _persisted} <- Persistence.persist(tree, groups, project.id, source_document.id),
         {:ok, _policies} <- PolicyGenerator.generate_from_session(project.id, session),
         {:ok, _terms} <- GlossaryCollector.collect(project.id),
         {:ok, _run} <- RunCreator.create(project.id, status: "draft"),
         {:ok, _project} <- clear_prepare_error(project) do
      :ok
    else
      {:error, reason} = error ->
        Logger.error("ProjectPrepareWorker failed: #{inspect(reason)}")
        _ = set_prepare_error(project_id, reason)
        error

      other ->
        Logger.error("ProjectPrepareWorker unexpected: #{inspect(other)}")
        _ = set_prepare_error(project_id, other)
        {:error, {:unexpected_result, other}}
    end
  end

  defp ensure_empty_work_dir(work_dir) do
    case File.ls(work_dir) do
      {:error, :enoent} -> :ok
      {:ok, []} -> :ok
      {:ok, _} ->
        File.rm_rf(work_dir)
        |> case do
          {:ok, _} -> :ok
          {:error, reason, _} -> {:error, reason}
        end
      {:error, reason} -> {:error, reason}
    end
  end

  defp set_prepare_error(project_id, reason) do
    project = Translation.get_project!(project_id)
    settings = Map.put(project.settings || %{}, @prepare_error_key, error_payload(reason))
    Translation.update_project(project, %{settings: settings})
  end

  defp clear_prepare_error(%Project{} = project) do
    settings = Map.delete(project.settings || %{}, @prepare_error_key)
    Translation.update_project(project, %{settings: settings})
  end

  defp error_payload(reason) do
    %{
      "at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "error" => inspect(reason)
    }
  end
end
