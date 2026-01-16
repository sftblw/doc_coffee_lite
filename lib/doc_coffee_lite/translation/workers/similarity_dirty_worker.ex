defmodule DocCoffeeLite.Translation.Workers.SimilarityDirtyWorker do
  @moduledoc """
  Marks units as dirty when translated text is too similar to the source.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias DocCoffeeLite.Translation
  alias DocCoffeeLite.Translation.SimilarityGuard

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id} = args}) do
    search = Map.get(args, "search")

    units = Translation.list_units_for_similarity_scan(project_id, search: search)

    dirty_ids =
      units
      |> Enum.reduce([], fn unit, acc ->
        case Translation.get_latest_translation(unit) do
          nil ->
            acc

          bt ->
            case SimilarityGuard.check(unit.source_text, bt.translated_text) do
              {:ok, _ratio} -> acc
              {:skip, _ratio} -> acc
              {:error, %SimilarityGuard.SimilarityError{}} -> [unit.id | acc]
            end
        end
      end)
      |> Enum.uniq()

    {count, _} = Translation.mark_units_dirty(dirty_ids)
    Logger.info("Similarity dirty scan complete: #{count} units marked.")

    {:ok, %{dirty_count: count}}
  end
end
