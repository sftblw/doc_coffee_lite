defmodule DocCoffeeLite.Repo.Migrations.AddBlockTranslationsUniqueIndex do
  use Ecto.Migration

  def change do
    # Ensure any existing index with this name is removed before creating the unique one
    drop_if_exists index(:block_translations, [:translation_run_id, :translation_unit_id])
    
    create unique_index(:block_translations, [:translation_run_id, :translation_unit_id])
  end
end
