defmodule DocCoffeeLite.Epub.Reader do
  @moduledoc """
  Reads and validates EPUB containers, then parses container and OPF metadata using Floki.
  """

  alias DocCoffeeLite.Epub.Package
  alias DocCoffeeLite.Epub.Path, as: EpubPath

  @container_path "META-INF/container.xml"
  @xhtml_media_types [
    "application/xhtml+xml",
    "application/x-dtbook+xml",
    "text/html"
  ]

  @spec open(String.t(), String.t()) :: {:ok, Package.t()} | {:error, term()}
  def open(epub_path, work_dir) do
    with :ok <- extract(epub_path, work_dir),
         {:ok, package} <- read_package(work_dir) do
      {:ok, package}
    end
  end

  @spec extract(String.t(), String.t()) :: :ok | {:error, term()}
  def extract(epub_path, work_dir) do
    epub_path = Path.expand(epub_path)
    work_dir = Path.expand(work_dir)

    with :ok <- ensure_regular_file(epub_path),
         :ok <- ensure_empty_dir(work_dir),
         :ok <- File.mkdir_p(work_dir),
         :ok <- validate_zip_entries(epub_path),
         :ok <- unzip(epub_path, work_dir),
         :ok <- validate_mimetype(work_dir) do
      :ok
    end
  end

  @spec read_package(String.t()) :: {:ok, Package.t()} | {:error, term()}
  def read_package(work_dir) do
    work_dir = Path.expand(work_dir)

    with :ok <- validate_mimetype(work_dir),
         {:ok, rootfile_path} <- read_container(work_dir),
         {:ok, package} <- read_opf(work_dir, rootfile_path) do
      {:ok, package}
    end
  end

  defp ensure_regular_file(path) do
    case File.stat(path) do
      {:ok, %{type: :regular}} -> :ok
      {:ok, _} -> {:error, :not_a_file}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_empty_dir(path) do
    case File.ls(path) do
      {:ok, []} -> :ok
      {:ok, _} -> {:error, :work_dir_not_empty}
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_zip_entries(epub_path) do
    case :zip.list_dir(String.to_charlist(epub_path)) do
      {:ok, entries} ->
        Enum.reduce_while(entries, :ok, fn
          {:zip_file, name, _info, _comment, _offset, _comp_size}, :ok ->
            path = List.to_string(name)

            if EpubPath.safe_entry_path?(path) do
              {:cont, :ok}
            else
              {:halt, {:error, {:unsafe_entry, path}}}
            end

          {:zip_comment, _}, acc ->
            {:cont, acc}
        end)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp unzip(epub_path, work_dir) do
    cwd = String.to_charlist(work_dir)

    file_filter = fn
      {:zip_file, name, _info, _comment, _offset, _comp_size} ->
        EpubPath.safe_entry_path?(List.to_string(name))

      _ ->
        false
    end

    case :zip.unzip(String.to_charlist(epub_path), [
           {:cwd, cwd},
           {:file_filter, file_filter}
         ]) do
      {:ok, _files} -> :ok
      {:error, reason} -> {:error, reason}
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

  defp read_container(work_dir) do
    container_path = Path.join(work_dir, @container_path)

    with {:ok, xml} <- File.read(container_path),
         {:ok, doc} <- parse_xml(xml),
         rootfile_path when is_binary(rootfile_path) <- find_rootfile_path(doc),
         rootfile_path <- String.trim(rootfile_path),
         :ok <-EpubPath.validate_relative_path(rootfile_path) do
      {:ok, rootfile_path}
    else
      nil -> {:error, :missing_rootfile}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_container}
    end
  end

  defp find_rootfile_path(doc) do
    doc
    |> Floki.find("rootfile")
    |> Floki.attribute("full-path")
    |> List.first()
  end

  defp read_opf(work_dir, rootfile_path) do
    rootfile_path = String.trim(rootfile_path)
    rootfile_dir = normalize_root_dir(Path.dirname(rootfile_path))

    with {:ok, xml} <- File.read(Path.join(work_dir, rootfile_path)),
         {:ok, doc} <- parse_xml(xml),
         {:ok, manifest} <- parse_manifest(doc, rootfile_dir),
         {:ok, {spine, spine_toc_id}} <- parse_spine(doc),
         {:ok, spine_items} <- resolve_spine_items(manifest, spine) do
      
      version = doc |> Floki.find("package") |> Floki.attribute("version") |> List.first()
      metadata = parse_metadata(doc)
      nav_path = find_nav_path(manifest)
      toc_ncx_path = find_toc_ncx_path(manifest, spine_toc_id)

      spine_paths = Enum.map(spine_items, & &1.full_path)

      content_paths =
        spine_items
        |> Enum.filter(&content_item?/1)
        |> Enum.map(& &1.full_path)

      package = %Package{
        version: version,
        rootfile_path: rootfile_path,
        rootfile_dir: rootfile_dir,
        metadata: metadata,
        manifest: manifest,
        spine: spine,
        spine_paths: spine_paths,
        content_paths: content_paths,
        nav_path: nav_path,
        toc_ncx_path: toc_ncx_path
      }

      {:ok, package}
    end
  end

  defp parse_manifest(doc, rootfile_dir) do
    items = Floki.find(doc, "manifest item")

    Enum.reduce_while(items, {:ok, %{}}, fn item, {:ok, acc} ->
      id = attr_value(item, "id")
      href = attr_value(item, "href")

      if is_nil(id) or is_nil(href) do
        {:halt, {:error, :invalid_manifest_item}}
      else
        case resolve_href(rootfile_dir, href) do
          {:ok, full_path} ->
            media_type = attr_value(item, "media-type")
            properties = attr_value(item, "properties")

            item_map = %{
              id: id,
              href: href,
              full_path: full_path,
              media_type: media_type,
              properties: split_properties(properties)
            }

            {:cont, {:ok, Map.put(acc, id, item_map)}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end
    end)
  end

  defp parse_spine(doc) do
    case Floki.find(doc, "spine") do
      [] ->
        {:error, :missing_spine}

      [spine_element | _rest] ->
        spine_toc_id = attr_value(spine_element, "toc")
        itemrefs = Floki.find(spine_element, "itemref")

        spine =
          itemrefs
          |> Enum.map(fn itemref -> attr_value(itemref, "idref") end)
          |> Enum.reject(&is_nil/1)

        {:ok, {spine, spine_toc_id}}
    end
  end

  defp resolve_spine_items(manifest, spine) do
    {spine_items, missing_ids} =
      Enum.reduce(spine, {[], []}, fn id, {items, missing} ->
        case Map.get(manifest, id) do
          nil -> {items, [id | missing]}
          item -> {[item | items], missing}
        end
      end)

    case missing_ids do
      [] -> {:ok, Enum.reverse(spine_items)}
      _ -> {:error, {:missing_spine_items, Enum.reverse(missing_ids)}}
    end
  end

  defp parse_metadata(doc) do
    title =
      doc
      |> Floki.find("metadata > title, metadata > dc\:title")
      |> Floki.text(sep: " ")
      |> String.trim()

    if title == "" do
      %{}
    else
      %{title: title}
    end
  end

  defp content_item?(item) do
    case item.media_type do
      media_type when is_binary(media_type) ->
        media_type in @xhtml_media_types

      _ ->
        String.ends_with?(item.full_path, [".xhtml", ".html", ".htm"])
    end
  end

  defp find_nav_path(manifest) do
    manifest
    |> Map.values()
    |> Enum.find(fn item -> Enum.member?(item.properties, "nav") end)
    |> case do
      nil -> nil
      item -> item.full_path
    end
  end

  defp find_toc_ncx_path(manifest, spine_toc_id) do
    cond do
      is_binary(spine_toc_id) and Map.has_key?(manifest, spine_toc_id) ->
        manifest[spine_toc_id].full_path

      true ->
        manifest
        |> Map.values()
        |> Enum.find(fn item -> item.media_type == "application/x-dtbncx+xml" end)
        |> case do
          nil -> nil
          item -> item.full_path
        end
    end
  end

  defp resolve_href(rootfile_dir, href) do
    [path | _rest] = String.split(href, "#", parts: 2)
    path = String.trim(path)

    with :ok <- EpubPath.validate_relative_path(path) do
      full_path = Path.expand(Path.join(rootfile_dir, path), "/")
      relative_path = String.trim_leading(full_path, "/")

      case EpubPath.validate_relative_path(relative_path) do
        :ok -> {:ok, relative_path}
        {:error, reason} -> {:error, {:invalid_href, href, reason}}
      end
    else
      {:error, reason} -> {:error, {:invalid_href, href, reason}}
    end
  end

  defp normalize_root_dir("."), do: ""
  defp normalize_root_dir(path), do: path

  defp split_properties(nil), do: []

  defp split_properties(value) do
    value
    |> to_string()
    |> String.split(~r/\s+/, trim: true)
  end

  defp attr_value(element, name) do
    case Floki.attribute(element, name) do
      [value | _] -> String.trim(value)
      _ -> nil
    end
  end

  defp parse_xml(xml) do
    case Floki.parse_document(xml) do
      {:ok, doc} -> {:ok, doc}
      {:error, reason} -> {:error, {:xml_parse_error, reason}}
    end
  end
end