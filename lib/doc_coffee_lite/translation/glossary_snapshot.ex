defmodule DocCoffeeLite.Translation.GlossarySnapshot do
  @moduledoc """
  Builds glossary snapshots for translation runs.
  """

  import Ecto.Query
  alias DocCoffeeLite.Repo
  alias DocCoffeeLite.Translation.GlossaryTerm

  @default_statuses ["approved", "candidate"]

  @spec build(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def build(project_id, opts \\ []) do
    statuses = Keyword.get(opts, :statuses, @default_statuses) |> Enum.map(&to_string/1)
    limit = Keyword.get(opts, :limit)
    min_usage = Keyword.get(opts, :min_usage)

    query =
      from g in GlossaryTerm,
        where: g.project_id == ^project_id and g.status in ^statuses,
        order_by: [desc: g.usage_count, asc: g.source_text]

    query = if min_usage, do: from(g in query, where: g.usage_count >= ^min_usage), else: query
    query = if limit, do: from(g in query, limit: ^limit), else: query

    terms = Repo.all(query)

    snapshot = %{
      "version" => 1,
      "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "terms" => Enum.map(terms, &serialize_term/1),
      "metadata" => %{
        "total_count" => length(terms),
        "status_filter" => statuses,
        "min_usage" => min_usage,
        "limit" => limit
      }
    }

    {:ok, snapshot}
  end

  defp serialize_term(term) do
    %{
      "term_id" => term.id,
      "source_text" => term.source_text,
      "target_text" => term.target_text,
      "status" => to_string(term.status),
      "source" => to_string(term.source),
      "usage_count" => term.usage_count || 0,
      "notes" => term.notes,
      "inserted_at" => DateTime.to_iso8601(term.inserted_at),
      "updated_at" => DateTime.to_iso8601(term.updated_at),
      "metadata" => term.metadata || %{}
    }
  end
end
