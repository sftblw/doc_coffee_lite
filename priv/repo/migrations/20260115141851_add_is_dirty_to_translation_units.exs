defmodule DocCoffeeLite.Repo.Migrations.AddIsDirtyToTranslationUnits do
  use Ecto.Migration

  def change do
    alter table(:translation_units) do
      add :is_dirty, :boolean, default: false, null: false
    end
  end
end
