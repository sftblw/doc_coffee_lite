defmodule DocCoffeeLite.Translation.TranslationUnit do
  use Ecto.Schema
  import Ecto.Changeset

  schema "translation_units" do
    field :status, :string, default: "pending"
    field :position, :integer
    field :metadata, :map, default: %{}
    field :source_hash, :string
    field :source_markup, :string
    field :source_text, :string
    field :unit_key, :string
    field :placeholders, :map, default: %{}
    field :is_dirty, :boolean, default: false

    belongs_to :translation_group, DocCoffeeLite.Translation.TranslationGroup
    belongs_to :document_node, DocCoffeeLite.Translation.DocumentNode
    has_many :block_translations, DocCoffeeLite.Translation.BlockTranslation

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(translation_unit, attrs) do
    translation_unit
    |> cast(attrs, [
      :translation_group_id,
      :document_node_id,
      :unit_key,
      :status,
      :position,
      :source_text,
      :source_markup,
      :placeholders,
      :source_hash,
      :metadata,
      :is_dirty
    ])
    |> validate_required([
      :unit_key,
      :status,
      :position,
      :source_text,
      :source_markup,
      :source_hash
    ])
  end
end
