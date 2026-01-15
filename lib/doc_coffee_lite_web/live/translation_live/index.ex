defmodule DocCoffeeLiteWeb.TranslationLive.Index do
  use DocCoffeeLiteWeb, :live_view
  alias DocCoffeeLite.Translation

  @impl true
  def mount(%{"project_id" => project_id}, _session, socket) do
    if connected?(socket), do: :ok
    
    project = Translation.get_project!(project_id)
    dirty_count = Translation.count_dirty_units(project.id)
    
    {:ok,
     socket
     |> assign(:project, project)
     |> assign(:page_title, "Review: #{project.title}")
     |> assign(:limit, 100)
     |> assign(:show_bulk, false)
     |> assign(:dirty_count, dirty_count)
     |> assign(:bulk_form, to_form(%{"find" => "", "replace" => ""}))
     |> stream(:units, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    query = params["q"] || ""
    
    {:noreply,
     socket
     |> assign(:search, query)
     |> assign(:offset, 0)
     |> assign(:has_more, true)
     |> stream(:units, [], reset: true)
     |> load_units()}
  end

  @impl true
  def handle_event("toggle_bulk", _, socket) do
    {:noreply, assign(socket, :show_bulk, !socket.assigns.show_bulk)}
  end

  @impl true
  def handle_event("clear_search", _, socket) do
    {:noreply, push_patch(socket, to: ~p"/projects/#{socket.assigns.project.id}/translations")}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    path = if query == "", 
      do: ~p"/projects/#{socket.assigns.project.id}/translations",
      else: ~p"/projects/#{socket.assigns.project.id}/translations?q=#{query}"
      
    {:noreply, push_patch(socket, to: path)}
  end

  @impl true
  def handle_event("start_retranslation", _, socket) do
    case Translation.start_translation(socket.assigns.project.id) do
      :ok ->
        {:noreply, 
         socket 
         |> put_flash(:info, "Re-translation process enqueued successfully.")
         |> assign(:dirty_count, 0)
         |> assign(:offset, 0)
         |> stream(:units, [], reset: true)
         |> load_units()}
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("mark_filtered_dirty", _, socket) do
    search = socket.assigns.search
    project_id = socket.assigns.project.id
    
    Translation.mark_all_filtered_dirty(project_id, search)
    dirty_count = Translation.count_dirty_units(project_id)
    
    {:noreply,
     socket
     |> put_flash(:info, "Filtered units marked as dirty.")
     |> assign(:dirty_count, dirty_count)
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
  def handle_event("search", params, socket) do
    query = case params do
      %{"query" => q} -> q
      q when is_binary(q) -> q
      _ -> ""
    end

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
      <header class="sticky top-0 z-20 border-b border-stone-300 bg-white shadow-sm">
        <div class="mx-auto max-w-[1400px] px-4 py-4 sm:px-6 lg:px-8">
          <div class="flex flex-wrap items-center justify-between gap-4">
            <div class="flex items-center gap-4">
              <.link navigate={~p"/projects/#{@project.id}"} class="rounded-full p-2 hover:bg-stone-100 transition-colors text-stone-600">
                <.icon name="hero-arrow-left" class="size-5" />
              </.link>
              <div>
                <h1 class="text-lg font-display text-stone-900 truncate max-w-xs md:max-w-md">{@project.title}</h1>
                <p class="text-[10px] uppercase tracking-widest text-stone-500 font-bold">Review & Bulk Edit</p>
              </div>
            </div>

            <!-- Search Bar -->
            <div class="flex items-center gap-3 flex-1 max-w-lg">
              <form phx-submit="search" phx-change="search" class="relative flex-1">
                <.icon name="hero-magnifying-glass" class="absolute left-3 top-1/2 -translate-y-1/2 size-4 text-stone-500" />
                <input 
                  type="text" 
                  name="query" 
                  value={@search} 
                  placeholder="Search source or translation..." 
                  class="w-full rounded-full border-stone-300 pl-10 pr-10 text-sm text-stone-900 focus:border-indigo-500 focus:ring-indigo-500 bg-stone-50 placeholder:text-stone-400 font-medium"
                  phx-debounce="400"
                  autocomplete="off"
                />
                <button 
                  :if={@search != ""}
                  type="button" 
                  phx-click="clear_search"
                  class="absolute right-3 top-1/2 -translate-y-1/2 p-1 text-stone-400 hover:text-stone-600"
                >
                  <.icon name="hero-x-mark" class="size-4" />
                </button>
              </form>
              <button 
                phx-click="toggle_bulk" 
                class={[
                  "flex items-center gap-1.5 rounded-full border px-4 py-2 text-xs font-bold uppercase transition-all shadow-sm relative",
                  @show_bulk && "bg-stone-900 text-white border-stone-900",
                  !@show_bulk && "bg-white text-stone-700 border-stone-300 hover:bg-stone-50"
                ]}
              >
                <.icon name="hero-adjustments-horizontal" class="size-4" />
                Bulk Actions
                <span :if={@dirty_count > 0} class="absolute -top-1 -right-1 flex h-4 w-4 items-center justify-center rounded-full bg-rose-600 text-[8px] text-white">
                  {@dirty_count}
                </span>
              </button>
            </div>
          </div>
        </div>

        <!-- Bulk Actions Panel -->
        <div :if={@show_bulk} class="border-t border-stone-200 bg-stone-100 shadow-inner">
          <div class="mx-auto max-w-[1400px] px-4 py-8 sm:px-6 lg:px-8">
            <div class="grid gap-12 md:grid-cols-3">
              <!-- Action 1: Dirty Marking -->
              <div class="space-y-4">
                <h3 class="text-xs font-bold uppercase tracking-widest text-stone-600">Batch Filtered Action</h3>
                <p class="text-xs text-stone-500 leading-relaxed">
                  Mark all units matching <span class="font-black text-stone-900">"{@search}"</span> as needing re-translation.
                </p>
                <button 
                  phx-click="mark_filtered_dirty" 
                  disabled={@search == ""}
                  data-confirm={"Are you sure you want to mark all filtered items matching '#{@search}' as dirty?"}
                  class="inline-flex items-center gap-2 rounded-lg bg-stone-900 px-5 py-2.5 text-xs font-bold text-white uppercase hover:bg-stone-800 shadow-sm transition-colors disabled:opacity-30"
                >
                  <.icon name="hero-flag" class="size-4" />
                  Mark Filtered as Dirty
                </button>
              </div>

              <!-- Action 2: Find & Replace -->
              <div class="space-y-4">
                <h3 class="text-xs font-bold uppercase tracking-widest text-stone-600">Global Find & Replace</h3>
                <p class="text-xs text-stone-500 leading-relaxed">
                  Replace text within results for <span class="font-bold text-stone-900">"{@search || "all units"}"</span>.
                </p>
                <.form for={@bulk_form} phx-submit="bulk_replace" class="space-y-3">
                  <div class="flex gap-3">
                    <input name="find" type="text" placeholder="Find..." class="block flex-1 rounded-lg border-stone-300 text-xs text-stone-900 bg-white focus:border-indigo-500 shadow-sm" required />
                    <input name="replace" type="text" placeholder="Replace..." class="block flex-1 rounded-lg border-stone-300 text-xs text-stone-900 bg-white focus:border-indigo-500 shadow-sm" />
                  </div>
                  <button type="submit" class="w-full rounded-lg bg-stone-900 py-2.5 text-xs font-bold text-white uppercase hover:bg-stone-800 shadow-sm transition-colors">
                    Replace in results
                  </button>
                </.form>
              </div>

              <!-- Action 3: Re-translation Control -->
              <div class="space-y-4 border-l border-stone-200 pl-8">
                <h3 class="text-xs font-bold uppercase tracking-widest text-stone-600">Re-translation Queue</h3>
                <div class="flex items-center justify-between rounded-xl bg-white p-4 shadow-sm ring-1 ring-stone-200">
                  <div>
                    <span class="text-2xl font-display text-rose-600">{@dirty_count}</span>
                    <span class="ml-1 text-[10px] font-bold text-stone-400 uppercase">Units marked</span>
                  </div>
                  <button 
                    phx-click="start_retranslation"
                    disabled={@dirty_count == 0}
                    class="rounded-lg bg-rose-600 px-4 py-2 text-[10px] font-bold text-white uppercase hover:bg-rose-700 shadow-md transition-all disabled:opacity-30 disabled:grayscale"
                  >
                    Start Now
                  </button>
                </div>
                <p class="text-[10px] leading-relaxed text-stone-400 italic">
                  * Starting will reset status of marked units to 'pending' and rewind chapter cursors.
                </p>
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
