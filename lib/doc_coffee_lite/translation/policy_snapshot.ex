defmodule DocCoffeeLite.Translation.PolicySnapshot do
  @moduledoc """
  Builds layered policy snapshots for translation runs.
  """

  import Ecto.Query
  alias DocCoffeeLite.Repo
  alias DocCoffeeLite.Translation.PolicySet

  @default_statuses ["active"]
  @default_source_rank %{"auto" => 1, "import" => 2, "user" => 3}

  @spec build(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def build(project_id, opts \\ []) do
    statuses = Keyword.get(opts, :statuses, @default_statuses) |> Enum.map(&to_string/1)

    policies = load_policies(project_id, statuses)
    {selected, overridden} = layer_policies(policies, opts)
    compiled_text = compile_text(selected)

    snapshot = %{
      "version" => 1,
      "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "compiled_text" => compiled_text,
      "policies" => Enum.map(selected, &serialize_policy/1),
      "metadata" => %{
        "total_count" => length(policies),
        "selected_count" => length(selected),
        "overridden_count" => length(overridden),
        "status_filter" => statuses
      }
    }

    {:ok, snapshot}
  end

  defp load_policies(project_id, statuses) do
    query =
      from p in PolicySet,
        where: p.project_id == ^project_id and p.status in ^statuses

    Repo.all(query)
  end

  defp layer_policies(policies, opts) do
    source_rank = Keyword.get(opts, :source_rank, @default_source_rank)
    groups = Enum.group_by(policies, & &1.policy_key)

    Enum.reduce(groups, {[], []}, fn {_key, entries}, {selected, overridden} ->
      best = pick_policy(entries, source_rank)
      others = Enum.reject(entries, &(&1 == best))
      {[best | selected], overridden ++ others}
    end)
    |> then(fn {selected, overridden} ->
      {sort_policies(selected), overridden}
    end)
  end

  defp pick_policy(policies, source_rank) do
    Enum.max_by(
      policies,
      fn policy ->
        {
          Map.get(source_rank, to_string(policy.source), 0),
          DateTime.to_unix(policy.updated_at || policy.inserted_at)
        }
      end,
      fn -> List.first(policies) end
    )
  end

  defp sort_policies(policies) do
    Enum.sort_by(policies, fn policy ->
      {policy.priority || 0, policy.policy_key || "", policy.title || ""}
    end)
  end

  defp compile_text(policies) do
    policies
    |> Enum.map(&format_policy_text/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  defp format_policy_text(policy) do
    title = policy.title || policy.policy_key || "Policy"
    body = String.trim(policy.policy_text || "")

    if body == "" do
      ""
    else
      "### #{title}\n#{body}"
    end
  end

  defp serialize_policy(policy) do
    %{
      "policy_id" => policy.id,
      "policy_key" => policy.policy_key,
      "title" => policy.title,
      "policy_text" => policy.policy_text,
      "policy_type" => to_string(policy.policy_type),
      "source" => to_string(policy.source),
      "status" => to_string(policy.status),
      "priority" => policy.priority || 0,
      "inserted_at" => DateTime.to_iso8601(policy.inserted_at),
      "updated_at" => DateTime.to_iso8601(policy.updated_at),
      "metadata" => policy.metadata || %{}
    }
  end
end
