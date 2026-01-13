defmodule DocCoffeeLiteWeb.ProjectsLive do
  use DocCoffeeLiteWeb, :live_view

  alias DocCoffeeLiteWeb.ProjectFormatter

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Projects")
      |> assign(:projects, ProjectFormatter.list_projects(limit: 50))

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#f6f1ea] text-stone-900">
      <div class="mx-auto max-w-6xl px-6 pb-16 pt-10">
        <header id="projects-header" class="flex flex-wrap items-end justify-between gap-6">
          <div>
            <p class="text-xs font-semibold uppercase tracking-[0.3em] text-stone-400">All projects</p>
            <h1 class="font-display mt-2 text-3xl text-stone-900 sm:text-4xl">Projects</h1>
          </div>
          <.link navigate={~p"/"} class="rounded-full bg-stone-900 px-4 py-3 text-xs font-semibold text-white uppercase">New project</.link>
        </header>

        <section id="projects-list" class="mt-10 rounded-3xl border border-stone-200/70 bg-white/80 p-6 shadow-sm">
          <%= if @projects == [] do %>
            <div class="p-10 text-center text-sm text-stone-500">No projects yet.</div>
          <% else %>
            <div class="space-y-4">
              <%= for project <- @projects do %>
                <div class="group rounded-2xl border border-stone-200/80 bg-white/70 p-5 transition hover:shadow-lg">
                  <div class="flex flex-wrap items-start justify-between gap-4">
                    <div>
                      <div class="flex flex-wrap items-center gap-2 text-xs text-stone-500">
                        <span class="rounded-full border border-stone-200 bg-white px-2 py-1 font-semibold uppercase">{project.format}</span>
                        <span>{project.source} → {project.target}</span>
                      </div>
                      <h2 class="mt-2 text-lg font-semibold text-stone-900">{project.title}</h2>
                    </div>
                    <div class="flex items-center gap-3">
                      <span class={"rounded-full px-3 py-1 text-xs font-semibold uppercase #{project.status_classes}"}>{project.status_label}</span>
                      <.link navigate={~p"/projects/#{project.id}"} class="rounded-full bg-stone-900 px-4 py-2 text-xs font-semibold text-white uppercase">View</.link>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </section>
      </div>
    </div>
    """
  end
end