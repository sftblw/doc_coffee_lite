defmodule DocCoffeeLiteWeb.ProjectLive do
  use DocCoffeeLiteWeb, :live_view

  import Ecto.Query
  alias DocCoffeeLite.Repo
  alias DocCoffeeLite.Translation
  alias DocCoffeeLite.Translation.{Project, TranslationGroup, TranslationRun, SourceDocument}
  alias DocCoffeeLiteWeb.ProjectFormatter

  @impl true
  def mount(%{"project_id" => project_id}, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(DocCoffeeLite.PubSub, "project:#{project_id}")
    end

    socket =
      socket
      |> assign(:project, nil)
      |> assign(:page_title, "Project")

    case load_project(project_id) do
      {:ok, project} ->
        socket =
          socket
          |> assign(:project, project)
          |> assign(:page_title, project.title || "Project")

        {:ok, socket}

      {:error, _reason} ->
        {:ok, socket |> put_flash(:error, "Project not found") |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_info({:progress_updated, progress}, socket) do
    project = socket.assigns.project
    {:noreply, assign(socket, :project, %{project | progress: progress})}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, reload_project(socket)}
  end

  def handle_event("retry_prepare", _params, socket) do
    project = socket.assigns.project

    with %Project{} <- project,
         %SourceDocument{id: source_document_id} <- project.source_document,
         {:ok, _job} <-
           DocCoffeeLite.Translation.Workers.ProjectPrepareWorker.new(%{
             "project_id" => project.id,
             "source_document_id" => source_document_id
           })
           |> Oban.insert() do
      {:noreply,
       socket
       |> put_flash(:info, "Retry enqueued")
       |> reload_project()}
    else
      nil -> {:noreply, put_flash(socket, :error, "Project not loaded")}
      {:error, reason} -> {:noreply, put_flash(socket, :error, format_error(reason))}
      _ -> {:noreply, put_flash(socket, :error, "Source document missing")}
    end
  end

  def handle_event("start", _params, socket) do
    project = socket.assigns.project

    with %Project{} <- project,
         :ok <- Translation.start_translation(project.id) do
      {:noreply,
       socket
       |> put_flash(:info, "Translation started")
       |> reload_project()}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Project not loaded")}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Start failed: #{format_error(reason)}")
         |> reload_project()}
    end
  end

  def handle_event("pause", _params, socket) do
    project = socket.assigns.project

    with %Project{} <- project,
         :ok <- Translation.pause_translation(project.id) do
      {:noreply, socket |> put_flash(:info, "Translation paused") |> reload_project()}
    else
      nil -> {:noreply, put_flash(socket, :error, "Project not loaded")}
      {:error, reason} -> {:noreply, put_flash(socket, :error, format_error(reason))}
    end
  end

  defp reload_project(%{assigns: %{project: %Project{id: id}}} = socket) do
    case load_project(id) do
      {:ok, project} -> assign(socket, :project, project)
      _ -> socket
    end
  end
  defp reload_project(socket), do: socket

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#f6f1ea] text-stone-900">
      <div class="mx-auto max-w-5xl px-6 pb-16 pt-10">
        <header id="project-header" class="flex flex-wrap items-start justify-between gap-6">
          <div>
            <p class="text-xs font-semibold uppercase tracking-[0.3em] text-stone-400">Project</p>
            <h1 class="font-display mt-2 text-3xl text-stone-900 sm:text-4xl">
              {project_title(@project)}
            </h1>
            <p class="mt-2 text-sm text-stone-600">
              Status:
              <span class="font-semibold">
                {ProjectFormatter.status_label(project_status(@project))}
              </span>
              <span :if={latest_run(@project)} class="ml-3 text-stone-400">
                Run: {ProjectFormatter.status_label(run_status(latest_run(@project)))}
              </span>
            </p>

            <%= if @project && prepare_failed?(@project) do %>
              <div class="mt-4 flex flex-wrap items-center gap-3 rounded-2xl border border-rose-200/70 bg-rose-50 px-4 py-3 text-xs font-semibold text-rose-900 shadow-sm">
                Prepare failed.
                <span class="font-mono text-[0.7rem] font-medium text-rose-700">
                  {prepare_error_message(@project)}
                </span>
                <button phx-click="retry_prepare" class="ml-auto rounded-full bg-rose-600 px-3 py-1 text-[0.65rem] text-white uppercase">Retry</button>
                <button phx-click="refresh" class="rounded-full bg-white px-3 py-1 text-[0.65rem] uppercase border">Refresh</button>
              </div>
            <% end %>

            <%= if @project && preparing?(@project) do %>
              <div class="mt-4 inline-flex items-center gap-2 rounded-2xl border border-amber-200/70 bg-amber-50 px-4 py-2 text-xs font-semibold text-amber-900 shadow-sm">
                Preparing content in background…
                <button phx-click="refresh" class="ml-2 rounded-full bg-white px-3 py-1 text-[0.65rem] uppercase border">Refresh</button>
              </div>
            <% end %>
          </div>

          <div class="flex flex-wrap items-center gap-3">
            <button :if={@project && can_start?(@project, latest_run(@project))} phx-click="start" class="rounded-full bg-emerald-600 px-4 py-2 text-xs font-semibold text-white uppercase">Start</button>
            <button :if={@project && can_pause?(latest_run(@project))} phx-click="pause" class="rounded-full border bg-white px-4 py-2 text-xs font-semibold uppercase">Pause</button>
            <.link
              :if={@project && latest_run(@project) && run_status(latest_run(@project)) == "ready"}
              id="project-download"
              href={download_path(@project)}
              class="inline-flex items-center gap-2 rounded-full bg-stone-900 px-4 py-2 text-xs font-semibold uppercase tracking-[0.22em] text-white shadow-sm transition hover:-translate-y-0.5 hover:bg-stone-800"
            >
              Download <.icon name="hero-arrow-down-tray" class="size-4" />
            </.link>
            <.link :if={@project} navigate={~p"/"} class="rounded-full border bg-white px-4 py-2 text-xs font-semibold uppercase">Back</.link>
          </div>
        </header>

        <section id="project-summary" class="mt-10 rounded-3xl border border-stone-200/70 bg-white/80 p-6 shadow-sm">
          <%= if @project do %>
            <div class="grid gap-4 sm:grid-cols-3">
              <div>
                <p class="text-xs font-semibold uppercase text-stone-400">Format</p>
                <p class="mt-2 text-sm font-semibold">{source_format(@project)}</p>
              </div>
              <div>
                <p class="text-xs font-semibold uppercase text-stone-400">Languages</p>
                <p class="mt-2 text-sm font-semibold">
                  {ProjectFormatter.lang_label(@project.source_lang)} → {ProjectFormatter.lang_label(@project.target_lang)}
                </p>
              </div>
              <div>
                <p class="text-xs font-semibold uppercase text-stone-400">Progress</p>
                <p class="mt-2 text-sm font-semibold">{ProjectFormatter.normalize_progress(@project.progress)}%</p>
              </div>
            </div>
          <% else %>
            <p class="text-sm text-stone-600">No project loaded.</p>
          <% end %>
        </section>
      </div>
    </div>
    """
  end

  defp download_path(%Project{id: project_id} = project) do
    case latest_run(project) do
      %TranslationRun{id: run_id} -> ~p"/projects/#{project_id}/runs/#{run_id}/download"
      _ -> "#"
    end
  end

  defp load_project(project_id) do
    query = from p in Project,
      where: p.id == ^project_id,
      preload: [:source_document, translation_runs: :block_translations]
      
    case Repo.one(query) do
      nil -> {:error, :not_found}
      project -> {:ok, project}
    end
  end

  defp project_title(%Project{title: title}) when is_binary(title), do: title
  defp project_title(_), do: "Project"

  defp project_status(%Project{status: status}), do: status
  defp project_status(_), do: nil

  defp source_format(%Project{source_document: %SourceDocument{format: format}}),
    do: ProjectFormatter.format_label(format)
  defp source_format(_), do: "N/A"

  defp latest_run(%Project{translation_runs: runs}) when is_list(runs) do
    Enum.max_by(runs, & &1.inserted_at, fn -> nil end)
  end
  defp latest_run(_), do: nil

  defp preparing?(%Project{status: "draft"} = project) do
    has_groups? = project_has_groups?(project)
    project.source_document != nil and not has_groups? and not prepare_failed?(project)
  end
  defp preparing?(_), do: false

  defp prepare_failed?(%Project{settings: settings}) when is_map(settings) do
    Map.has_key?(settings, "prepare_error")
  end
  defp prepare_failed?(_), do: false

  defp prepare_error_message(%Project{settings: settings}) when is_map(settings) do
    get_in(settings, ["prepare_error", "error"]) || "unknown"
  end
  defp prepare_error_message(_), do: "unknown"

  defp project_has_groups?(%Project{id: project_id}) do
    Repo.exists?(from g in TranslationGroup, where: g.project_id == ^project_id)
  end
  defp project_has_groups?(_), do: false

  defp run_status(%TranslationRun{status: status}), do: status
  defp run_status(_), do: nil

  defp can_start?(%Project{status: "draft"}, _run), do: true
  defp can_start?(_project, %TranslationRun{status: s}) when s in ["draft", "paused", "failed"], do: true
  defp can_start?(_, _), do: false

  defp can_pause?(%TranslationRun{status: "running"}), do: true
  defp can_pause?(_), do: false

  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error)
end