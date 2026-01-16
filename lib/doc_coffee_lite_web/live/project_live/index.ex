defmodule DocCoffeeLiteWeb.ProjectLive.Index do
  use DocCoffeeLiteWeb, :live_view

  alias DocCoffeeLiteWeb.ProjectFormatter

  @impl true
  def mount(_params, _session, socket) do
    projects = ProjectFormatter.list_projects(limit: 1000)

    socket =
      socket
      |> assign(:page_title, "All Projects")
      |> assign(:projects, projects)

    {:ok, socket}
  end

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
          <div class="flex items-center gap-4">
            <.link
              navigate={~p"/"}
              class="rounded-full border border-stone-200 bg-white/80 px-4 py-2 text-xs font-semibold uppercase tracking-wider backdrop-blur hover:bg-white"
            >
              Home
            </.link>
          </div>
        </header>

        <main class="mx-auto max-w-6xl px-6 pb-16">
          <section class="space-y-6">
            <div class="flex items-center justify-between">
              <h1 class="font-display text-3xl">All Projects</h1>
            </div>

            <div class="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
              <%= for project <- @projects do %>
                <div class="group relative overflow-hidden rounded-3xl border border-stone-200/80 bg-white/80 p-6 shadow-sm backdrop-blur transition hover:shadow-lg">
                  <div class="flex items-start justify-between gap-4">
                    <div class="min-w-0">
                      <h3 class="truncate text-lg font-semibold text-stone-900" title={project.title}>
                        {project.title}
                      </h3>
                      <p class="mt-1 text-xs text-stone-500">{project.source} -> {project.target}</p>
                    </div>
                    <span class={"shrink-0 inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-semibold uppercase #{project.status_classes}"}>
                      {project.status_label}
                    </span>
                  </div>

                  <div class="mt-4">
                    <div class="flex items-center justify-between text-xs text-stone-500">
                      <span>Progress</span>
                      <span>{project.progress}%</span>
                    </div>
                    <div class="mt-2 h-1.5 w-full overflow-hidden rounded-full bg-stone-100">
                      <div
                        class="h-full rounded-full bg-stone-900 transition-all duration-500"
                        style={"width: #{project.progress}%"}
                      />
                    </div>
                  </div>

                  <div class="mt-6 flex items-center justify-end gap-2">
                    <.link
                      navigate={~p"/projects/#{project.id}"}
                      class="rounded-full border border-stone-200 bg-white px-4 py-2 text-xs font-semibold uppercase hover:bg-stone-50"
                    >
                      View Details
                    </.link>
                  </div>
                </div>
              <% end %>
            </div>
          </section>
        </main>
      </div>
    </div>
    """
  end
end
