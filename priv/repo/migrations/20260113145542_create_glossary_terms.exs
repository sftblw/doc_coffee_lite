defmodule DocCoffeeLite.Repo.Migrations.CreateGlossaryTerms do
  use Ecto.Migration

  def change do
    create table(:glossary_terms) do
      add :source_text, :string
      add :target_text, :string
      add :status, :string
      add :source, :string
      add :notes, :text
      add :usage_count, :integer
      add :metadata, :map
      add :project_id, references(:projects, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:glossary_terms, [:project_id])
  end
end
