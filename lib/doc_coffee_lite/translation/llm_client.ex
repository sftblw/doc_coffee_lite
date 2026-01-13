defmodule DocCoffeeLite.Translation.LlmClient do
  @moduledoc """
  Thin wrapper around LangChain chat models for translation.

  Currently uses `LangChain.ChatModels.ChatOpenAI` so it can talk to OpenAI-
  compatible servers (including Ollama).
  """

  alias LangChain.ChatModels.ChatOpenAI
  alias LangChain.Message

  @type config :: map()

  @spec translate(config(), String.t(), keyword()) :: {:ok, String.t(), map()} | {:error, term()}
  def translate(config, source, opts \\ []) when is_map(config) and is_binary(source) do
    usage_type = Keyword.get(opts, :usage_type, :translate)
    target_lang = Keyword.get(opts, :target_lang, "Korean")

    with {:ok, model} <- build_model(config, usage_type),
         {:ok, response} <- ChatOpenAI.call(model, messages_for_translation(source, target_lang)) do
      {:ok, extract_text(response), serialize_response(response)}
    end
  end

  defp messages_for_translation(source, target_lang) do
    [
      Message.new_system!(
        "Translate the user content into #{target_lang}. " <>
          "Preserve placeholders and markup exactly, unless instructed otherwise. " <>
          "Return only the translation."
      ),
      Message.new_user!(source)
    ]
  end

  defp build_model(%{} = snapshot, usage_type) do
    case resolve_config(snapshot, usage_type) do
      nil ->
        {:error, :missing_llm_config}

      config ->
        config = normalize_config_map(config)
        endpoint = endpoint_from_base_url(config["base_url"])

        attrs =
          %{
            endpoint: endpoint,
            model: config["model"],
            receive_timeout: 600_000
          }
          |> maybe_put(:api_key, config["api_key"])
          |> Map.merge(settings_to_langchain_attrs(config["settings"]))

        ChatOpenAI.new(attrs)
    end
  end

  defp resolve_config(%{"configs" => configs}, usage_type) do
    type_config = Map.get(configs, to_string(usage_type), %{})
    Map.get(type_config, "cheap") || Map.get(type_config, "expensive")
  end

  defp resolve_config(_snapshot, _usage_type), do: nil

  defp normalize_config_map(nil), do: %{}
  defp normalize_config_map(%{} = config), do: config
  defp normalize_config_map(_), do: %{}

  defp endpoint_from_base_url(nil), do: "https://api.openai.com/v1/chat/completions"

  defp endpoint_from_base_url(base_url) when is_binary(base_url) do
    base_url
    |> String.trim()
    |> String.trim_trailing("/")
    |> then(fn url -> url <> "/v1/chat/completions" end)
  end

  defp settings_to_langchain_attrs(nil), do: %{}

  defp settings_to_langchain_attrs(%{} = settings) do
    settings
    |> Enum.reduce(%{}, fn
      {key, value}, acc
      when key in ["receive_timeout", "max_tokens", "n", "seed"] and
             is_integer(value) ->
        Map.put(acc, String.to_atom(key), value)

      {"temperature", value}, acc when is_number(value) ->
        Map.put(acc, :temperature, 1.0 * value)

      {"frequency_penalty", value}, acc when is_number(value) ->
        Map.put(acc, :frequency_penalty, 1.0 * value)

      {_key, _value}, acc ->
        acc
    end)
  end

  defp maybe_put(attrs, _key, nil), do: attrs
  defp maybe_put(attrs, _key, ""), do: attrs
  defp maybe_put(attrs, key, value), do: Map.put(attrs, key, value)

  defp extract_text([%Message{} = first | _]), do: extract_text(first)
  
  defp extract_text(%Message{content: content}) when is_list(content) do
    content
    |> Enum.map(fn
      %LangChain.Message.ContentPart{type: :text, content: text} -> text
      _ -> ""
    end)
    |> Enum.join("")
  end

  defp extract_text(%Message{content: content}) when is_binary(content), do: content
  defp extract_text(%{content: content}) when is_binary(content), do: content
  defp extract_text(_), do: ""

  defp serialize_response(%Message{} = message) do
    %{
      "role" => to_string(message.role),
      "content" => message.content,
      "status" => to_string(message.status),
      "metadata" => Map.from_struct(message.metadata)
    }
  end

  defp serialize_response(other) do
    %{"raw" => inspect(other)}
  end
end
