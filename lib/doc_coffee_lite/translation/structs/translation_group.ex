defmodule DocCoffeeLite.Translation.Structs.TranslationGroup do
  @moduledoc """
  Segmented group of translation units within a document.
  """

  alias DocCoffeeLite.Translation.Structs.TranslationUnit

  @type group_type :: :file | :section | :window

  @type t :: %__MODULE__{
          group_key: String.t(),
          group_type: group_type(),
          position: non_neg_integer(),
          source_path: String.t(),
          node_id: String.t() | nil,
          units: [TranslationUnit.t()],
          metadata: map()
        }

  @enforce_keys [:group_key, :group_type, :position, :source_path]
  defstruct [
    :group_key,
    :group_type,
    :position,
    :source_path,
    :node_id,
    units: [],
    metadata: %{}
  ]
end
