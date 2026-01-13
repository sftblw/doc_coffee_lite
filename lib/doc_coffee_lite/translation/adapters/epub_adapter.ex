defmodule DocCoffeeLite.Translation.Adapters.EpubAdapter do
  @moduledoc """
  Builds a format-agnostic DocumentTree and translation groups from EPUB content.
  """

  alias DocCoffeeLite.Epub.Session
  alias DocCoffeeLite.Translation.DocumentTree
  alias DocCoffeeLite.Translation.DocumentTreeNode
  alias DocCoffeeLite.Translation.Structs.TranslationGroup
  alias DocCoffeeLite.Translation.Structs.TranslationUnit

  @block_tags ~w(
    p
    h1
    h2
    h3
    h4
    h5
    h6
    li
    dt
    dd
    pre
    code
    blockquote
    td
    th
    figcaption
    caption
  )

  @block_xpath @block_tags
               |> Enum.map(&"local-name()='#{&1}'")
               |> Enum.join(" or ")
               |> then(&".//*[#{&1}]")

  @spec build(Session.t()) ::
          {:ok, %{tree: DocumentTree.t(), groups: [TranslationGroup.t()]}}
          | {:error, term()}
  def build(%Session{} = session) do
    content_paths = Session.content_paths(session)
    root_id = "doc:root"

    root_node = %DocumentTreeNode{
      node_id: root_id,
      node_type: :document,
      source_path: session.source_path,
      position: 0,
      level: 0,
      title: tree_title(session),
      parent_id: nil,
      children_ids: []
    }

    base_nodes = %{root_id => root_node}

    case build_groups(session, content_paths, root_id, base_nodes) do
      {:ok, {nodes, groups, file_ids}} ->
        root_node = %DocumentTreeNode{root_node | children_ids: Enum.reverse(file_ids)}
        nodes = Map.put(nodes, root_id, root_node)

        tree = %DocumentTree{
          format: :epub,
          source_path: session.source_path,
          work_dir: session.work_dir,
          nodes: nodes,
          root_ids: [root_id],
          metadata: tree_metadata(session)
        }

        {:ok, %{tree: tree, groups: Enum.reverse(groups)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_groups(session, content_paths, root_id, nodes) do
    Enum.reduce_while(Enum.with_index(content_paths), {:ok, {nodes, [], []}}, fn {path, index},
                                                                                 {:ok,
                                                                                  {nodes, groups,
                                                                                   file_ids}} ->
      case build_group(session, path, index, root_id) do
        {:ok, {file_node, block_nodes, group}} ->
          nodes =
            nodes
            |> Map.put(file_node.node_id, file_node)
            |> Map.merge(block_nodes)

          {:cont, {:ok, {nodes, [group | groups], [file_node.node_id | file_ids]}}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp build_group(session, path, index, root_id) do
    with {:ok, xml} <- Session.read_file(session, path),
         {:ok, elements} <- block_elements(xml) do
      file_node_id = "file:#{path}"

      {units, block_nodes, child_ids} = build_units(elements, path, file_node_id)

      file_node = %DocumentTreeNode{
        node_id: file_node_id,
        node_type: :file,
        source_path: path,
        node_path: path,
        position: index,
        level: 1,
        parent_id: root_id,
        children_ids: child_ids
      }

      group = %TranslationGroup{
        group_key: path,
        group_type: :file,
        position: index,
        source_path: path,
        node_id: file_node_id,
        units: units
      }

      {:ok, {file_node, block_nodes, group}}
    else
      {:error, reason} -> {:error, {:epub_parse_failed, path, reason}}
    end
  end

  defp block_elements(xml) when is_binary(xml) do
    with {:ok, doc} <- Floki.parse_document(xml),
         body <- Floki.find(doc, "body") |> List.first() do
      container = body || doc

      elements = Floki.find(container, @block_xpath)
      elements = if elements == [], do: Floki.children(container), else: elements
      elements = Enum.filter(elements, &match?({_, _, _}, &1))

      {:ok, elements}
    end
  end

  defp build_units(elements, path, file_node_id) do
    elements
    |> Enum.map(&element_payload/1)
    |> Enum.reject(&blank_payload?/1)
    |> Enum.with_index()
    |> Enum.reduce({[], %{}, []}, fn {payload, index}, {units, nodes, child_ids} ->
      position = index
      node_id = "block:#{path}:#{position}"
      node_path = "body/#{payload.tag}[#{index + 1}]"

      node = %DocumentTreeNode{
        node_id: node_id,
        node_type: node_type_for(payload.tag),
        source_path: path,
        node_path: node_path,
        position: position,
        level: 2,
        parent_id: file_node_id,
        children_ids: []
      }

      unit = %TranslationUnit{
        unit_key: "block:#{position}",
        position: position,
        source_text: payload.text,
        source_markup: payload.markup,
        placeholders: %{},
        source_hash: hash_source(payload.markup),
        node_id: node_id,
        node_path: node_path,
        metadata: %{}
      }

      {[unit | units], Map.put(nodes, node_id, node), [node_id | child_ids]}
    end)
    |> then(fn {units, nodes, child_ids} ->
      {Enum.reverse(units), nodes, Enum.reverse(child_ids)}
    end)
  end

  defp element_payload({tag, _attrs, _children} = element) do
    tag = to_string(tag)
    markup = element |> Floki.raw_html() |> String.trim() |> strip_xml_declaration()
    text = element |> Floki.text(sep: "") |> String.trim()

    %{tag: tag, markup: markup, text: text}
  end

  defp blank_payload?(%{text: text}) do
    text == ""
  end

  defp strip_xml_declaration(markup) when is_binary(markup) do
    Regex.replace(~r/\A<\?xml[^>]*\?>\s*/i, markup, "")
  end

  defp strip_xml_declaration(markup), do: markup

  defp node_type_for(tag) do
    case tag do
      "h1" -> :heading
      "h2" -> :heading
      "h3" -> :heading
      "h4" -> :heading
      "h5" -> :heading
      "h6" -> :heading
      "li" -> :list_item
      "ol" -> :list
      "ul" -> :list
      "pre" -> :code
      "code" -> :code
      "table" -> :table
      "tr" -> :row
      "td" -> :cell
      "th" -> :cell
      "img" -> :image
      "section" -> :section
      "div" -> :section
      _ -> :block
    end
  end

  defp hash_source(source) do
    :crypto.hash(:sha256, source)
    |> Base.encode16(case: :lower)
  end

  defp tree_title(%Session{package: %{metadata: %{title: title}}}) when is_binary(title),
    do: title

  defp tree_title(_session), do: nil

  defp tree_metadata(%Session{package: package}) do
    %{
      version: package.version,
      rootfile_path: package.rootfile_path,
      spine_paths: package.spine_paths,
      content_paths: package.content_paths,
      nav_path: package.nav_path,
      toc_ncx_path: package.toc_ncx_path,
      metadata: package.metadata
    }
  end
end
