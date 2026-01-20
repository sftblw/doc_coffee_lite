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
     |> assign(:fallback, fallback)
     |> assign(:fallback_form, build_fallback_form(fallback))}
  end

  @impl true
  def handle_event("save_fallback", %{"fallback" => params}, socket) do
    existing = socket.assigns.fallback
    settings = merge_settings(existing && existing.settings, params)

    attrs = %{
      name: params["name"],
      provider: params["provider"],
      model: params["model"],
      base_url: params["base_url"],
      api_key: params["api_key"],
      settings: settings,
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
        {:noreply,
         socket
         |> assign(:fallback, config)
         |> assign(:fallback_form, build_fallback_form(config))
         |> put_flash(:info, "Saved")}

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
          <.form
            for={@fallback_form}
            id="global-llm-form"
            phx-submit="save_fallback"
            class="space-y-4"
          >
            <div class="grid grid-cols-2 gap-4">
              <.input field={@fallback_form[:name]} label="Name" required />
              <.input
                field={@fallback_form[:provider]}
                label="Provider"
                required
              />
            </div>
            <.input field={@fallback_form[:model]} label="Model" required />
            <.input field={@fallback_form[:base_url]} label="Base URL" />
            <.input field={@fallback_form[:api_key]} label="API Key" />
            <.input
              field={@fallback_form[:batch_max_chars]}
              type="number"
              label="Max Batch Chars"
              min="1"
            />

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

  defp build_fallback_form(nil), do: to_form(%{}, as: :fallback)

  defp build_fallback_form(%LlmConfig{} = fallback) do
    settings = fallback.settings || %{}

    to_form(
      %{
        "name" => fallback.name,
        "provider" => fallback.provider,
        "model" => fallback.model,
        "base_url" => fallback.base_url,
        "api_key" => fallback.api_key,
        "batch_max_chars" => Map.get(settings, "batch_max_chars")
      },
      as: :fallback
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
