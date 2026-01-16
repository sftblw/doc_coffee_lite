defmodule DocCoffeeLiteWeb.TranslationLive.RowComponent do
  use DocCoffeeLiteWeb, :live_component
  alias DocCoffeeLite.Translation

  @impl true
  def update(%{unit: unit} = assigns, socket) do
    translation = Translation.get_latest_translation(unit)

    socket =
      socket
      |> assign(assigns)
      |> assign(:translation, translation)

    # Initialize editing/draft only if not already set (to prevent resets on re-renders)
    socket =
      if Map.has_key?(socket.assigns, :editing) do
        socket
      else
        socket
        |> assign(:editing, false)
        |> assign(:draft, (translation && translation.translated_text) || "")
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("edit", _, socket) do
    # Ensure draft is synced with current translation when opening
    draft = (socket.assigns.translation && socket.assigns.translation.translated_text) || ""
    {:noreply, socket |> assign(:editing, true) |> assign(:draft, draft)}
  end

  @impl true
  def handle_event("cancel", _, socket) do
    {:noreply, assign(socket, :editing, false)}
  end

  @impl true
  def handle_event("save", %{"draft" => draft}, socket) do
    case socket.assigns.translation do
      nil ->
        {:noreply, put_flash(socket, :error, "No translation record to update.")}

      bt ->
        case Translation.update_block_translation(bt, %{translated_text: draft}) do
          {:ok, updated_bt} ->
            {:noreply,
             socket
             |> assign(:translation, updated_bt)
             |> assign(:draft, updated_bt.translated_text)
             |> assign(:editing, false)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to save.")}
        end
    end
  end

  @impl true
  def handle_event("toggle_dirty", _, socket) do
    unit = socket.assigns.unit

    case Translation.update_translation_unit(unit, %{is_dirty: !unit.is_dirty}) do
      {:ok, updated_unit} ->
        send(self(), {:dirty_toggled, updated_unit})
        {:noreply, assign(socket, :unit, updated_unit)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "group relative border-b border-stone-200 bg-white hover:bg-stone-50/50 transition-colors",
        @unit.is_dirty && "bg-rose-50/40"
      ]}
    >
      <div class="flex gap-4 p-4 lg:p-6">
        <!-- Meta & Context -->
        <div class="flex flex-col gap-2 w-28 shrink-0">
          <span class="text-[10px] font-bold uppercase tracking-wider text-stone-400">
            #{@unit.unit_key}
          </span>
          <span class="text-[9px] text-stone-400 truncate" title={@unit.translation_group.group_key}>
            {Path.basename(@unit.translation_group.group_key)}
          </span>

          <button
            phx-click="toggle_dirty"
            phx-target={@myself}
            class={[
              "mt-3 inline-flex items-center gap-1.5 self-start rounded-md px-2 py-1 text-[9px] font-bold uppercase tracking-tighter transition-all",
              @unit.is_dirty && "bg-rose-600 text-white shadow-sm ring-1 ring-rose-700",
              !@unit.is_dirty && "bg-stone-100 text-stone-400 hover:bg-stone-200 hover:text-stone-600"
            ]}
          >
            <.icon
              name={if @unit.is_dirty, do: "hero-exclamation-circle-solid", else: "hero-arrow-path"}
              class="size-3"
            />
            {if @unit.is_dirty, do: "RE-TRANSLATE", else: "MARK DIRTY"}
          </button>
        </div>
        
    <!-- Texts -->
        <div class="grid flex-1 gap-6 lg:grid-cols-2">
          <!-- Source Column -->
          <div class="space-y-2">
            <p class="text-[10px] font-bold uppercase tracking-widest text-stone-300">
              Original Source
            </p>
            <div class="text-sm leading-relaxed text-stone-600 whitespace-pre-wrap select-all">
              {@unit.source_text}
            </div>
          </div>
          
    <!-- Translation Column -->
          <div class="space-y-2">
            <div class="flex items-center justify-between">
              <p class="text-[10px] font-bold uppercase tracking-widest text-stone-300">
                Translation
              </p>
              <%= if !@editing do %>
                <button
                  phx-click="edit"
                  phx-target={@myself}
                  class="text-[10px] font-bold uppercase text-indigo-500 hover:text-indigo-700 transition-colors"
                >
                  Edit manually
                </button>
              <% end %>
            </div>

            <%= if @editing do %>
              <div class="space-y-3">
                <form phx-submit="save" phx-target={@myself} id={"form-#{@unit.id}"}>
                  <textarea
                    name="draft"
                    rows="5"
                    autofocus
                    class="w-full rounded-xl border-stone-300 text-sm leading-relaxed text-stone-900 focus:border-indigo-500 focus:ring-indigo-500 shadow-sm bg-white"
                    phx-window-keydown={JS.dispatch("submit", to: "#form-#{@unit.id}")}
                    phx-key="Enter"
                    phx-metadata='{"ctrlKey":true}'
                  ><%= @draft %></textarea>
                  <div class="mt-2 flex items-center gap-3">
                    <button
                      type="submit"
                      class="rounded-full bg-stone-900 px-4 py-1.5 text-[10px] font-bold uppercase text-white hover:bg-stone-800 shadow-md"
                    >
                      Save Changes <span class="ml-1 opacity-50 font-normal">Ctrl+Enter</span>
                    </button>
                    <button
                      type="button"
                      phx-click="cancel"
                      phx-target={@myself}
                      class="text-[10px] font-bold uppercase text-stone-400 hover:text-stone-600"
                    >
                      Discard
                    </button>
                  </div>
                </form>
              </div>
            <% else %>
              <div
                phx-click="edit"
                phx-target={@myself}
                class="min-h-[4rem] cursor-pointer rounded-lg border border-dashed border-transparent p-2 -m-2 hover:bg-white hover:border-stone-200 hover:shadow-sm text-sm leading-relaxed text-stone-900 whitespace-pre-wrap transition-all"
              >
                {if @translation && @translation.translated_text != "",
                  do: @translation.translated_text,
                  else: "---"}
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
