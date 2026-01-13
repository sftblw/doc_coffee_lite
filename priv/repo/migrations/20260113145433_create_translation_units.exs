defmodule DocCoffeeLite.Repo.Migrations.CreateTranslationUnits do
  use Ecto.Migration

  def change do
    create table(:translation_units) do
      add :unit_key, :string
      add :status, :string
      add :position, :integer
      add :source_text, :text
      add :source_markup, :text
      add :placeholders, :map
      add :source_hash, :string
      add :metadata, :map
      add :translation_group_id, references(:translation_groups, on_delete: :nothing)
      add :document_node_id, references(:document_nodes, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:translation_units, [:translation_group_id])
    create index(:translation_units, [:document_node_id])
  end
end
