defmodule DocCoffeeLiteWeb.GlossaryLive do
  use DocCoffeeLiteWeb, :live_view

  import Ecto.Query
  alias DocCoffeeLite.Repo
  alias DocCoffeeLite.Translation.GlossaryTerm
  alias DocCoffeeLite.Translation.Project

  @status_options [
    {"Candidate", "candidate"},
    {"Approved", "approved"},
    {"Rejected", "rejected"},
    {"Deprecated", "deprecated"}
  ]

  @impl true
  def mount(%{"project_id" => project_id}, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Glossary")
      |> assign(:project_id, project_id)
      |> assign(:status_options, @status_options)
      |> assign(:filters, default_filters())

    case load_project(project_id) do
      {:ok, project} ->
        socket = socket |> assign(:project, project) |> load_terms()
        {:ok, socket}

      _ ->
        {:ok, socket |> put_flash(:error, "Project not found") |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("filter", %{"filters" => filters}, socket) do
    socket = socket |> assign(:filters, normalize_filters(filters)) |> load_terms()
    {:noreply, socket}
  end

  def handle_event("save-term", %{"term" => params}, socket) do
    id = params["id"]
    term = Repo.get!(GlossaryTerm, id)

    case Repo.update(GlossaryTerm.changeset(term, params)) do
      {:ok, _} -> {:noreply, load_terms(socket)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to save term")}
    end
  end

  def handle_event("set-status", %{"id" => id, "status" => status}, socket) do
    term = Repo.get!(GlossaryTerm, id)

    case Repo.update(GlossaryTerm.changeset(term, %{status: status})) do
      {:ok, _} -> {:noreply, load_terms(socket)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to update status")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#f6f1ea] text-stone-900 p-10">
      <header class="flex justify-between items-end mb-8">
        <div>
          <h1 class="text-3xl font-display">Glossary: {@project && @project.title}</h1>
          <p class="text-stone-600">Curate terms for consistent translation.</p>
        </div>
        <.link navigate={~p"/projects/#{@project_id}"} class="border px-4 py-2 rounded-full">
          Back
        </.link>
      </header>

      <section class="bg-white p-6 rounded-2xl border shadow-sm mb-8">
        <.form for={%{}} as={:filters} phx-change="filter" class="flex gap-4">
          <div class="flex-1">
            <label class="block text-xs font-semibold uppercase text-stone-400">Search</label>
            <input
              name="filters[query]"
              value={@filters.query}
              class="w-full mt-1 border rounded-lg px-3 py-2"
            />
          </div>
          <div class="w-48">
            <label class="block text-xs font-semibold uppercase text-stone-400">Status</label>
            <select name="filters[status]" class="w-full mt-1 border rounded-lg px-3 py-2">
              <option value="all">All</option>
              {Phoenix.HTML.Form.options_for_select(@status_options, @filters.status)}
            </select>
          </div>
        </.form>
      </section>

      <div class="space-y-4">
        <%= for term <- @terms do %>
          <div class="bg-white p-6 rounded-2xl border shadow-sm flex justify-between items-center">
            <div>
              <h3 class="text-lg font-semibold">{term.source_text}</h3>
              <p class="text-sm text-stone-500">Usage: {term.usage_count}</p>
            </div>
            <div class="flex gap-2">
              <form phx-submit="save-term" class="flex gap-2">
                <input type="hidden" name="term[id]" value={term.id} />
                <input
                  name="term[target_text]"
                  value={term.target_text}
                  placeholder="Translation"
                  class="border rounded-lg px-3 py-1 text-sm"
                />
                <button
                  type="submit"
                  class="bg-stone-900 text-white px-3 py-1 rounded-lg text-sm font-semibold"
                >
                  Save
                </button>
              </form>
              <button
                phx-click="set-status"
                phx-value-id={term.id}
                phx-value-status="approved"
                class="border border-emerald-200 bg-emerald-50 text-emerald-700 px-3 py-1 rounded-lg text-sm font-semibold"
              >
                Approve
              </button>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp load_project(id) do
    case Repo.get(Project, id) do
      nil -> {:error, :not_found}
      project -> {:ok, project}
    end
  end

  defp load_terms(socket) do
    project_id = socket.assigns.project_id
    filters = socket.assigns.filters

    query = from g in GlossaryTerm, where: g.project_id == ^project_id

    query =
      if filters.status != "all",
        do: from(g in query, where: g.status == ^filters.status),
        else: query

    query =
      if filters.query != "",
        do: from(g in query, where: ilike(g.source_text, ^"%#{filters.query}%")),
        else: query

    query = from g in query, order_by: [desc: g.usage_count]

    terms = Repo.all(query)
    assign(socket, :terms, terms)
  end

  defp default_filters, do: %{query: "", status: "all"}
  defp normalize_filters(f), do: %{query: f["query"] || "", status: f["status"] || "all"}
end
