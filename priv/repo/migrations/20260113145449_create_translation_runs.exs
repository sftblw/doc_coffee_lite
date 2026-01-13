defmodule DocCoffeeLite.Repo.Migrations.CreateTranslationRuns do
  use Ecto.Migration

  def change do
    create table(:translation_runs) do
      add :status, :string
      add :progress, :integer
      add :policy_snapshot, :map
      add :glossary_snapshot, :map
      add :llm_config_snapshot, :map
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :project_id, references(:projects, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:translation_runs, [:project_id])
  end
end
