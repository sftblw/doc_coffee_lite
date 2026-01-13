defmodule DocCoffeeLite.Epub.Session do
  @moduledoc """
  Holds EPUB extraction state and pending file updates.
  """

  alias DocCoffeeLite.Epub.{Package, Reader, Writer}
  alias DocCoffeeLite.Epub.Path, as: EpubPath

  @type t :: %__MODULE__{
          source_path: String.t(),
          work_dir: String.t(),
          package: Package.t(),
          changes: %{optional(String.t()) => binary()}
        }

  @enforce_keys [:source_path, :work_dir, :package]
  defstruct [:source_path, :work_dir, :package, changes: %{}]

  @spec open(String.t(), String.t()) :: {:ok, t()} | {:error, term()}
  def open(epub_path, work_dir) do
    epub_path = Path.expand(epub_path)
    work_dir = Path.expand(work_dir)

    with {:ok, package} <- Reader.open(epub_path, work_dir) do
      {:ok, %__MODULE__{source_path: epub_path, work_dir: work_dir, package: package}}
    end
  end

  @spec content_paths(t()) :: [String.t()]
  def content_paths(%__MODULE__{package: %Package{content_paths: paths}}), do: paths || []

  @spec read_file(t(), String.t()) :: {:ok, binary()} | {:error, term()}
  def read_file(%__MODULE__{changes: changes} = session, path) do
    case Map.fetch(changes, path) do
      {:ok, content} -> {:ok, content}
      :error -> read_original_file(session, path)
    end
  end

  @spec update_file(t(), String.t(), iodata()) :: {:ok, t()} | {:error, term()}
  def update_file(%__MODULE__{} = session, path, content) do
    with :ok <- validate_path(path),
         {:ok, original} <- read_original_file(session, path) do
      content = IO.iodata_to_binary(content)

      changes =
        if original == content do
          Map.delete(session.changes, path)
        else
          Map.put(session.changes, path, content)
        end

      {:ok, %__MODULE__{session | changes: changes}}
    end
  end

  @spec build(t(), String.t()) :: :ok | {:error, term()}
  def build(%__MODULE__{} = session, output_path) do
    output_path = Path.expand(output_path)

    with :ok <- File.mkdir_p(Path.dirname(output_path)) do
      case session.changes do
        changes when map_size(changes) == 0 ->
          File.cp(session.source_path, output_path)

        _ ->
          with :ok <- apply_changes(session.work_dir, session.changes) do
            Writer.build(session.work_dir, output_path)
          end
      end
    end
  end

  defp read_original_file(%__MODULE__{work_dir: work_dir}, path) do
    with :ok <- validate_path(path),
         {:ok, full_path} <- EpubPath.safe_join(work_dir, path) do
      File.read(full_path)
    end
  end

  defp apply_changes(work_dir, changes) do
    Enum.reduce_while(changes, :ok, fn {path, content}, :ok ->
      with :ok <- validate_path(path),
           {:ok, full_path} <- EpubPath.safe_join(work_dir, path),
           :ok <- File.mkdir_p(Path.dirname(full_path)),
           :ok <- File.write(full_path, content) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_path(path) do
    case EpubPath.validate_relative_path(path) do
      :ok -> :ok
      {:error, reason} -> {:error, {:invalid_path, path, reason}}
    end
  end
end
