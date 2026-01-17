defmodule DocCoffeeLite.Translation.TranslationRun do
  use Ecto.Schema
  import Ecto.Changeset

  schema "translation_runs" do
    field :status, :string, default: "draft"
    field :progress, :integer, default: 0
    field :policy_snapshot, :map, default: %{}
    field :glossary_snapshot, :map, default: %{}
    field :llm_config_snapshot, :map, default: %{}
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :project, DocCoffeeLite.Translation.Project
    has_many :block_translations, DocCoffeeLite.Translation.BlockTranslation

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(translation_run, attrs) do
    translation_run
    |> cast(attrs, [
      :project_id,
      :status,
      :progress,
      :policy_snapshot,
      :glossary_snapshot,
      :llm_config_snapshot,
      :started_at,
      :completed_at
    ])
    |> validate_required([:status, :progress])
    |> unique_constraint(:project_id)
  end
end
