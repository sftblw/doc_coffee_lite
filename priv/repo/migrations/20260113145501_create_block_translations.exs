defmodule DocCoffeeLite.Repo.Migrations.CreateBlockTranslations do
  use Ecto.Migration

  def change do
    create table(:block_translations) do
      add :status, :string
      add :translated_text, :text
      add :translated_markup, :text
      add :placeholders, :map
      add :llm_response, :map
      add :metrics, :map
      add :metadata, :map
      add :translation_run_id, references(:translation_runs, on_delete: :nothing)
      add :translation_unit_id, references(:translation_units, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:block_translations, [:translation_run_id])
    create index(:block_translations, [:translation_unit_id])
  end
end
