defmodule DocCoffeeLite.Repo.Migrations.EnsureSingleTranslationRunPerProject do
  use Ecto.Migration

  def up do
    create table(:block_translation_archives) do
      add :block_translation_id, :bigint
      add :project_id, references(:projects, on_delete: :nothing)
      add :translation_run_id, references(:translation_runs, on_delete: :nothing)
      add :translation_unit_id, references(:translation_units, on_delete: :nothing)
      add :status, :string
      add :translated_text, :text
      add :translated_markup, :text
      add :placeholders, :map
      add :llm_response, :map
      add :metrics, :map
      add :metadata, :map
      add :original_inserted_at, :utc_datetime
      add :original_updated_at, :utc_datetime
      add :archived_at, :utc_datetime
    end

    create index(:block_translation_archives, [:project_id])
    create index(:block_translation_archives, [:translation_unit_id])

    execute("""
    WITH ranked AS (
      SELECT
        bt.id,
        tr.project_id,
        ROW_NUMBER() OVER (
          PARTITION BY tr.project_id, bt.translation_unit_id
          ORDER BY bt.updated_at DESC NULLS LAST, bt.inserted_at DESC, bt.id DESC
        ) AS rn
      FROM block_translations bt
      JOIN translation_runs tr ON tr.id = bt.translation_run_id
      WHERE tr.project_id IS NOT NULL
    )
    INSERT INTO block_translation_archives (
      block_translation_id,
      project_id,
      translation_run_id,
      translation_unit_id,
      status,
      translated_text,
      translated_markup,
      placeholders,
      llm_response,
      metrics,
      metadata,
      original_inserted_at,
      original_updated_at,
      archived_at
    )
    SELECT
      bt.id,
      tr.project_id,
      bt.translation_run_id,
      bt.translation_unit_id,
      bt.status,
      bt.translated_text,
      bt.translated_markup,
      bt.placeholders,
      bt.llm_response,
      bt.metrics,
      bt.metadata,
      bt.inserted_at,
      bt.updated_at,
      NOW()
    FROM ranked r
    JOIN block_translations bt ON bt.id = r.id
    JOIN translation_runs tr ON tr.id = bt.translation_run_id
    WHERE r.rn > 1;
    """)

    execute("""
    WITH ranked AS (
      SELECT
        bt.id,
        tr.project_id,
        ROW_NUMBER() OVER (
          PARTITION BY tr.project_id, bt.translation_unit_id
          ORDER BY bt.updated_at DESC NULLS LAST, bt.inserted_at DESC, bt.id DESC
        ) AS rn
      FROM block_translations bt
      JOIN translation_runs tr ON tr.id = bt.translation_run_id
      WHERE tr.project_id IS NOT NULL
    )
    DELETE FROM block_translations bt
    USING ranked r
    WHERE bt.id = r.id AND r.rn > 1;
    """)

    execute("""
    WITH canonical_runs AS (
      SELECT id, project_id
      FROM (
        SELECT
          id,
          project_id,
          ROW_NUMBER() OVER (
            PARTITION BY project_id
            ORDER BY inserted_at DESC, id DESC
          ) AS rn
        FROM translation_runs
        WHERE project_id IS NOT NULL
      ) ranked
      WHERE rn = 1
    )
    UPDATE block_translations bt
    SET translation_run_id = cr.id
    FROM translation_runs tr
    JOIN canonical_runs cr ON cr.project_id = tr.project_id
    WHERE bt.translation_run_id = tr.id AND tr.id <> cr.id;
    """)

    execute("""
    WITH ranked AS (
      SELECT
        id,
        project_id,
        ROW_NUMBER() OVER (
          PARTITION BY project_id
          ORDER BY inserted_at DESC, id DESC
        ) AS rn
      FROM translation_runs
      WHERE project_id IS NOT NULL
    )
    DELETE FROM translation_runs tr
    USING ranked r
    WHERE tr.id = r.id AND r.rn > 1;
    """)

    drop_if_exists index(:translation_runs, [:project_id])
    create unique_index(:translation_runs, [:project_id])
  end

  def down do
    drop_if_exists index(:translation_runs, [:project_id])
    drop_if_exists table(:block_translation_archives)
  end
end
