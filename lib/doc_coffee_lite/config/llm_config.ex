defmodule DocCoffeeLite.Config.LlmConfig do
  use Ecto.Schema
  import Ecto.Changeset

  schema "llm_configs" do
    field :active, :boolean, default: true
    field :name, :string
    field :api_key, :string
    field :provider, :string
    field :settings, :map, default: %{}
    field :fallback, :boolean, default: false
    field :base_url, :string
    field :model, :string
    field :tier, :string
    field :usage_type, :string
    
    belongs_to :project, DocCoffeeLite.Translation.Project

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(llm_config, attrs) do
    llm_config
    |> cast(attrs, [:project_id, :name, :usage_type, :tier, :provider, :model, :base_url, :api_key, :settings, :active, :fallback])
    |> validate_required([:name, :usage_type, :tier, :provider, :model, :base_url, :api_key, :active, :fallback])
  end
end
