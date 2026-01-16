defmodule DocCoffeeLite.Translation.LlmClient do
  @moduledoc """
  Thin wrapper around LangChain chat models for translation.

  Currently uses `LangChain.ChatModels.ChatOpenAI` so it can talk to OpenAI-
  compatible servers (including Ollama).
  """

  alias LangChain.ChatModels.ChatOpenAI
  alias LangChain.Message
  alias DocCoffeeLite.Translation.LlmPool

  require Logger

  @type config :: map()

  @spec translate(config(), String.t(), keyword()) ::
          {:ok, map() | String.t(), String.t() | nil, map()} | {:error, term()}
  def translate(config, source, opts \\ []) when is_map(config) and is_binary(source) do
    usage_type = Keyword.get(opts, :usage_type, :translate)
    target_lang = Keyword.get(opts, :target_lang, "Korean")
    expected_keys = Keyword.get(opts, :expected_keys, [])
    prev_context = Keyword.get(opts, :prev_context)

    with {:ok, model_config, selected_url} <- build_model_config(config, usage_type) do
      # Configure model with native json_schema enforcement
      llm = ChatOpenAI.new!(Map.put(model_config, :json_schema, translations_schema_payload()))

      initial_messages = [
        Message.new_system!(
          "# ROLE\nYou are a specialized translation engine.\n\n" <>
            "# TASK\nTranslate the provided text units into the target language: '#{target_lang}'.\n\n" <>
            "# CONSTRAINTS\n" <>
            "1. Output ONLY a valid JSON object.\n" <>
            "2. 'translations': An array of strings. Each string MUST be the full translated unit with its original semantic tags (e.g., [[p_1]]...[[/p_1]]).\n" <>
            "3. 'context_summary': A brief one-sentence summary of the story/content so far to help the next translation batch.\n" <>
            "4. Do not include any explanations.\n\n" <>
            "# EXAMPLE\n" <>
            "Output: {\"translations\": [\"[[p_1]]...[[/p_1]]\"], \"context_summary\": \"The character has just arrived at the mysterious castle.\"}"
        ),
        Message.new_user!(
          if(prev_context, do: "**Previous Context Summary**: #{prev_context}\n\n", else: "") <>
            "**Target Language Code**: #{target_lang}\n\n" <>
            "**Units to translate into #{target_lang}**:\n#{source}"
        )
      ]

      run_translation_loop(llm, initial_messages, expected_keys, 3, selected_url)
    end
  end

  @spec classify_translation(config(), String.t(), String.t(), keyword()) ::
          {:ok, :translated | :not_translated | :ambiguous} | {:error, term()}
  def classify_translation(config, source, translated, opts \\ [])
      when is_map(config) and is_binary(source) and is_binary(translated) do
    usage_type = Keyword.get(opts, :usage_type, :validation)

    with {:ok, model_config, selected_url} <- build_model_config(config, usage_type) do
      llm = ChatOpenAI.new!(model_config)

      messages = [
        Message.new_system!(
          "# ROLE\nYou are a translation quality checker.\n\n" <>
            "# TASK\n" <>
            "Classify whether the translated text is actually translated from the source.\n\n" <>
            "# CONSTRAINTS\n" <>
            "1. Respond with ONE of: NOT_TRANSLATED, TRANSLATED, AMBIGUOUS.\n" <>
            "2. Output ONLY the token, no punctuation or explanation.\n" <>
            "3. Ignore placeholder tags like [[p_1]] or [[/p_1]].\n" <>
            "4. If the translation is mostly identical or unchanged, choose NOT_TRANSLATED.\n"
        ),
        Message.new_user!("SOURCE:\n#{source}\n\nTRANSLATION:\n#{translated}\n")
      ]

      case ChatOpenAI.call(llm, messages) do
        {:ok, response} ->
          result = response |> extract_text() |> parse_validation_result()
          if selected_url, do: LlmPool.checkin(selected_url)
          result

        {:error, reason} ->
          if selected_url, do: LlmPool.report_failure(selected_url)
          {:error, reason}
      end
    end
  end

  defp run_translation_loop(llm, messages, expected_keys, retries_left, url) do
    case ChatOpenAI.call(llm, messages) do
      {:ok, response} ->
        content_text = extract_text(response)

        case validate_and_parse(content_text, expected_keys) do
          {:ok, data, summary} ->
            if url, do: LlmPool.checkin(url)
            {:ok, data, summary, serialize_response(response)}

          {:error, feedback} when retries_left > 0 ->
            Logger.warning(
              "Translation validation failed. Retries left: #{retries_left}. Feedback: #{feedback}"
            )

            new_messages =
              messages ++
                [
                  Message.new_assistant!(content_text),
                  Message.new_user!(
                    "Your previous response had errors: #{feedback}. Please correct them and return the full JSON object again."
                  )
                ]

            run_translation_loop(llm, new_messages, expected_keys, retries_left - 1, url)

          {:error, _feedback} ->
            if url, do: LlmPool.checkin(url)

            case parse_best_effort(content_text) do
              {:ok, data, summary} -> {:ok, data, summary, serialize_response(response)}
              _ -> {:ok, content_text, nil, serialize_response(response)}
            end
        end

      {:error, reason} ->
        if url, do: LlmPool.report_failure(url)
        {:error, reason}
    end
  end

  defp validate_and_parse(text, expected_keys) do
    case Jason.decode(text) do
      {:ok, %{"translations" => list} = json} when is_list(list) ->
        parsed = parse_tagged_list(list)
        summary = Map.get(json, "context_summary")
        missing_keys = Enum.reject(expected_keys, &Map.has_key?(parsed, &1))

        cond do
          length(list) != length(expected_keys) ->
            {:error, "Expected #{length(expected_keys)} units, but got #{length(list)}."}

          missing_keys != [] ->
            {:error,
             "The following tags are missing or malformed: #{Enum.join(missing_keys, ", ")}."}

          true ->
            {:ok, parsed, summary}
        end

      _ ->
        {:error, "Invalid JSON format or missing 'translations' key."}
    end
  end

  defp parse_tagged_list(list) do
    Enum.reduce(list, %{}, fn entry, acc ->
      # Strict regex for unified key format [a-z0-9_]+
      case Regex.run(~r/\[\[([a-z0-9_]+)\]\](.*?)\[\[\/\1\]\]/s, entry) do
        [_, key, text] -> Map.put(acc, key, String.trim(text))
        _ -> acc
      end
    end)
  end

  defp parse_best_effort(text) do
    case Jason.decode(text) do
      {:ok, %{"translations" => list} = json} when is_list(list) ->
        {:ok, parse_tagged_list(list), Map.get(json, "context_summary")}

      _ ->
        :error
    end
  end

  defp translations_schema_payload do
    %{
      "type" => "json_schema",
      "json_schema" => %{
        "name" => "translation_response",
        "strict" => true,
        "schema" => %{
          "type" => "object",
          "properties" => %{
            "translations" => %{
              "type" => "array",
              "items" => %{"type" => "string"}
            },
            "context_summary" => %{"type" => "string"}
          },
          "required" => ["translations", "context_summary"],
          "additionalProperties" => false
        }
      }
    }
  end

  defp build_model_config(%{} = snapshot, usage_type) do
    case resolve_config(snapshot, usage_type) do
      nil ->
        {:error, :missing_llm_config}

      config ->
        config = normalize_config_map(config)

        raw_url =
          if config["id"] == "env" do
            System.get_env("LIVE_LLM_SERVER") || config["base_url"]
          else
            config["base_url"]
          end

        selected_url = LlmPool.checkout(raw_url)
        endpoint = endpoint_from_base_url(selected_url)

        attrs =
          %{
            endpoint: endpoint,
            model: config["model"],
            receive_timeout: 600_000,
            temperature: 0
          }
          |> maybe_put(:api_key, config["api_key"])
          |> Map.merge(settings_to_langchain_attrs(config["settings"]))

        {:ok, attrs, selected_url}
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

  defp extract_text(msg) do
    raw_extract_text(msg)
    |> sanitize_text()
  end

  defp sanitize_text(text) do
    text
    |> String.replace("&#91;", "[")
    |> String.replace("&#93;", "]")
  end

  defp raw_extract_text([%Message{} = first | _]), do: raw_extract_text(first)

  defp raw_extract_text(%Message{content: content}) when is_list(content) do
    content
    |> Enum.map(fn
      %LangChain.Message.ContentPart{type: :text, content: text} -> text
      _ -> ""
    end)
    |> Enum.join("")
  end

  defp raw_extract_text(%Message{content: content}) when is_binary(content), do: content
  defp raw_extract_text(%{content: content}) when is_binary(content), do: content
  defp raw_extract_text(_), do: ""

  defp parse_validation_result(text) do
    trimmed = String.trim(text)
    upper = String.upcase(trimmed)

    cond do
      upper in ["NOT_TRANSLATED", "NOT TRANSLATED"] -> {:ok, :not_translated}
      upper == "TRANSLATED" -> {:ok, :translated}
      upper == "AMBIGUOUS" -> {:ok, :ambiguous}
      trimmed in ["번역되지 않음", "번역 안됨"] -> {:ok, :not_translated}
      trimmed in ["번역됨"] -> {:ok, :translated}
      trimmed in ["모호함"] -> {:ok, :ambiguous}
      true -> {:ok, :ambiguous}
    end
  end

  defp serialize_response([%Message{} = first | _]), do: serialize_response(first)

  defp serialize_response(%Message{} = message) do
    metadata =
      case message.metadata do
        %{} = map -> Map.new(map, fn {k, v} -> {to_string(k), sanitize_metadata_value(v)} end)
        _ -> %{}
      end

    %{
      "role" => to_string(message.role),
      "content" => extract_text(message),
      "status" => to_string(message.status),
      "metadata" => metadata
    }
  end

  defp serialize_response(other) do
    %{"raw" => inspect(other)}
  end

  defp sanitize_metadata_value(%_{} = struct), do: Map.from_struct(struct)
  defp sanitize_metadata_value(%{} = map), do: map
  defp sanitize_metadata_value(other), do: other
end
