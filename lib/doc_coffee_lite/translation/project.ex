defmodule DocCoffeeLite.Translation.Project do
  use Ecto.Schema
  import Ecto.Changeset

  schema "projects" do
    field :title, :string
    field :status, :string, default: "draft"
    field :progress, :integer, default: 0
    field :source_lang, :string
    field :target_lang, :string
    field :settings, :map, default: %{}

    has_one :source_document, DocCoffeeLite.Translation.SourceDocument
    has_many :translation_groups, DocCoffeeLite.Translation.TranslationGroup
    has_many :translation_runs, DocCoffeeLite.Translation.TranslationRun
    has_many :policy_sets, DocCoffeeLite.Translation.PolicySet
    has_many :glossary_terms, DocCoffeeLite.Translation.GlossaryTerm
    has_many :llm_configs, DocCoffeeLite.Config.LlmConfig

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(project, attrs) do
    project
    |> cast(attrs, [:title, :status, :progress, :source_lang, :target_lang, :settings])
    |> validate_required([:title, :status, :progress, :source_lang, :target_lang])
  end
end
