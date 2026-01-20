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
      {:ok, snapshot} ->
        {:noreply, assign(socket, :snapshot, snapshot)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Snapshot failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="min-h-screen bg-[#f6f1ea] text-stone-900 p-10 llm-settings">
        <header class="flex justify-between items-start mb-10">
          <div>
            <h1 class="text-3xl font-display">LLM Settings</h1>
            <p class="text-stone-600">Configure models for project {@project && @project.title}</p>
          </div>
          <.link
            navigate={~p"/projects/#{@project && @project.id}"}
            class="border px-4 py-2 rounded-full"
          >
            Back
          </.link>
        </header>

        <div class="grid gap-6">
          <%= for usage_type <- @usage_types do %>
            <div class="bg-white p-6 rounded-2xl border shadow-sm">
              <h2 class="text-xl font-semibold mb-4">{String.capitalize(to_string(usage_type))}</h2>
              <div class="grid sm:grid-cols-2 gap-4">
                <%= for tier <- @tiers do %>
                  <.config_form
                    usage_type={usage_type}
                    tier={tier}
                    config={Map.get(@configs, {usage_type, tier})}
                  />
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp config_form(assigns) do
    assigns = assign(assigns, :form, build_config_form(assigns))

    ~H"""
    <.form
      for={@form}
      id={"llm-config-#{@usage_type}-#{@tier}"}
      phx-submit="save"
      class="p-4 border rounded-xl bg-stone-50"
    >
      <h3 class="font-semibold mb-3">{String.capitalize(to_string(@tier))} Tier</h3>
      <.input field={@form[:usage_type]} type="hidden" value={@usage_type} />
      <.input field={@form[:tier]} type="hidden" value={@tier} />
      <div class="space-y-3">
        <.input field={@form[:name]} label="Name" required />
        <.input field={@form[:provider]} label="Provider" required />
        <.input field={@form[:model]} label="Model" required />
        <.input field={@form[:base_url]} label="Base URL" />
        <.input field={@form[:api_key]} label="API Key" />
        <.input
          field={@form[:batch_max_chars]}
          type="number"
          label="Max Batch Chars"
          min="1"
        />
      </div>
      <button type="submit" class="mt-4 w-full bg-stone-900 text-white py-2 rounded-lg text-sm">
        Save
      </button>
    </.form>
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
    |> Enum.reduce(%{}, fn c, acc ->
      Map.put(acc, {String.to_existing_atom(c.usage_type), String.to_existing_atom(c.tier)}, c)
    end)
  end

  defp upsert_config(project_id, usage_type, tier, params) do
    usage_type_s = to_string(usage_type)
    tier_s = to_string(tier)

    existing =
      Repo.one(
        from c in LlmConfig,
          where:
            c.project_id == ^project_id and c.usage_type == ^usage_type_s and c.tier == ^tier_s
      )

    settings = merge_settings(existing && existing.settings, params)

    attrs = %{
      project_id: project_id,
      usage_type: usage_type_s,
      tier: tier_s,
      name: params["name"],
      provider: params["provider"],
      model: params["model"],
      base_url: params["base_url"],
      api_key: params["api_key"],
      settings: settings,
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

  defp build_config_form(%{usage_type: usage_type, tier: tier, config: config}) do
    settings = if config, do: config.settings || %{}, else: %{}

    to_form(
      %{
        "usage_type" => to_string(usage_type),
        "tier" => to_string(tier),
        "name" => config && config.name,
        "provider" => config && config.provider,
        "model" => config && config.model,
        "base_url" => config && config.base_url,
        "api_key" => config && config.api_key,
        "batch_max_chars" => Map.get(settings, "batch_max_chars")
      },
      as: :config
    )
  end

  defp merge_settings(existing, params) do
    existing = normalize_settings(existing)

    existing
    |> put_optional_int("batch_max_chars", params["batch_max_chars"])
  end

  defp normalize_settings(%{} = settings), do: settings
  defp normalize_settings(_), do: %{}

  defp put_optional_int(settings, key, value) do
    case parse_int(value) do
      nil -> Map.delete(settings, key)
      int -> Map.put(settings, key, int)
    end
  end

  defp parse_int(value) when is_integer(value) and value > 0, do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} when int > 0 -> int
      _ -> nil
    end
  end

  defp parse_int(_), do: nil
end
