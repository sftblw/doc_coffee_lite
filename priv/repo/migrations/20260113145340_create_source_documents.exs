defmodule DocCoffeeLite.Repo.Migrations.CreateSourceDocuments do
  use Ecto.Migration

  def change do
    create table(:source_documents) do
      add :format, :string
      add :source_path, :string
      add :work_dir, :string
      add :checksum, :string
      add :metadata, :map
      add :project_id, references(:projects, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:source_documents, [:project_id])
  end
end
