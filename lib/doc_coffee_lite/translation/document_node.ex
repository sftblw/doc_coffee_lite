defmodule DocCoffeeLite.Translation.DocumentNode do
  use Ecto.Schema
  import Ecto.Changeset

  schema "document_nodes" do
    field :node_id, :string
    field :node_type, :string
    field :source_path, :string
    field :node_path, :string
    field :position, :integer
    field :level, :integer
    field :title, :string
    field :metadata, :map, default: %{}
    
    belongs_to :source_document, DocCoffeeLite.Translation.SourceDocument
    belongs_to :parent_node, DocCoffeeLite.Translation.DocumentNode, foreign_key: :parent_node_id
    has_many :child_nodes, DocCoffeeLite.Translation.DocumentNode, foreign_key: :parent_node_id
    has_many :translation_groups, DocCoffeeLite.Translation.TranslationGroup
    has_many :translation_units, DocCoffeeLite.Translation.TranslationUnit

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(document_node, attrs) do
    document_node
    |> cast(attrs, [:source_document_id, :parent_node_id, :node_id, :node_type, :source_path, :node_path, :position, :level, :title, :metadata])
    |> validate_required([:node_id, :node_type, :source_path, :position, :level])
  end
end
