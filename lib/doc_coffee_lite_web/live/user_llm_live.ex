defmodule DocCoffeeLiteWeb.UserLlmLive do
  use DocCoffeeLiteWeb, :live_view

  import Ecto.Query
  alias DocCoffeeLite.Repo
  alias DocCoffeeLite.Config.LlmConfig

  @impl true
  def mount(_params, _session, socket) do
    fallback =
      Repo.one(from c in LlmConfig, where: is_nil(c.project_id) and c.fallback == true, limit: 1)

    {:ok,
     socket
     |> assign(:page_title, "Global LLM Settings")
     |> assign(:fallback, fallback)}
  end

  @impl true
  def handle_event("save_fallback", %{"fallback" => params}, socket) do
    existing = socket.assigns.fallback

    attrs = %{
      name: params["name"],
      provider: params["provider"],
      model: params["model"],
      base_url: params["base_url"],
      api_key: params["api_key"],
      fallback: true,
      active: true,
      usage_type: "translate",
      tier: "cheap"
    }

    case existing do
      nil -> %LlmConfig{} |> LlmConfig.changeset(attrs) |> Repo.insert()
      config -> config |> LlmConfig.changeset(attrs) |> Repo.update()
    end
    |> case do
      {:ok, config} ->
        {:noreply, socket |> assign(:fallback, config) |> put_flash(:info, "Saved")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to save")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="min-h-screen bg-[#f6f1ea] text-stone-900 p-10 llm-settings">
        <header class="flex justify-between items-end mb-8">
          <div>
            <h1 class="text-3xl font-display">Global LLM Defaults</h1>
            <p class="text-stone-600">These settings apply if no project-specific config exists.</p>
          </div>
          <.link navigate={~p"/"} class="border px-4 py-2 rounded-full">Home</.link>
        </header>

        <section class="bg-white p-8 rounded-3xl border shadow-sm max-w-2xl">
          <h2 class="text-2xl mb-6 font-display">Default Model (Fallback)</h2>
          <.form for={%{}} as={:fallback} phx-submit="save_fallback" class="space-y-4">
            <div class="grid grid-cols-2 gap-4">
              <.input name="fallback[name]" label="Name" value={@fallback && @fallback.name} required />
              <.input
                name="fallback[provider]"
                label="Provider"
                value={@fallback && @fallback.provider}
                required
              />
            </div>
            <.input
              name="fallback[model]"
              label="Model"
              value={@fallback && @fallback.model}
              required
            />
            <.input
              name="fallback[base_url]"
              label="Base URL"
              value={@fallback && @fallback.base_url}
            />
            <.input name="fallback[api_key]" label="API Key" value={@fallback && @fallback.api_key} />

            <button
              type="submit"
              class="w-full bg-stone-900 text-white py-3 rounded-xl font-semibold mt-4"
            >
              Save Global Default
            </button>
          </.form>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
