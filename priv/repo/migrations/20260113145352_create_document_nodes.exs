defmodule DocCoffeeLite.Repo.Migrations.CreateDocumentNodes do
  use Ecto.Migration

  def change do
    create table(:document_nodes) do
      add :node_id, :string
      add :node_type, :string
      add :source_path, :string
      add :node_path, :string
      add :position, :integer
      add :level, :integer
      add :title, :string
      add :metadata, :map
      add :source_document_id, references(:source_documents, on_delete: :nothing)
      add :parent_node_id, references(:document_nodes, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:document_nodes, [:source_document_id])
    create index(:document_nodes, [:parent_node_id])
  end
end
