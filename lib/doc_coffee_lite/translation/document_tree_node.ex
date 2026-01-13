defmodule DocCoffeeLite.Translation.DocumentTreeNode do
  @moduledoc """
  Node for the format-agnostic document tree.
  """

  @type node_type ::
          :document
          | :file
          | :section
          | :heading
          | :block
          | :table
          | :row
          | :cell
          | :code
          | :list
          | :list_item
          | :image

  @type t :: %__MODULE__{
          node_id: String.t(),
          node_type: node_type(),
          source_path: String.t(),
          node_path: String.t() | nil,
          position: non_neg_integer(),
          level: non_neg_integer(),
          title: String.t() | nil,
          parent_id: String.t() | nil,
          children_ids: [String.t()],
          metadata: map()
        }

  @enforce_keys [:node_id, :node_type, :source_path]
  defstruct [
    :node_id,
    :node_type,
    :source_path,
    :node_path,
    :position,
    :level,
    :title,
    :parent_id,
    children_ids: [],
    metadata: %{}
  ]
end
