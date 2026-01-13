defmodule DocCoffeeLite.Repo.Migrations.CreatePolicySets do
  use Ecto.Migration

  def change do
    create table(:policy_sets) do
      add :policy_key, :string
      add :title, :string
      add :policy_text, :text
      add :policy_type, :string
      add :source, :string
      add :status, :string
      add :priority, :integer
      add :metadata, :map
      add :project_id, references(:projects, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:policy_sets, [:project_id])
  end
end
