defmodule DocCoffeeLiteWeb.HomeLive do
  use DocCoffeeLiteWeb, :live_view
  require Logger

  alias DocCoffeeLite.Epub
  alias DocCoffeeLite.Translation
  alias DocCoffeeLite.Translation.{Project, SourceDocument}
  alias DocCoffeeLite.Translation.Workers.ProjectPrepareWorker
  alias DocCoffeeLiteWeb.ProjectFormatter

  @upload_max_size 50 * 1_024 * 1_024
  @upload_accept ~w(.epub)

  @impl true
  def mount(_params, _session, socket) do
    projects = ProjectFormatter.list_projects(limit: 4)

    socket =
      socket
      |> assign(:page_title, "DocCoffee Lite")
      |> assign(:projects, projects)
      |> assign(:form, to_form(%{}, as: :upload))
      |> assign(:target_lang, "KO")
      |> allow_upload(:epub,
        accept: @upload_accept,
        max_entries: 1,
        max_file_size: @upload_max_size
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("noop", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("create_project", %{"upload" => params}, socket) do
    socket = assign(socket, :target_lang, String.trim(to_string(params["target_lang"] || "KO")))

    socket =
      socket
      |> clear_flash()
      |> put_flash(:info, "Uploaded. Preparing project in background…")

    case create_project_from_upload(socket) do
      {:ok, project_id} ->
        {:noreply, push_navigate(socket, to: ~p"/projects/#{project_id}")}

      {:error, :missing_upload} ->
        {:noreply, socket |> clear_flash() |> put_flash(:error, "Please choose an .epub file.")}

      {:error, reason} ->
        Logger.error("create_project failed: #{inspect(reason)}")
        {:noreply,
         socket
         |> clear_flash()
         |> put_flash(:error, "Upload failed: #{format_error(reason)}")}
    end
  end

  defp create_project_from_upload(socket) do
    consume_uploaded_entries(socket, :epub, fn %{path: path}, entry ->
      dest_path = Path.join(upload_dir(), "#{entry.uuid}.epub")
      Logger.info("Processing upload: #{path} -> #{dest_path}")

      result =
        with :ok <- File.mkdir_p(upload_dir()),
             :ok <- File.cp(path, dest_path),
             {:ok, work_dir} <- allocate_work_dir(socket.id, entry),
             _ = Logger.info("Work dir: #{work_dir}"),
             {:ok, session} <- Epub.open(dest_path, work_dir),
             _ = Logger.info("EPUB opened"),
             {:ok, project} <- create_project(session, socket),
             _ = Logger.info("Project created: #{project.id}"),
             {:ok, source_document} <- create_source_document(project, session, dest_path),
             _ = Logger.info("SourceDoc created: #{source_document.id}"),
             {:ok, job} <- enqueue_prepare_job(project.id, source_document.id) do
          Logger.info("Job enqueued: #{job.id}")
          {:ok, project.id}
        else
          {:error, reason} = error ->
            Logger.error("Upload failed at step: #{inspect(reason)}")
            error
          error ->
            Logger.error("Upload failed unexpected: #{inspect(error)}")
            {:error, error}
        end

      {:ok, result}
    end)
    |> case do
      [{:ok, project_id}] -> {:ok, project_id}
      [{:error, reason}] -> {:error, reason}
      [] -> {:error, :missing_upload}
      other -> 
        Logger.error("Unexpected consume_uploaded_entries result: #{inspect(other)}")
        {:error, {:unexpected_upload_result, other}}
    end
  end

  defp upload_dir do
    Application.app_dir(:doc_coffee_lite, "priv/uploads")
  end

  defp allocate_work_dir(socket_id, entry) do
    base = Application.app_dir(:doc_coffee_lite, "priv/work")
    work_dir = Path.join(base, "upload-#{socket_id}-#{entry.uuid}")
    File.mkdir_p!(base)

    case File.ls(work_dir) do
      {:error, :enoent} -> {:ok, work_dir}
      {:ok, []} -> {:ok, work_dir}
      {:ok, _} -> {:ok, Path.join(base, "upload-#{socket_id}-#{entry.uuid}-#{System.unique_integer([:positive])}")}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_project(session, socket) do
    title = session.package.metadata[:title] || session.package.metadata["title"]
    target_lang = socket.assigns.target_lang

    Translation.create_project(%{
      title: title || "Untitled project",
      status: "draft",
      progress: 0,
      source_lang: "EN",
      target_lang: target_lang,
      settings: %{}
    })
  end

  defp create_source_document(project, session, dest_path) do
    Translation.create_source_document(%{
      project_id: project.id,
      format: "epub",
      source_path: dest_path,
      work_dir: session.work_dir,
      metadata: session.package.metadata || %{},
      checksum: "pending-#{:os.system_time(:millisecond)}"
    })
  end

  defp enqueue_prepare_job(project_id, source_document_id) do
    %{
      "project_id" => project_id,
      "source_document_id" => source_document_id
    }
    |> ProjectPrepareWorker.new()
    |> Oban.insert()
  end

  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="relative min-h-screen overflow-hidden bg-[#f7f1e9] text-stone-900">
      <div class="pointer-events-none absolute inset-0">
        <div class="absolute -top-28 -left-24 h-72 w-72 rounded-full bg-amber-200/60 blur-3xl" />
        <div class="absolute top-28 -right-28 h-96 w-96 rounded-full bg-emerald-200/40 blur-3xl" />
        <div class="absolute bottom-0 left-1/2 h-80 w-80 -translate-x-1/2 rounded-full bg-orange-200/30 blur-3xl" />
      </div>

      <div class="relative z-10">
        <header class="mx-auto flex max-w-6xl items-center justify-between px-6 py-8">
          <div class="flex items-center gap-3">
            <div class="flex h-11 w-11 items-center justify-center rounded-2xl bg-stone-900 text-amber-100 shadow-sm">
              <.icon name="hero-sparkles" class="size-5" />
            </div>
            <div>
              <p class="font-display text-xl leading-none">DocCoffee Lite</p>
              <p class="mt-1 text-[0.65rem] uppercase tracking-[0.28em] text-stone-500">
                EPUB translation studio
              </p>
            </div>
          </div>
        </header>

        <main class="mx-auto max-w-6xl px-6 pb-16">
          <section class="grid gap-6 lg:grid-cols-12">
            <div class="space-y-6 lg:col-span-7">
              <div class="relative overflow-hidden rounded-3xl border border-stone-200/80 bg-white/80 p-8 shadow-sm backdrop-blur">
                <div class="relative">
                  <h1 class="font-display text-3xl leading-tight sm:text-4xl">
                    Reader-ready EPUB translation.
                  </h1>
                  <p class="mt-3 text-sm text-stone-600 sm:text-base">
                    Pure Ecto version. No Ash overhead.
                  </p>

                  <.form for={@form} id="new-project-form" phx-submit="create_project" phx-change="noop" class="mt-6 space-y-4">
                    <div class="space-y-2">
                      <.live_file_input upload={@uploads.epub} class="w-full cursor-pointer rounded-2xl border-2 border-dashed border-stone-200 bg-white/80 p-8 text-sm text-stone-600" />
                      
                      <%= for entry <- @uploads.epub.entries do %>
                        <div class="flex items-center justify-between gap-3 rounded-2xl border border-stone-200/70 bg-white/70 px-4 py-3 text-xs text-stone-600">
                          <span class="font-semibold text-stone-700">{entry.client_name}</span>
                          <span class="text-stone-400">{entry.progress}%</span>
                        </div>
                      <% end %>
                    </div>

                    <div class="flex flex-wrap items-center gap-3">
                      <div class="min-w-[220px]">
                        <label class="text-xs font-semibold uppercase tracking-[0.22em] text-stone-400">Target lang</label>
                        <.input name="upload[target_lang]" type="text" value={@target_lang} class="mt-2 w-full rounded-2xl border border-stone-200 bg-white px-4 py-3 text-sm" />
                      </div>

                      <button type="submit" disabled={@uploads.epub.entries == []} class="mt-6 inline-flex items-center gap-2 rounded-full bg-stone-900 px-4 py-3 text-xs font-semibold uppercase tracking-[0.22em] text-white">
                        Create project <.icon name="hero-plus" class="size-4" />
                      </button>
                    </div>
                  </.form>
                </div>
              </div>
            </div>

            <div class="space-y-6 lg:col-span-5">
              <div class="rounded-3xl border border-stone-200/80 bg-white/85 p-6 shadow-sm backdrop-blur">
                <div class="flex items-center justify-between mb-5">
                  <h2 class="font-display text-xl">Recent projects</h2>
                  <.link navigate={~p"/projects"} class="text-xs font-semibold uppercase tracking-wider text-stone-500 hover:text-stone-900">
                    View all
                  </.link>
                </div>
                <div class="space-y-4">
                  <%= for project <- @projects do %>
                    <div class="group rounded-2xl border border-stone-200/80 bg-white/70 p-4 transition hover:shadow-lg">
                      <div class="flex items-start justify-between gap-4">
                        <div>
                          <h3 class="text-base font-semibold text-stone-900">{project.title}</h3>
                          <p class="mt-1 text-xs text-stone-500">{project.source} -> {project.target}</p>
                        </div>
                        <span class={"inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-semibold uppercase #{project.status_classes}"}>
                          {project.status_label}
                        </span>
                      </div>
                      <div class="mt-4 flex items-center justify-end gap-2">
                        <.link navigate={~p"/projects/#{project.id}"} class="rounded-full border border-stone-200 bg-white px-3 py-1 text-xs font-semibold uppercase">
                          Details
                        </.link>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          </section>
        </main>
      </div>
    </div>
    """
  end
end
