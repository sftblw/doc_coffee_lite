defmodule DocCoffeeLite.Translation.Workers.ProjectHealingWorker do
  @moduledoc """
  Iterates through all BlockTranslations of the latest run for a project
  and applies AutoHealer to fix structure and restore whitespace.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1

  import Ecto.Query
  require Logger

  alias DocCoffeeLite.Repo
  alias DocCoffeeLite.Translation.Project
  alias DocCoffeeLite.Translation.BlockTranslation
  alias DocCoffeeLite.Translation.TranslationUnit
  alias DocCoffeeLite.Translation.AutoHealer
  alias DocCoffeeLite.Translation.Placeholder

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id}}) do
    project = Repo.get(Project, project_id) |> Repo.preload(:translation_runs)

    if project do
      latest_run = Enum.max_by(project.translation_runs, & &1.inserted_at, fn -> nil end)

      if latest_run do
        Logger.info("Starting AutoHealing for Project #{project_id}, Run #{latest_run.id}")
        heal_run(latest_run.id)
      else
        Logger.warning("No translation run found for Project #{project_id}")
        :ok
      end
    else
      {:error, :not_found}
    end
  end

  defp heal_run(run_id) do
    # Stream all BlockTranslations with their Source Unit
    # This avoids loading everything into memory
    query =
      from b in BlockTranslation,
        join: u in TranslationUnit,
        on: b.translation_unit_id == u.id,
        where: b.translation_run_id == ^run_id,
        select: {b, u}

    Repo.transaction(
      fn ->
        query
        |> Repo.stream()
        |> Enum.each(fn {block, unit} ->
          heal_block(block, unit)
        end)
      end,
      timeout: :infinity
    )

    Logger.info("Finished AutoHealing for Run #{run_id}")
    :ok
  end

  defp heal_block(block, unit) do
    # Only heal if it hasn't been healed or if we want to force re-heal.
    # For now, we force re-heal to ensure consistency.

    case AutoHealer.heal(unit.source_text, block.translated_text) do
      {:ok, healed_text} ->
        if healed_text != block.translated_text do
          update_block(block, healed_text, unit.placeholders, "ok")
        end

      {:error, %AutoHealer.HealError{} = err} ->
        Logger.debug("Skipping AutoHeal for block #{block.id}: #{err.message}")
        # Mark as failed in metadata but keep original text
        update_block(block, block.translated_text, unit.placeholders, "healing_failed")
    end
  end

  defp update_block(block, new_text, placeholders, status) do
    # Restore markup from new text
    new_markup = Placeholder.restore(new_text, placeholders || %{})

    # Merge metadata
    new_metadata = Map.put(block.metadata || %{}, "healing_status", status)
    new_metadata = Map.put(new_metadata, "healed_at", DateTime.utc_now() |> DateTime.to_iso8601())

    block
    |> BlockTranslation.changeset(%{
      translated_text: new_text,
      translated_markup: new_markup,
      metadata: new_metadata
    })
    |> Repo.update()
  end
end
