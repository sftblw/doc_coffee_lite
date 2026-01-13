defmodule DocCoffeeLite.Repo.Migrations.CreateTranslationGroups do
  use Ecto.Migration

  def change do
    create table(:translation_groups) do
      add :group_key, :string
      add :group_type, :string
      add :position, :integer
      add :status, :string
      add :progress, :integer
      add :cursor, :integer
      add :context_summary, :text
      add :metadata, :map
      add :project_id, references(:projects, on_delete: :nothing)
      add :source_document_id, references(:source_documents, on_delete: :nothing)
      add :document_node_id, references(:document_nodes, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:translation_groups, [:project_id])
    create index(:translation_groups, [:source_document_id])
    create index(:translation_groups, [:document_node_id])
  end
end
