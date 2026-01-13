defmodule DocCoffeeLite.Translation.DocumentTree do
  @moduledoc """
  Format-agnostic document structure produced by adapters before persistence.
  """

  alias DocCoffeeLite.Translation.DocumentTreeNode

  @type format :: :epub | :docx

  @type t :: %__MODULE__{
          format: format(),
          source_path: String.t(),
          work_dir: String.t() | nil,
          nodes: %{optional(String.t()) => DocumentTreeNode.t()},
          root_ids: [String.t()],
          metadata: map()
        }

  @enforce_keys [:format, :source_path, :nodes, :root_ids]
  defstruct [:format, :source_path, :work_dir, :nodes, :root_ids, metadata: %{}]
end
