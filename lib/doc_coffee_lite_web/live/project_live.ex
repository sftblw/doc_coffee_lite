defmodule DocCoffeeLiteWeb.ProjectLive do
  use DocCoffeeLiteWeb, :live_view

  import Ecto.Query
  alias DocCoffeeLite.Repo
  alias DocCoffeeLite.Translation
  alias DocCoffeeLite.Translation.{Project, TranslationRun, SourceDocument, TranslationUnit}
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
      |> assign(:editing_title, false)
      |> allow_upload(:import_file, accept: ~w(.zip), max_entries: 1)

    case load_project(project_id) do
      {:ok, project, completed, total, recent} ->
        socket =
          socket
          |> assign(:project, project)
          |> assign(:completed_count, completed)
          |> assign(:total_count, total)
          |> assign(:recent_translations, recent)
          |> assign(:eta, calculate_eta(project, completed, total))
          |> assign(:page_title, project.title || "Project")

        {:ok, socket}

      {:error, _reason} ->
        {:ok, socket |> put_flash(:error, "Project not found") |> push_navigate(to: ~p"/")}
    end
  end

  @impl true

  def handle_info({:progress_updated, progress, completed, total}, socket) do
    if progress == 100 do
      {:noreply, reload_project(socket)}
    else
      project = socket.assigns.project

      updated_project = %{project | progress: progress}

      # For real-time feel, we could fetch recent translations here too, 

      # but let's keep it efficient by doing it on reload or separate pubsub if needed.

      # For now, let's refresh them on each progress update.

      {:ok, _, _, _, recent} = load_project(project.id)

      {:noreply,
       socket
       |> assign(:project, updated_project)
       |> assign(:completed_count, completed)
       |> assign(:total_count, total)
       |> assign(:recent_translations, recent)
       |> assign(:eta, calculate_eta(updated_project, completed, total))}
    end
  end

  @impl true

  def handle_event("edit_title", _, socket) do
    {:noreply, assign(socket, :editing_title, true)}
  end

  def handle_event("cancel_edit_title", _, socket) do
    {:noreply, assign(socket, :editing_title, false)}
  end

  def handle_event("save_title", %{"title" => title}, socket) do
    project = socket.assigns.project

    case Translation.update_project(project, %{title: title}) do
      {:ok, updated_project} ->
        {:noreply,
         socket
         |> assign(:project, updated_project)
         |> assign(:editing_title, false)
         |> put_flash(:info, "Project title updated.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update title.")}
    end
  end

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
      _ -> {:noreply, put_flash(socket, :error, "Failed to retry prepare")}
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
      _ -> {:noreply, put_flash(socket, :error, "Start failed")}
    end
  end

  def handle_event("reset_project", _params, socket) do
    project = socket.assigns.project

    with %Project{} <- project,
         :ok <- Translation.reset_project(project.id) do
      {:noreply,
       socket
       |> put_flash(:info, "Project progress and translations has been reset.")
       |> reload_project()}
    else
      _ -> {:noreply, put_flash(socket, :error, "Reset failed")}
    end
  end

  def handle_event("delete_project", _params, socket) do
    project = socket.assigns.project

    with %Project{} <- project,
         {:ok, _project} <- Translation.delete_project(project) do
      {:noreply,
       socket
       |> put_flash(:info, "Project deleted.")
       |> push_navigate(to: ~p"/")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Delete failed")}
    end
  end

  def handle_event("pause", _params, socket) do
    project = socket.assigns.project

    with %Project{} <- project,
         :ok <- Translation.pause_translation(project.id) do
      {:noreply, socket |> put_flash(:info, "Translation paused") |> reload_project()}
    else
      _ -> {:noreply, put_flash(socket, :error, "Pause failed")}
    end
  end

  def handle_event("heal_project", _params, socket) do
    project = socket.assigns.project

    with %Project{} <- project,
         {:ok, _job} <-
           DocCoffeeLite.Translation.Workers.ProjectHealingWorker.new(%{
             "project_id" => project.id
           })
           |> Oban.insert() do
      {:noreply, put_flash(socket, :info, "Healing started in background")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Failed to start healing")}
    end
  end

  def handle_event("validate_import", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("import_update", _params, socket) do
    project = socket.assigns.project

    uploaded_files =
      consume_uploaded_entries(socket, :import_file, fn %{path: path}, _entry ->
        DocCoffeeLite.Translation.ImportExport.import_to_existing(project.id, path)
      end)

    case uploaded_files do
      [{:ok, count}] ->
        {:noreply,
         socket
         |> put_flash(:info, "Imported #{count} translations successfully.")
         |> reload_project()}

      [{:error, reason}] ->
        {:noreply, put_flash(socket, :error, "Import failed: #{inspect(reason)}")}

      _ ->
        {:noreply, socket}
    end
  end

  defp reload_project(%{assigns: %{project: %Project{id: id}}} = socket) do
    case load_project(id) do
      {:ok, project, completed, total, recent} ->
        socket
        |> assign(:project, project)
        |> assign(:completed_count, completed)
        |> assign(:total_count, total)
        |> assign(:recent_translations, recent)
        |> assign(:eta, calculate_eta(project, completed, total))

      _ ->
        socket
    end
  end

  defp reload_project(socket), do: socket

  @impl true

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#f6f1ea] text-stone-900">
      <div class="mx-auto max-w-5xl px-6 pb-16 pt-10">
        <header id="project-header" class="flex flex-wrap items-start justify-between gap-6">
          <div class="min-w-0 flex-1">
            <div class="flex items-center gap-2 mb-1">
              <span class="text-[10px] font-bold uppercase tracking-[0.2em] text-stone-400">
                Project
              </span>
              <span
                :if={@project}
                class="rounded bg-stone-200/50 px-1.5 py-0.5 text-[9px] font-black text-stone-500"
              >
                ID: #{@project.id}
              </span>
            </div>

            <%= if @editing_title do %>
              <form phx-submit="save_title" class="flex items-center gap-2">
                <input
                  type="text"
                  name="title"
                  value={project_title(@project)}
                  autofocus
                  class="block w-full max-w-lg rounded-xl border-stone-300 bg-white/50 text-2xl font-display focus:border-indigo-500 focus:ring-indigo-500 py-1"
                />
                <button
                  type="submit"
                  class="rounded-full bg-stone-900 p-2 text-white hover:bg-stone-800"
                >
                  <.icon name="hero-check" class="size-4" />
                </button>
                <button
                  type="button"
                  phx-click="cancel_edit_title"
                  class="rounded-full bg-white p-2 text-stone-400 hover:text-stone-600 ring-1 ring-stone-200"
                >
                  <.icon name="hero-x-mark" class="size-4" />
                </button>
              </form>
            <% else %>
              <div class="group flex items-center gap-3">
                <h1 class="font-display text-3xl text-stone-900 sm:text-4xl truncate">
                  {project_title(@project)}
                </h1>
                <button
                  phx-click="edit_title"
                  class="opacity-0 group-hover:opacity-100 transition-opacity p-1 text-stone-400 hover:text-indigo-500"
                >
                  <.icon name="hero-pencil-square" class="size-5" />
                </button>
              </div>
            <% end %>

            <p class="mt-2 text-sm text-stone-600">
              Status:
              <span class="font-semibold">
                {ProjectFormatter.status_label(project_status(@project))}
              </span>

              <span :if={latest_run(@project)} class="ml-3 text-stone-400">
                Run: {ProjectFormatter.status_label(run_status(latest_run(@project)))}
              </span>
            </p>
          </div>

          <div class="flex flex-wrap items-center gap-3">
            <button
              :if={@project && can_start?(@project, latest_run(@project))}
              phx-click="start"
              class="rounded-full bg-emerald-600 px-4 py-2 text-xs font-semibold text-white uppercase shadow-sm hover:bg-emerald-700 transition-colors"
            >
              Start
            </button>

            <button
              :if={@project && can_pause?(latest_run(@project))}
              phx-click="pause"
              class="rounded-full border border-stone-200 bg-white px-4 py-2 text-xs font-semibold uppercase shadow-sm hover:bg-stone-50 transition-colors"
            >
              Pause
            </button>

            <button
              :if={@project}
              phx-click="reset_project"
              data-confirm="Are you absolutely sure? This will PERMANENTLY DELETE all translations and progress for this project."
              class="rounded-full border border-rose-200 bg-rose-50 px-4 py-2 text-xs font-semibold uppercase shadow-sm text-rose-600 hover:bg-rose-100 transition-colors"
            >
              Reset
            </button>

            <button
              :if={@project}
              id="delete-project-button"
              phx-click="delete_project"
              data-confirm="Delete this project and all associated data? This cannot be undone."
              class="rounded-full border border-rose-600 bg-rose-600 px-4 py-2 text-xs font-semibold uppercase shadow-sm text-white hover:bg-rose-700 transition-colors"
            >
              Delete
            </button>

            <button
              :if={@project && latest_run(@project)}
              phx-click="heal_project"
              phx-disable-with="Healing..."
              class="rounded-full border border-stone-200 bg-white px-4 py-2 text-xs font-semibold uppercase shadow-sm text-stone-600 hover:bg-stone-50"
              title="Auto-heal structure & whitespace"
            >
              Heal
            </button>

            <.link
              :if={@project && latest_run(@project) && run_status(latest_run(@project)) == "ready"}
              id="project-download"
              href={download_path(@project)}
              class="inline-flex items-center gap-2 rounded-full bg-stone-900 px-4 py-2 text-xs font-semibold uppercase text-white shadow-sm transition hover:bg-stone-800"
            >
              Download <.icon name="hero-arrow-down-tray" class="size-4" />
            </.link>

            <.link
              navigate={~p"/"}
              class="rounded-full border border-stone-200 bg-white px-4 py-2 text-xs font-semibold uppercase shadow-sm"
            >
              Back
            </.link>
          </div>
        </header>

        <section
          id="project-summary"
          class="mt-10 rounded-3xl border border-stone-200/70 bg-white/80 p-6 shadow-sm"
        >
          <%= if @project do %>
            <div class="grid gap-4 sm:grid-cols-3">
              <div>
                <p class="text-xs font-semibold uppercase text-stone-400">Format</p>

                <p class="mt-2 text-sm font-semibold">{source_format(@project)}</p>
              </div>

              <div>
                <p class="text-xs font-semibold uppercase text-stone-400">Languages</p>

                <p class="mt-2 text-sm font-semibold">
                  {ProjectFormatter.lang_label(@project.source_lang)} → {ProjectFormatter.lang_label(
                    @project.target_lang
                  )}
                </p>
              </div>

              <div>
                <p class="text-xs font-semibold uppercase text-stone-400">Progress</p>

                <p class="mt-2 text-sm font-semibold">
                  {ProjectFormatter.normalize_progress(@project.progress)}%
                  <span class="ml-1 text-xs font-medium text-stone-400">
                    ({@completed_count} / {@total_count})
                  </span>
                </p>

                <p
                  :if={@project.status == "running" && @eta}
                  class="mt-1 text-[0.65rem] text-amber-600 font-medium"
                >
                  ETA: {@eta}
                </p>
              </div>
            </div>
          <% else %>
            <p class="text-sm text-stone-600">No project loaded.</p>
          <% end %>
        </section>

        <section id="data-management" class="mt-10">
          <h2 class="text-sm font-semibold uppercase tracking-wider text-stone-400 mb-4">
            Data Management
          </h2>
          <div class="grid gap-6 md:grid-cols-2">
            <div class="rounded-2xl border border-stone-200 bg-white p-6">
              <h3 class="font-bold text-stone-900">Export Project Data</h3>
              <p class="mt-2 text-xs text-stone-500">
                Download a ZIP archive containing the source file and all current translations (YAML).
              </p>
              <div class="mt-6">
                <.link
                  href={~p"/projects/#{@project.id}/export"}
                  class="inline-flex items-center gap-2 rounded-lg bg-white border border-stone-300 px-4 py-2 text-xs font-bold uppercase text-stone-700 hover:bg-stone-50 transition-colors"
                >
                  <.icon name="hero-arrow-down-tray" class="size-4" /> Export Data
                </.link>
              </div>
            </div>

            <div class="rounded-2xl border border-stone-200 bg-white p-6">
              <h3 class="font-bold text-stone-900">Import / Update Translations</h3>
              <p class="mt-2 text-xs text-stone-500">
                Upload an exported ZIP file to merge translations.
                <span class="block text-rose-500 mt-1 font-semibold">* Must match the current source document.</span>
              </p>
              <form phx-submit="import_update" phx-change="validate_import" class="mt-4">
                <div class="flex items-center gap-4">
                  <.live_file_input upload={@uploads.import_file} class="text-xs" />
                  <button
                    type="submit"
                    class="rounded-lg bg-stone-900 px-4 py-2 text-xs font-bold uppercase text-white hover:bg-stone-800 disabled:opacity-50"
                    disabled={@uploads.import_file.entries == []}
                  >
                    Import
                  </button>
                </div>
                <%= for entry <- @uploads.import_file.entries do %>
                  <div class="mt-2 text-xs text-stone-500">
                    {entry.client_name} - {entry.progress}%
                    <span :if={entry.preflight_errors != []} class="text-rose-500">
                      {inspect(entry.preflight_errors)}
                    </span>
                  </div>
                <% end %>
              </form>
            </div>
          </div>
        </section>

        <section :if={@recent_translations != []} id="recent-activity" class="mt-10">
          <div class="flex items-center justify-between">
            <h2 class="text-sm font-semibold uppercase tracking-wider text-stone-400">
              Recent Activity
            </h2>
            <.link
              navigate={~p"/projects/#{@project.id}/translations"}
              class="text-xs font-bold uppercase tracking-widest text-indigo-500 hover:text-indigo-600 transition-colors"
            >
              View All Translation
            </.link>
          </div>

          <div class="mt-4 space-y-3">
            <%= for trans <- @recent_translations do %>
              <div class="group relative rounded-2xl border border-stone-200/60 bg-white/50 p-4 transition hover:bg-white">
                <div class="grid gap-4 sm:grid-cols-2">
                  <div>
                    <p class="text-[0.65rem] font-bold uppercase text-stone-400">Source</p>

                    <div class="mt-1 text-xs text-stone-600 line-clamp-3">
                      {trans.translation_unit.source_text}
                    </div>
                  </div>

                  <div>
                    <p class="text-[0.65rem] font-bold uppercase text-emerald-600">Translation</p>

                    <div class="mt-1 text-xs text-stone-900 font-medium line-clamp-3">
                      {trans.translated_text}
                    </div>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </section>
      </div>
    </div>
    """
  end

  defp load_project(id) do
    case Repo.get(Project, id) do
      nil ->
        {:error, :not_found}

      project ->
        project = Repo.preload(project, [:source_document, :translation_runs])

        total =
          Repo.aggregate(
            from(u in TranslationUnit,
              join: g in assoc(u, :translation_group),
              where: g.project_id == ^id
            ),
            :count,
            :id
          )

        completed =
          Repo.aggregate(
            from(u in TranslationUnit,
              join: g in assoc(u, :translation_group),
              where: g.project_id == ^id and u.status == "translated"
            ),
            :count,
            :id
          )

        # Fetch 5 most recent translations for the latest run

        recent =
          if run = latest_run(project) do
            Repo.all(
              from b in DocCoffeeLite.Translation.BlockTranslation,
                where: b.translation_run_id == ^run.id,
                order_by: [desc: b.inserted_at],
                limit: 5,
                preload: [:translation_unit]
            )
          else
            []
          end

        {:ok, project, completed, total, recent}
    end
  end

  defp download_path(%Project{id: id} = project) do
    case latest_run(project) do
      %TranslationRun{id: run_id} -> ~p"/projects/#{id}/runs/#{run_id}/download"
      _ -> "#"
    end
  end

  defp project_title(%Project{title: title}), do: title
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

  defp run_status(%TranslationRun{status: status}), do: status
  defp run_status(_), do: nil

  defp can_start?(_project, %TranslationRun{status: s})
       when s in ["draft", "paused", "failed", "ready"], do: true

  defp can_start?(%Project{status: "draft"}, nil), do: true
  defp can_start?(_, _), do: false

  defp can_pause?(%TranslationRun{status: "running"}), do: true
  defp can_pause?(_), do: false

  defp calculate_eta(project, completed, total) do
    with %TranslationRun{started_at: started_at} when not is_nil(started_at) <-
           latest_run(project),
         remaining when remaining > 0 <- total - completed do
      elapsed_seconds = DateTime.diff(DateTime.utc_now(), started_at)

      if completed > 0 and elapsed_seconds > 5 do
        seconds_per_unit = elapsed_seconds / completed
        remaining_seconds = round(remaining * seconds_per_unit)
        format_duration(remaining_seconds)
      else
        "Calculating..."
      end
    else
      _ -> nil
    end
  end

  defp format_duration(seconds) do
    cond do
      seconds < 60 ->
        "#{seconds}s remaining"

      seconds < 3600 ->
        "#{round(seconds / 60)}m remaining"

      true ->
        hours = div(seconds, 3600)
        mins = div(rem(seconds, 3600), 60)
        "#{hours}h #{mins}m remaining"
    end
  end
end
