defmodule DocCoffeeLite.Translation.LlmSelector do
  @moduledoc """
  Selects active LLM configurations and builds run snapshots.
  """

  import Ecto.Query
  alias DocCoffeeLite.Repo
  alias DocCoffeeLite.Config.LlmConfig

  @default_usage_types [:translate, :policy, :validation, :glossary, :summary]
  @default_tiers [:cheap, :expensive]

  @type snapshot :: %{
          version: non_neg_integer(),
          selected_at: String.t(),
          configs: map(),
          missing: list(),
          metadata: map()
        }

  @spec snapshot(String.t(), keyword()) :: {:ok, snapshot()} | {:error, term()}
  def snapshot(project_id, opts \\ []) do
    usage_types = Keyword.get(opts, :usage_types, @default_usage_types)
    tiers = Keyword.get(opts, :tiers, @default_tiers)
    allow_missing? = Keyword.get(opts, :allow_missing?, false)

    configs = list_relevant_configs(project_id)
    
    {config_map, missing} = build_snapshot(configs, usage_types, tiers)

    snapshot = %{
      "version" => 1,
      "selected_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "configs" => config_map,
      "missing" => missing,
      "metadata" => %{
        "usage_types" => Enum.map(usage_types, &to_string/1),
        "tiers" => Enum.map(tiers, &to_string/1),
        "project_id" => project_id
      }
    }

    if missing != [] and not allow_missing? do
      {:error, {:missing_llm_config, missing}}
    else
      {:ok, snapshot}
    end
  end

  defp list_relevant_configs(project_id) do
    # Fetch project-specific and global fallback configs
    query = from c in LlmConfig,
      where: c.active == true and (c.project_id == ^project_id or is_nil(c.project_id)),
      order_by: [desc: c.project_id, desc: c.updated_at]
      
    Repo.all(query)
  end

  defp build_snapshot(configs, usage_types, tiers) do
    # Group by usage_type and tier
    # Project-specific configs will come first due to order_by
    grouped = Enum.group_by(configs, &{to_string(&1.usage_type), to_string(&1.tier)})
    global_fallback = Enum.find(configs, & &1.fallback)

    Enum.reduce(usage_types, {%{}, []}, fn usage_type, {acc, missing} ->
      {tier_map, missing} = 
        Enum.reduce(tiers, {%{}, missing}, fn tier, {tier_acc, missing} ->
          key = {to_string(usage_type), to_string(tier)}
          
          selected = 
            case Map.get(grouped, key) do
              [config | _] -> config
              _ -> global_fallback || env_fallback()
            end

          case selected do
            nil ->
              {tier_acc, ["#{usage_type}:#{tier}" | missing]}

            config ->
              {Map.put(tier_acc, to_string(tier), serialize_config(config)), missing}
          end
        end)

      {Map.put(acc, to_string(usage_type), tier_map), missing}
    end)
    |> then(fn {map, missing} ->
      {map, Enum.reverse(missing)}
    end)
  end

  defp env_fallback do
    server_env = System.get_env("LIVE_LLM_SERVER")
    model = System.get_env("LIVE_LLM_MODEL")

    if server_env && model do
      # Support multiple servers separated by comma
      servers = 
        server_env 
        |> String.split(",") 
        |> Enum.map(&String.trim/1) 
        |> Enum.reject(&(&1 == ""))

      %{
        id: "env",
        name: "Environment Fallback",
        usage_type: "any",
        tier: "any",
        provider: "ollama",
        model: model,
        base_url: if(length(servers) == 1, do: List.first(servers), else: servers),
        api_key: "ollama",
        settings: %{},
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }
    else
      nil
    end
  end

  defp serialize_config(%{id: "env"} = config), do: Map.new(config, fn {k, v} -> {to_string(k), v} end) |> Map.update!("inserted_at", &DateTime.to_iso8601/1) |> Map.update!("updated_at", &DateTime.to_iso8601/1)

  defp serialize_config(config) do
    %{ 
      "id" => config.id,
      "name" => config.name,
      "usage_type" => to_string(config.usage_type),
      "tier" => to_string(config.tier),
      "provider" => config.provider,
      "model" => config.model,
      "base_url" => config.base_url,
      "api_key" => config.api_key,
      "settings" => config.settings || %{},
      "inserted_at" => DateTime.to_iso8601(config.inserted_at),
      "updated_at" => DateTime.to_iso8601(config.updated_at)
    }
  end
end
