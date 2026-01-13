defmodule DocCoffeeLite.Repo.Migrations.CreateLlmConfigs do
  use Ecto.Migration

  def change do
    create table(:llm_configs) do
      add :name, :string
      add :usage_type, :string
      add :tier, :string
      add :provider, :string
      add :model, :string
      add :base_url, :string
      add :api_key, :string
      add :settings, :map
      add :active, :boolean, default: false, null: false
      add :fallback, :boolean, default: false, null: false
      add :project_id, references(:projects, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:llm_configs, [:project_id])
  end
end
