defmodule DocCoffeeLite.Translation.BlockTranslation do
  use Ecto.Schema
  import Ecto.Changeset

  schema "block_translations" do
    field :status, :string, default: "translated"
    field :metadata, :map, default: %{}
    field :placeholders, :map, default: %{}
    field :llm_response, :map, default: %{}
    field :metrics, :map, default: %{}
    field :translated_markup, :string
    field :translated_text, :string

    belongs_to :translation_run, DocCoffeeLite.Translation.TranslationRun
    belongs_to :translation_unit, DocCoffeeLite.Translation.TranslationUnit

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(block_translation, attrs) do
    block_translation
    |> cast(attrs, [
      :translation_run_id,
      :translation_unit_id,
      :status,
      :translated_text,
      :translated_markup,
      :placeholders,
      :llm_response,
      :metrics,
      :metadata
    ])
    |> validate_required([:status])
  end
end
