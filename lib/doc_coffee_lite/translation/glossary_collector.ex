defmodule DocCoffeeLite.Translation.GlossaryCollector do
  @moduledoc """
  Collects candidate glossary terms from translation units.
  """

  import Ecto.Query
  alias DocCoffeeLite.Repo
  alias DocCoffeeLite.Translation.GlossaryTerm
  alias DocCoffeeLite.Translation.TranslationUnit

  @default_max_terms 200
  @default_min_length 3
  @default_max_length 64

  @spec collect(String.t(), keyword()) :: {:ok, [GlossaryTerm.t()]} | {:error, term()}
  def collect(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_max_terms)
    min_length = Keyword.get(opts, :min_length, @default_min_length)
    max_length = Keyword.get(opts, :max_length, @default_max_length)

    units = load_units(project_id, opts)

    candidates =
      units
      |> Enum.flat_map(&extract_terms(&1.source_text, min_length, max_length))
      |> Enum.frequencies()
      |> Enum.sort_by(fn {_term, count} -> -count end)
      |> Enum.take(limit)

    persist_terms(project_id, candidates)
  end

  defp load_units(project_id, opts) do
    query =
      from u in TranslationUnit,
        join: g in assoc(u, :translation_group),
        where: g.project_id == ^project_id

    query =
      case Keyword.get(opts, :group_ids) do
        nil -> query
        [] -> query
        ids -> from u in query, where: u.translation_group_id in ^ids
      end

    query =
      case Keyword.get(opts, :status) do
        nil -> query
        [] -> query
        statuses -> from u in query, where: u.status in ^List.wrap(statuses)
      end

    Repo.all(query)
  end

  defp extract_terms(nil, _min_length, _max_length), do: []

  defp extract_terms(text, min_length, max_length) when is_binary(text) do
    text
    |> normalize_text()
    |> String.split(~r/[^[:alnum:]'’\-]+/u, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.trim(&1, "-'’"))
    |> Enum.filter(&valid_term?(&1, min_length, max_length))
  end

  defp normalize_text(text) do
    text
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp valid_term?(term, min_length, max_length) do
    length = String.length(term)

    length >= min_length and length <= max_length and
      String.match?(term, ~r/[[:alpha:]]/u)
  end

  defp persist_terms(project_id, candidates) do
    Repo.transaction(fn ->
      Enum.map(candidates, fn {term, count} ->
        attrs = %{
          project_id: project_id,
          source_text: term,
          status: "candidate",
          source: "auto",
          usage_count: count
        }

        %GlossaryTerm{}
        |> GlossaryTerm.changeset(attrs)
        |> Repo.insert!(
          on_conflict: {:replace_all_except, [:id, :inserted_at]},
          conflict_target: [:project_id, :source_text]
        )
      end)
    end)
  end
end
