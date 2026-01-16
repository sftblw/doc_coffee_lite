defmodule DocCoffeeLite.Translation.Workers.LlmValidationWorker do
  @moduledoc """
  Uses LLM validation to flag untranslated units and mark them dirty.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias DocCoffeeLite.Translation
  alias DocCoffeeLite.Translation.LlmClient
  alias DocCoffeeLite.Translation.SimilarityGuard

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id} = args}) do
    search = Map.get(args, "search")
    run = Translation.get_latest_run(project_id)

    if is_nil(run) do
      {:error, :missing_translation_run}
    else
      units = Translation.list_units_for_similarity_scan(project_id, search: search)

      dirty_ids =
        units
        |> Enum.reduce([], fn unit, acc ->
          case Translation.get_latest_translation(unit) do
            nil ->
              acc

            bt ->
              case SimilarityGuard.classify(unit.source_text, bt.translated_text) do
                {:ok, _ratio, level} when level in [:medium, :high] ->
                  src = scrub_for_llm(unit.source_text)
                  dst = scrub_for_llm(bt.translated_text)

                  case LlmClient.classify_translation(run.llm_config_snapshot, src, dst,
                         usage_type: :validation
                       ) do
                    {:ok, :not_translated} -> [unit.id | acc]
                    _ -> acc
                  end

                _ ->
                  acc
              end
          end
        end)
        |> Enum.uniq()

      {count, _} = Translation.mark_units_dirty(dirty_ids)
      Logger.info("LLM validation scan complete: #{count} units marked dirty.")

      {:ok, %{dirty_count: count}}
    end
  end

  defp scrub_for_llm(text) when is_binary(text) do
    text
    |> String.replace(~r/\[\[[^\]]+\]\]/u, "")
    |> String.trim()
  end

  defp scrub_for_llm(_), do: ""
end
