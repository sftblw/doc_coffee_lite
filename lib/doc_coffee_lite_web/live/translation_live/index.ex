defmodule DocCoffeeLiteWeb.TranslationLive.Index do
  use DocCoffeeLiteWeb, :live_view
  alias DocCoffeeLite.Translation

  @impl true
  def mount(%{"project_id" => project_id}, _session, socket) do
    if connected?(socket), do: :ok
    
    project = Translation.get_project!(project_id)
    
    {:ok,
     socket
     |> assign(:project, project)
     |> assign(:page_title, "Review: #{project.title}")
     |> assign(:offset, 0)
     |> assign(:limit, 100)
     |> assign(:search, "")
     |> assign(:has_more, true)
     |> stream(:units, [])
     |> load_units()}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply,
     socket
     |> assign(:search, query)
     |> assign(:offset, 0)
     |> assign(:has_more, true)
     |> stream(:units, [], reset: true)
     |> load_units()}
  end

  @impl true
  def handle_event("load_more", _, socket) do
    {:noreply, load_units(socket)}
  end

  defp load_units(socket) do
    units = Translation.list_units_for_review(socket.assigns.project.id, [
      offset: socket.assigns.offset,
      limit: socket.assigns.limit,
      search: socket.assigns.search
    ])

    socket
    |> stream(:units, units)
    |> assign(:offset, socket.assigns.offset + length(units))
    |> assign(:has_more, length(units) == socket.assigns.limit)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col min-h-screen bg-[#f7f1e9]">
      <!-- Sticky Header -->
      <header class="sticky top-0 z-20 border-b border-stone-200 bg-white/80 backdrop-blur-md">
        <div class="mx-auto max-w-[1400px] px-4 py-4 sm:px-6 lg:px-8">
          <div class="flex flex-wrap items-center justify-between gap-4">
            <div class="flex items-center gap-4">
              <.link navigate={~p"/projects/#{@project.id}"} class="rounded-full p-2 hover:bg-stone-100 transition-colors">
                <.icon name="hero-arrow-left" class="size-5" />
              </.link>
              <div>
                <h1 class="text-lg font-display text-stone-900 truncate max-w-xs md:max-w-md">{@project.title}</h1>
                <p class="text-[10px] uppercase tracking-widest text-stone-500 font-bold">Translation Review</p>
              </div>
            </div>

            <!-- Search Bar -->
            <div class="flex-1 max-w-md">
              <form phx-change="search" phx-submit="search" class="relative">
                <.icon name="hero-magnifying-glass" class="absolute left-3 top-1/2 -translate-y-1/2 size-4 text-stone-400" />
                <input 
                  type="text" 
                  name="query" 
                  value={@search} 
                  placeholder="Search source or translation..." 
                  class="w-full rounded-full border-stone-200 pl-10 text-sm focus:border-indigo-500 focus:ring-indigo-500 bg-stone-50/50"
                  phx-debounce="300"
                />
              </form>
            </div>
          </div>
        </div>
      </header>

      <!-- Content Area -->
      <main class="flex-1">
        <div class="mx-auto max-w-[1400px] bg-white shadow-sm min-h-screen border-x border-stone-200">
          <div id="units-list" phx-update="stream">
            <%= for {id, unit} <- @streams.units do %>
              <.live_component 
                module={DocCoffeeLiteWeb.TranslationLive.RowComponent} 
                id={id} 
                unit={unit} 
              />
            <% end %>
          </div>

          <%= if @has_more do %>
            <div class="p-8 text-center border-t border-stone-100">
              <button phx-click="load_more" class="rounded-full border border-stone-200 bg-white px-8 py-3 text-xs font-bold uppercase tracking-widest text-stone-600 hover:bg-stone-50 transition-colors">
                Load More Units
              </button>
            </div>
          <% end %>
        </div>
      </main>
    </div>
    """
  end
end
