defmodule DocCoffeeLite.Epub.Reader do
  @moduledoc """
  Reads and validates EPUB containers, then parses container and OPF metadata.
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
         {:ok, doc} <- parse_xml(xml, path: @container_path),
         [rootfile_path | _rest] <-
           xpath_attr(doc, "//*[local-name()='rootfile']/@full-path"),
         rootfile_path <- String.trim(rootfile_path),
         :ok <- EpubPath.validate_relative_path(rootfile_path) do
      {:ok, rootfile_path}
    else
      [] -> {:error, :missing_rootfile}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_container}
    end
  end

  defp read_opf(work_dir, rootfile_path) do
    rootfile_path = String.trim(rootfile_path)
    rootfile_dir = normalize_root_dir(Path.dirname(rootfile_path))

    with {:ok, xml} <- File.read(Path.join(work_dir, rootfile_path)),
         {:ok, doc} <- parse_xml(xml, path: rootfile_path),
         {:ok, manifest} <- parse_manifest(doc, rootfile_dir),
         {:ok, {spine, spine_toc_id}} <- parse_spine(doc),
         {:ok, spine_items} <- resolve_spine_items(manifest, spine) do
      version =
        doc
        |> xpath_attr("/*[local-name()='package']/@version")
        |> List.first()

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
    items = xpath(doc, "//*[local-name()='manifest']/*[local-name()='item']")

    Enum.reduce_while(items, {:ok, %{}}, fn item, {:ok, acc} ->
      {_, attrs, _} = :xmerl_lib.simplify_element(item)
      id = attr_value(attrs, :id)
      href = attr_value(attrs, :href)

      if is_nil(id) or is_nil(href) do
        {:halt, {:error, :invalid_manifest_item}}
      else
        case resolve_href(rootfile_dir, href) do
          {:ok, full_path} ->
            media_type = attr_value(attrs, :"media-type")
            properties = attr_value(attrs, :properties)

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
    case xpath(doc, "//*[local-name()='spine']") do
      [] ->
        {:error, :missing_spine}

      [spine_element | _rest] ->
        {_, attrs, _} = :xmerl_lib.simplify_element(spine_element)
        spine_toc_id = attr_value(attrs, :toc)

        itemrefs = xpath(doc, "//*[local-name()='spine']/*[local-name()='itemref']")

        spine =
          itemrefs
          |> Enum.map(fn itemref ->
            {_, item_attrs, _} = :xmerl_lib.simplify_element(itemref)
            attr_value(item_attrs, :idref)
          end)
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
    title = xpath_text(doc, "//*[local-name()='metadata']/*[local-name()='title']/text()")

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

  defp attr_value(attrs, name) do
    case List.keyfind(attrs, name, 0) do
      {^name, value} -> value |> to_string() |> String.trim()
      nil -> nil
    end
  end

  defp xpath(doc, path) do
    :xmerl_xpath.string(String.to_charlist(path), doc)
  end

  defp xpath_attr(doc, path) do
    doc
    |> xpath(path)
    |> Enum.map(&attr_from_node/1)
  end

  defp attr_from_node(
         {:xmlAttribute, _name, _expanded, _nsinfo, _namespace, _parents, _pos, _language, value,
          _normalized}
       ) do
    to_string(value)
  end

  defp attr_from_node(_), do: ""

  defp xpath_text(doc, path) do
    doc
    |> xpath(path)
    |> Enum.map(&text_from_node/1)
    |> Enum.join()
    |> String.trim()
  end

  defp text_from_node({:xmlText, _parents, _pos, _lang, value, _type}), do: to_string(value)
  defp text_from_node(value) when is_list(value), do: to_string(value)
  defp text_from_node(value) when is_binary(value), do: value
  defp text_from_node(_), do: ""

  defp parse_xml(xml, opts) do
    try do
      path = Keyword.get(opts, :path)

      xml = normalize_xml(xml)

      case scan_xml(xml) do
        {:ok, doc} ->
          {:ok, doc}

        {:error, reason} ->
          xml = force_utf8(xml)

          case scan_xml(xml) do
            {:ok, doc} ->
              {:ok, doc}

            {:error, reason2} ->
              {:error, {:xml_parse_error, %{path: path, first: reason, retry: reason2}}}
          end
      end
    catch
      _, reason -> {:error, {:xml_parse_error, %{path: Keyword.get(opts, :path), first: reason}}}
    end
  end

  defp scan_xml(xml) when is_binary(xml) do
    try do
      xml
      |> :erlang.binary_to_list()
      |> :xmerl_scan.string()
      |> case do
        {doc, _} -> {:ok, doc}
      end
    catch
      _, reason -> {:error, reason}
    end
  end

  defp force_utf8(xml) when is_binary(xml) do
    case :unicode.characters_to_binary(xml, :utf8, :utf8) do
      binary when is_binary(binary) -> binary
      _ -> xml
    end
  catch
    _, _ -> xml
  end

  defp normalize_xml(xml) when is_binary(xml) do
    xml
    |> strip_utf8_bom()
  end

  defp strip_utf8_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: rest
  defp strip_utf8_bom(xml), do: xml
end
