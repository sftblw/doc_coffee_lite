defmodule DocCoffeeLite.Repo.Migrations.AddUniqueIndexes do
  use Ecto.Migration

  def change do
    # Drop existing non-unique indexes that we want to replace with unique ones
    drop_if_exists index(:source_documents, [:project_id])
    
    create unique_index(:source_documents, [:project_id])
    create unique_index(:document_nodes, [:source_document_id, :node_id])
    create unique_index(:translation_groups, [:project_id, :group_key])
    create unique_index(:translation_units, [:translation_group_id, :unit_key])
    create unique_index(:glossary_terms, [:project_id, :source_text])
    create unique_index(:policy_sets, [:project_id, :policy_key])
    create unique_index(:llm_configs, [:project_id, :usage_type, :tier])
  end
end
