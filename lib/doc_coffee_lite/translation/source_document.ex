defmodule DocCoffeeLite.Translation.SourceDocument do
  use Ecto.Schema
  import Ecto.Changeset

  schema "source_documents" do
    field :format, :string
    field :source_path, :string
    field :work_dir, :string
    field :checksum, :string
    field :metadata, :map, default: %{}
    
    belongs_to :project, DocCoffeeLite.Translation.Project
    has_many :document_nodes, DocCoffeeLite.Translation.DocumentNode
    has_many :translation_groups, DocCoffeeLite.Translation.TranslationGroup

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(source_document, attrs) do
    source_document
    |> cast(attrs, [:project_id, :format, :source_path, :work_dir, :checksum, :metadata])
    |> validate_required([:format, :source_path, :work_dir, :checksum])
  end
end
