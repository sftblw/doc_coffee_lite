defmodule DocCoffeeLiteWeb.ProjectFormatter do
  @moduledoc false

  import Ecto.Query
  alias DocCoffeeLite.Repo
  alias DocCoffeeLite.Translation.{Project, SourceDocument, TranslationGroup}

  @default_limit 20

  @spec list_projects(keyword()) :: [map()]
  def list_projects(opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)

    query = from p in Project,
      order_by: [desc: p.updated_at],
      limit: ^limit,
      preload: [:source_document]

    Repo.all(query)
    |> Enum.map(&format_project/1)
  end

  defp format_project(%Project{} = project) do
    source_document = project.source_document

    %{ 
      id: project.id,
      title: project.title || "Untitled project",
      format: format_label(format_from_source(source_document)),
      source: lang_label(project.source_lang),
      target: lang_label(project.target_lang),
      progress: normalize_progress(project.progress),
      status: String.to_atom(project.status || "draft"),
      status_label: status_label(project.status),
      status_icon: status_icon(project.status),
      status_classes: status_classes(project.status),
      progress_classes: progress_classes(project.status),
      primary_action_label: primary_action_label(project.status),
      primary_action_classes: primary_action_classes(project.status),
      sections: sections_count(project.id),
      updated_at: relative_time(project.updated_at),
      last_output: last_output_label(project.status)
    }
  end

  defp format_from_source(%SourceDocument{format: format}), do: format
  defp format_from_source(_), do: nil

  defp sections_count(nil), do: 0
  defp sections_count(project_id) do
    Repo.aggregate(from(g in TranslationGroup, where: g.project_id == ^project_id), :count, :id)
  end

  def format_label(nil), do: "N/A"
  def format_label(:epub), do: "EPUB"
  def format_label("epub"), do: "EPUB"
  def format_label(:docx), do: "DOCX"
  def format_label("docx"), do: "DOCX"
  def format_label(format) when is_binary(format), do: String.upcase(format)
  def format_label(format), do: format |> to_string() |> String.upcase()

  def lang_label(nil), do: "??"
  def lang_label(lang) when is_binary(lang), do: String.upcase(lang)
  def lang_label(lang), do: lang |> to_string() |> String.upcase()

  def normalize_progress(nil), do: 0
  def normalize_progress(progress) when is_integer(progress), do: progress |> max(0) |> min(100)
  def normalize_progress(_progress), do: 0

  def relative_time(nil), do: "unknown"
  def relative_time(%DateTime{} = timestamp) do
    seconds = DateTime.diff(DateTime.utc_now(), timestamp, :second)
    cond do
      seconds < 60 -> "just now"
      seconds < 3600 -> "#{div(seconds, 60)}m ago"
      seconds < 86_400 -> "#{div(seconds, 3600)}h ago"
      seconds < 172_800 -> "yesterday"
      seconds < 604_800 -> "#{div(seconds, 86_400)}d ago"
      true -> Calendar.strftime(timestamp, "%Y-%m-%d")
    end
  end
  def relative_time(_), do: "unknown"

  def status_label("draft"), do: "Draft"
  def status_label("queued"), do: "Queued"
  def status_label("running"), do: "Translating"
  def status_label("translating"), do: "Translating"
  def status_label("paused"), do: "Paused"
  def status_label("validating"), do: "Validating"
  def status_label("ready"), do: "Ready"
  def status_label("failed"), do: "Failed"
  def status_label(status) when is_atom(status), do: status |> to_string() |> status_label()
  def status_label(_), do: "Unknown"

  def status_icon(s) when is_binary(s), do: s |> String.to_atom() |> status_icon()
  def status_icon(:draft), do: "hero-pencil-square"
  def status_icon(:queued), do: "hero-clock"
  def status_icon(:running), do: "hero-sparkles"
  def status_icon(:translating), do: "hero-sparkles"
  def status_icon(:paused), do: "hero-pause-circle"
  def status_icon(:validating), do: "hero-shield-check"
  def status_icon(:ready), do: "hero-check-circle"
  def status_icon(:failed), do: "hero-exclamation-triangle"
  def status_icon(_), do: "hero-question-mark-circle"

  def status_classes(s) when is_binary(s), do: s |> String.to_atom() |> status_classes()
  def status_classes(:draft), do: "bg-stone-50 text-stone-600 ring-stone-200"
  def status_classes(:queued), do: "bg-amber-50 text-amber-700 ring-amber-200"
  def status_classes(:running), do: "bg-emerald-50 text-emerald-700 ring-emerald-200"
  def status_classes(:translating), do: "bg-emerald-50 text-emerald-700 ring-emerald-200"
  def status_classes(:paused), do: "bg-amber-50 text-amber-700 ring-amber-200"
  def status_classes(:validating), do: "bg-indigo-50 text-indigo-700 ring-indigo-200"
  def status_classes(:ready), do: "bg-sky-50 text-sky-700 ring-sky-200"
  def status_classes(:failed), do: "bg-rose-50 text-rose-700 ring-rose-200"
  def status_classes(_), do: "bg-stone-50 text-stone-600 ring-stone-200"

  def progress_classes(s) when is_binary(s), do: s |> String.to_atom() |> progress_classes()
  def progress_classes(:draft), do: "bg-stone-300"
  def progress_classes(:queued), do: "bg-amber-300/80"
  def progress_classes(:running), do: "bg-emerald-400"
  def progress_classes(:translating), do: "bg-emerald-400"
  def progress_classes(:paused), do: "bg-amber-400"
  def progress_classes(:validating), do: "bg-indigo-400"
  def progress_classes(:ready), do: "bg-sky-400"
  def progress_classes(:failed), do: "bg-rose-400"
  def progress_classes(_), do: "bg-stone-300"

  def primary_action_label(_status), do: "View"
  def primary_action_classes(_status), do: "bg-stone-900 text-white hover:bg-stone-800"

  def last_output_label("ready"), do: "ready"
  def last_output_label("failed"), do: "retry needed"
  def last_output_label("paused"), do: "paused"
  def last_output_label("draft"), do: "draft"
  def last_output_label("validating"), do: "validating"
  def last_output_label("running"), do: "in progress"
  def last_output_label("queued"), do: "queued"
  def last_output_label("translating"), do: "in progress"
  def last_output_label(s) when is_atom(s), do: s |> to_string() |> last_output_label()
  def last_output_label(_), do: "unknown"
end
