defmodule DocCoffeeLiteWeb.BlockEditLive do
  use DocCoffeeLiteWeb, :live_view

  import Ecto.Query
  alias DocCoffeeLite.Repo
  alias DocCoffeeLite.Translation.{BlockTranslation, Project, TranslationGroup, TranslationRun, TranslationUnit}

  @impl true
  def mount(%{"project_id" => project_id, "run_id" => run_id, "group_id" => group_id}, _session, socket) do
    socket =
      socket
      |> assign(:project_id, project_id)
      |> assign(:run_id, run_id)
      |> assign(:group_id, group_id)
      |> assign(:project, nil)
      |> assign(:run, nil)
      |> assign(:group, nil)

    case load_state(project_id, run_id, group_id) do
      {:ok, project, run, group} ->
        socket =
          socket
          |> assign(:project, project)
          |> assign(:run, run)
          |> assign(:group, group)
          |> load_blocks()
        {:ok, socket}
      _ ->
        {:ok, socket |> put_flash(:error, "Not found") |> push_navigate(to: ~p"/projects/#{project_id}")}
    end
  end

  @impl true
  def handle_event("save-block", %{"block" => params}, socket) do
    unit_id = params["unit_id"]
    run_id = socket.assigns.run_id
    markup = params["translated_markup"]
    
    existing = Repo.one(from b in BlockTranslation, where: b.translation_run_id == ^run_id and b.translation_unit_id == ^unit_id)
    
    attrs = %{
      translation_run_id: run_id,
      translation_unit_id: unit_id,
      translated_markup: markup,
      translated_text: markup,
      status: "edited"
    }

    result = 
      case existing do
        nil -> %BlockTranslation{} |> BlockTranslation.changeset(attrs) |> Repo.insert()
        b -> b |> BlockTranslation.changeset(attrs) |> Repo.update()
      end

    case result do
      {:ok, _} -> {:noreply, put_flash(socket, :info, "Saved")}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to save")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#f6f1ea] text-stone-900 p-10">
      <header class="flex justify-between items-end mb-8">
        <div>
          <h1 class="text-3xl font-display">Review: {@project && @project.title}</h1>
          <p class="text-stone-600">Group: {@group && @group.group_key}</p>
        </div>
        <.link navigate={~p"/projects/#{@project_id}"} class="border px-4 py-2 rounded-full">Back</.link>
      </header>

      <div class="space-y-8">
        <%= for block <- @blocks do %>
          <div class="bg-white p-6 rounded-3xl border shadow-sm grid md:grid-cols-2 gap-6">
            <div>
              <p class="text-xs font-semibold uppercase text-stone-400 mb-2">Source</p>
              <div class="p-4 bg-stone-50 rounded-xl text-sm font-mono overflow-auto max-h-40">
                {block.unit.source_markup}
              </div>
            </div>
            <div>
              <p class="text-xs font-semibold uppercase text-stone-400 mb-2">Translation</p>
              <form phx-submit="save-block" class="space-y-3">
                <input type="hidden" name="block[unit_id]" value={block.unit.id} />
                <textarea name="block[translated_markup]" rows="6" class="w-full border rounded-xl p-3 text-sm font-mono">{(block.translation && block.translation.translated_markup) || block.unit.source_markup}</textarea>
                <button type="submit" class="bg-stone-900 text-white px-4 py-2 rounded-lg text-sm font-semibold">Save</button>
              </form>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp load_state(project_id, run_id, group_id) do
    project = Repo.get(Project, project_id)
    run = Repo.get(TranslationRun, run_id)
    group = Repo.get(TranslationGroup, group_id)
    if project && run && group, do: {:ok, project, run, group}, else: {:error, :not_found}
  end

  defp load_blocks(socket) do
    group_id = socket.assigns.group_id
    run_id = socket.assigns.run_id
    
    units = Repo.all(from u in TranslationUnit, where: u.translation_group_id == ^group_id, order_by: [asc: u.position])
    unit_ids = Enum.map(units, & &1.id)
    
    translations = Repo.all(from b in BlockTranslation, where: b.translation_run_id == ^run_id and b.translation_unit_id in ^unit_ids)
    trans_map = Map.new(translations, &{&1.translation_unit_id, &1})
    
    blocks = Enum.map(units, fn u -> %{unit: u, translation: Map.get(trans_map, u.id)} end)
    assign(socket, :blocks, blocks)
  end
end