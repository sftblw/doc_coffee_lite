defmodule DocCoffeeLite.Translation.Structs.TranslationUnit do
  @moduledoc """
  Translation unit extracted from a document group.
  """

  @type t :: %__MODULE__{
          unit_key: String.t(),
          position: non_neg_integer(),
          source_text: String.t(),
          source_markup: String.t(),
          placeholders: map(),
          source_hash: String.t() | nil,
          node_id: String.t() | nil,
          node_path: String.t() | nil,
          metadata: map()
        }

  @enforce_keys [:unit_key, :position, :source_text, :source_markup]
  defstruct [
    :unit_key,
    :position,
    :source_text,
    :source_markup,
    :placeholders,
    :source_hash,
    :node_id,
    :node_path,
    metadata: %{}
  ]
end
