defmodule DocCoffeeLite.Epub.Package do
  @moduledoc """
  Struct representing an EPUB package after container and OPF parsing.
  """

  @enforce_keys [:rootfile_path, :rootfile_dir, :manifest, :spine, :spine_paths]
  @type t :: %__MODULE__{
          version: String.t() | nil,
          rootfile_path: String.t(),
          rootfile_dir: String.t(),
          metadata: map() | nil,
          manifest: map(),
          spine: [String.t()],
          spine_paths: [String.t()],
          content_paths: [String.t()] | nil,
          nav_path: String.t() | nil,
          toc_ncx_path: String.t() | nil
        }
  defstruct [
    :version,
    :rootfile_path,
    :rootfile_dir,
    :metadata,
    :manifest,
    :spine,
    :spine_paths,
    :content_paths,
    :nav_path,
    :toc_ncx_path
  ]
end
