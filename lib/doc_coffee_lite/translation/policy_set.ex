defmodule DocCoffeeLite.Translation.PolicySet do
  use Ecto.Schema
  import Ecto.Changeset

  schema "policy_sets" do
    field :status, :string, default: "active"
    field :metadata, :map, default: %{}
    field :priority, :integer, default: 0
    field :source, :string, default: "auto"
    field :title, :string
    field :policy_key, :string
    field :policy_text, :string
    field :policy_type, :string
    
    belongs_to :project, DocCoffeeLite.Translation.Project

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(policy_set, attrs) do
    policy_set
    |> cast(attrs, [:project_id, :policy_key, :title, :policy_text, :policy_type, :source, :status, :priority, :metadata])
    |> validate_required([:policy_key, :title, :policy_text, :status])
  end
end
