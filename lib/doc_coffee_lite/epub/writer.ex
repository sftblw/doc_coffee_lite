defmodule DocCoffeeLite.Epub.Writer do
  @moduledoc """
  Builds a valid EPUB archive from a working directory.
  """

  @spec build(String.t(), String.t()) :: :ok | {:error, term()}
  def build(work_dir, output_path) do
    work_dir = Path.expand(work_dir)
    output_path = Path.expand(output_path)

    with :ok <- validate_mimetype(work_dir),
         {:ok, file_list} <- collect_files(work_dir),
         :ok <- File.mkdir_p(Path.dirname(output_path)),
         :ok <- create_zip(work_dir, output_path, file_list) do
      :ok
    end
  end

  defp validate_mimetype(work_dir) do
    mimetype_path = Path.join(work_dir, "mimetype")

    case File.read(mimetype_path) do
      {:ok, content} ->
        if String.trim(content) == DocCoffeeLite.Epub.mimetype_value() do
          :ok
        else
          {:error, :invalid_mimetype}
        end

      {:error, reason} ->
        {:error, {:missing_mimetype, reason}}
    end
  end

  defp collect_files(work_dir) do
    files =
      work_dir
      |> Path.join("**/*")
      |> Path.wildcard()
      |> Enum.filter(&File.regular?/1)

    relative_paths = Enum.map(files, &Path.relative_to(&1, work_dir))

    if "mimetype" in relative_paths do
      others =
        relative_paths
        |> Enum.reject(&(&1 == "mimetype"))
        |> Enum.sort()

      {:ok, ["mimetype" | others]}
    else
      {:error, :missing_mimetype_file}
    end
  end

  defp create_zip(work_dir, output_path, file_list) do
    zip_path = String.to_charlist(output_path)
    cwd = String.to_charlist(work_dir)
    entries = Enum.map(file_list, &String.to_charlist/1)

    options = [
      {:cwd, cwd},
      {:uncompress, {:add, [~c""]}}
    ]

    case :zip.create(zip_path, entries, options) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
