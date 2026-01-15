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
     |> assign(:show_bulk, false)
     |> assign(:bulk_form, to_form(%{"find" => "", "replace" => ""}))
     |> stream(:units, [])
     |> load_units()}
  end

  @impl true
  def handle_event("toggle_bulk", _, socket) do
    {:noreply, assign(socket, :show_bulk, !socket.assigns.show_bulk)}
  end

  @impl true
  def handle_event("mark_filtered_dirty", _, socket) do
    search = socket.assigns.search
    project_id = socket.assigns.project.id
    
    Translation.mark_all_filtered_dirty(project_id, search)
    
    {:noreply,
     socket
     |> put_flash(:info, "Filtered units marked as dirty.")
     |> assign(:offset, 0)
     |> stream(:units, [], reset: true)
     |> load_units()}
  end

  @impl true
  def handle_event("bulk_replace", %{"find" => find, "replace" => replace}, socket) do
    search = socket.assigns.search
    project_id = socket.assigns.project.id
    
    if find != "" do
      Translation.bulk_replace_translations(project_id, search, find, replace)
      
      {:noreply,
       socket
       |> put_flash(:info, "Bulk replacement complete.")
       |> assign(:offset, 0)
       |> stream(:units, [], reset: true)
       |> load_units()}
    else
      {:noreply, socket |> put_flash(:error, "Search string for replacement cannot be empty.")}
    end
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
            <div class="flex items-center gap-2 flex-1 max-w-lg">
              <form phx-change="search" phx-submit="search" class="relative flex-1">
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
              <button 
                phx-click="toggle_bulk" 
                class={[
                  "flex items-center gap-1.5 rounded-full border px-4 py-2 text-xs font-bold uppercase transition-all",
                  @show_bulk && "bg-stone-900 text-white border-stone-900",
                  !@show_bulk && "bg-white text-stone-600 border-stone-200 hover:bg-stone-50"
                ]}
              >
                <.icon name="hero-adjustments-horizontal" class="size-4" />
                Bulk
              </button>
            </div>
          </div>
        </div>

        <!-- Bulk Actions Panel -->
        <div :if={@show_bulk} class="border-t border-stone-200 bg-stone-50 shadow-inner">
          <div class="mx-auto max-w-[1400px] px-4 py-6 sm:px-6 lg:px-8">
            <div class="grid gap-8 md:grid-cols-2">
              <!-- Action 1: Dirty Marking -->
              <div class="space-y-3">
                <h3 class="text-[10px] font-bold uppercase tracking-widest text-stone-400">Batch Mark Dirty</h3>
                <p class="text-xs text-stone-500">
                  Mark all units matching <span class="font-bold text-stone-900">"{@search}"</span> as needing re-translation.
                </p>
                <button 
                  phx-click="mark_filtered_dirty" 
                  data-confirm={"Are you sure you want to mark all filtered items (#{@search}) as dirty?"}
                  class="inline-flex items-center gap-2 rounded-lg bg-rose-600 px-4 py-2 text-xs font-bold text-white uppercase hover:bg-rose-700"
                >
                  <.icon name="hero-flag" class="size-4" />
                  Mark Filtered as Dirty
                </button>
              </div>

              <!-- Action 2: Find & Replace -->
              <div class="space-y-3">
                <h3 class="text-[10px] font-bold uppercase tracking-widest text-stone-400">Find & Replace in Translations</h3>
                <p class="text-xs text-stone-500">
                  Replace text in translations for units matching <span class="font-bold text-stone-900">"{@search}"</span>.
                </p>
                <.form for={@bulk_form} phx-submit="bulk_replace" class="flex flex-wrap items-end gap-3">
                  <div class="space-y-1">
                    <label class="text-[9px] font-bold uppercase text-stone-400">Find</label>
                    <input name="find" type="text" class="block rounded-lg border-stone-200 text-xs focus:border-indigo-500 focus:ring-indigo-500" required />
                  </div>
                  <div class="space-y-1">
                    <label class="text-[9px] font-bold uppercase text-stone-400">Replace with</label>
                    <input name="replace" type="text" class="block rounded-lg border-stone-200 text-xs focus:border-indigo-500 focus:ring-indigo-500" />
                  </div>
                  <button type="submit" class="rounded-lg bg-stone-900 px-4 py-2 text-xs font-bold text-white uppercase hover:bg-stone-800">
                    Replace All
                  </button>
                </.form>
              </div>
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
