defmodule DocCoffeeLite.Repo.Migrations.CreateProjects do
  use Ecto.Migration

  def change do
    create table(:projects) do
      add :title, :string
      add :status, :string
      add :progress, :integer
      add :source_lang, :string
      add :target_lang, :string
      add :settings, :map

      timestamps(type: :utc_datetime)
    end
  end
end
