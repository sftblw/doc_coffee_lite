defmodule DocCoffeeLite.Translation.GlossaryTerm do
  use Ecto.Schema
  import Ecto.Changeset

  schema "glossary_terms" do
    field :status, :string, default: "candidate"
    field :metadata, :map, default: %{}
    field :source, :string, default: "auto"
    field :source_text, :string
    field :target_text, :string
    field :notes, :string
    field :usage_count, :integer, default: 0

    belongs_to :project, DocCoffeeLite.Translation.Project

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(glossary_term, attrs) do
    glossary_term
    |> cast(attrs, [
      :project_id,
      :source_text,
      :target_text,
      :status,
      :source,
      :notes,
      :usage_count,
      :metadata
    ])
    |> validate_required([:source_text, :status])
  end
end
