defmodule DocCoffeeLite.Translation.TranslationGroup do
  use Ecto.Schema
  import Ecto.Changeset

  schema "translation_groups" do
    field :status, :string, default: "pending"
    field :progress, :integer, default: 0
    field :position, :integer
    field :metadata, :map, default: %{}
    field :group_key, :string
    field :group_type, :string
    field :cursor, :integer, default: 0
    field :context_summary, :string
    
    belongs_to :project, DocCoffeeLite.Translation.Project
    belongs_to :source_document, DocCoffeeLite.Translation.SourceDocument
    belongs_to :document_node, DocCoffeeLite.Translation.DocumentNode
    has_many :translation_units, DocCoffeeLite.Translation.TranslationUnit

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(translation_group, attrs) do
    translation_group
    |> cast(attrs, [:project_id, :source_document_id, :document_node_id, :group_key, :group_type, :position, :status, :progress, :cursor, :context_summary, :metadata])
    |> validate_required([:group_key, :group_type, :position, :status, :progress, :cursor, :context_summary])
  end
end
