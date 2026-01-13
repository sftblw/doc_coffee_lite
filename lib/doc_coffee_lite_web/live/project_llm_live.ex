defmodule DocCoffeeLiteWeb.ProjectLlmLive do
  use DocCoffeeLiteWeb, :live_view

  import Ecto.Query
  alias DocCoffeeLite.Repo
  alias DocCoffeeLite.Config.LlmConfig
  alias DocCoffeeLite.Translation.LlmSelector
  alias DocCoffeeLite.Translation.Project

  @usage_types [:translate, :policy, :validation, :glossary, :summary]
  @tiers [:cheap, :expensive]

  @impl true
  def mount(%{"project_id" => project_id}, _session, socket) do
    socket =
      socket
      |> assign(:project, nil)
      |> assign(:configs, %{})
      |> assign(:snapshot, nil)
      |> assign(:usage_types, @usage_types)
      |> assign(:tiers, @tiers)
      |> assign(:page_title, "LLM settings")

    case load_project(project_id) do
      {:ok, project} ->
        configs = load_configs(project.id)
        {:ok, socket |> assign(:project, project) |> assign(:configs, configs)}
      _ ->
        {:ok, socket |> put_flash(:error, "Project not found") |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("save", %{"config" => params}, socket) do
    project = socket.assigns.project
    with {:ok, usage_type} <- fetch_atom(params, "usage_type"),
         {:ok, tier} <- fetch_atom(params, "tier"),
         {:ok, config} <- upsert_config(project.id, usage_type, tier, params) do
      configs = Map.put(socket.assigns.configs, {usage_type, tier}, config)
      {:noreply, socket |> assign(:configs, configs) |> put_flash(:info, "Saved")}
    else
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Save failed: #{inspect(reason)}")}
    end
  end

  def handle_event("preview_snapshot", _params, socket) do
    project = socket.assigns.project
    case LlmSelector.snapshot(project.id, allow_missing?: true) do
      {:ok, snapshot} -> {:noreply, assign(socket, :snapshot, snapshot)}
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Snapshot failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#f6f1ea] text-stone-900 p-10">
      <header class="flex justify-between items-start mb-10">
        <div>
          <h1 class="text-3xl font-display">LLM Settings</h1>
          <p class="text-stone-600">Configure models for project {@project && @project.title}</p>
        </div>
        <.link navigate={~p"/projects/#{@project && @project.id}"} class="border px-4 py-2 rounded-full">Back</.link>
      </header>

      <div class="grid gap-6">
        <%= for usage_type <- @usage_types do %>
          <div class="bg-white p-6 rounded-2xl border shadow-sm">
            <h2 class="text-xl font-semibold mb-4">{String.capitalize(to_string(usage_type))}</h2>
            <div class="grid sm:grid-cols-2 gap-4">
              <%= for tier <- @tiers do %>
                <.config_form usage_type={usage_type} tier={tier} config={Map.get(@configs, {usage_type, tier})} />
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp config_form(assigns) do
    ~H"""
    <form phx-submit="save" class="p-4 border rounded-xl bg-stone-50">
      <h3 class="font-semibold mb-3">{String.capitalize(to_string(@tier))} Tier</h3>
      <input type="hidden" name="config[usage_type]" value={@usage_type} />
      <input type="hidden" name="config[tier]" value={@tier} />
      <div class="space-y-3">
        <.input name="config[name]" label="Name" value={@config && @config.name} required />
        <.input name="config[provider]" label="Provider" value={@config && @config.provider} required />
        <.input name="config[model]" label="Model" value={@config && @config.model} required />
        <.input name="config[base_url]" label="Base URL" value={@config && @config.base_url} />
        <.input name="config[api_key]" label="API Key" value={@config && @config.api_key} />
      </div>
      <button type="submit" class="mt-4 w-full bg-stone-900 text-white py-2 rounded-lg text-sm">Save</button>
    </form>
    """
  end

  defp load_project(id) do
    case Repo.get(Project, id) do
      nil -> {:error, :not_found}
      project -> {:ok, project}
    end
  end

  defp load_configs(project_id) do
    Repo.all(from c in LlmConfig, where: c.project_id == ^project_id and c.active == true)
    |> Enum.reduce(%{}, fn c, acc -> Map.put(acc, {String.to_existing_atom(c.usage_type), String.to_existing_atom(c.tier)}, c) end)
  end

  defp upsert_config(project_id, usage_type, tier, params) do
    usage_type_s = to_string(usage_type)
    tier_s = to_string(tier)
    
    existing = Repo.one(from c in LlmConfig, where: c.project_id == ^project_id and c.usage_type == ^usage_type_s and c.tier == ^tier_s)
    
    attrs = %{
      project_id: project_id,
      usage_type: usage_type_s,
      tier: tier_s,
      name: params["name"],
      provider: params["provider"],
      model: params["model"],
      base_url: params["base_url"],
      api_key: params["api_key"],
      active: true
    }

    case existing do
      nil -> %LlmConfig{} |> LlmConfig.changeset(attrs) |> Repo.insert()
      config -> config |> LlmConfig.changeset(attrs) |> Repo.update()
    end
  end

  defp fetch_atom(params, key) do
    val = params[key]
    if val, do: {:ok, String.to_existing_atom(val)}, else: {:error, :missing}
  end
end