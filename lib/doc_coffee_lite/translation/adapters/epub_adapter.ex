defmodule DocCoffeeLite.Translation.Adapters.EpubAdapter do
  @moduledoc """
  Builds a format-agnostic DocumentTree by granularly segmenting EPUB content.
  """

  alias DocCoffeeLite.Epub.Session
  alias DocCoffeeLite.Translation.DocumentTree
  alias DocCoffeeLite.Translation.DocumentTreeNode
  alias DocCoffeeLite.Translation.Structs.TranslationGroup
  alias DocCoffeeLite.Translation.Structs.TranslationUnit
  alias DocCoffeeLite.Translation.Placeholder

  # Tags that should be treated as a single translatable unit
  @block_tags ~w(p h1 h2 h3 h4 h5 h6 li dt dd td th figcaption caption pre code address)
  
  # Tags that contain blocks and should be traversed deeper
  @container_tags ~w(body div section nav article aside header footer main ol ul table tr blockquote)

  def build(%Session{} = session) do
    content_paths = Session.content_paths(session)
    root_id = "doc:root"

    root_node = %DocumentTreeNode{
      node_id: root_id,
      node_type: :document,
      source_path: session.source_path,
      node_path: "/",
      position: 0,
      level: 0,
      title: session.package.metadata[:title],
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
          metadata: %{}
        }

        {:ok, %{tree: tree, groups: Enum.reverse(groups)}}

      {:error, reason} -> {:error, reason}
    end
  end

  defp build_groups(session, content_paths, root_id, nodes) do
    Enum.reduce_while(Enum.with_index(content_paths), {:ok, {nodes, [], []}}, fn {path, index}, {:ok, {nodes, groups, file_ids}} ->
      case build_group(session, path, index, root_id) do
        {:ok, {file_node, block_nodes, group}} ->
          nodes = nodes |> Map.put(file_node.node_id, file_node) |> Map.merge(block_nodes)
          {:cont, {:ok, {nodes, [group | groups], [file_node.node_id | file_ids]}}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp build_group(session, path, index, root_id) do
    with {:ok, xml} <- Session.read_file(session, path),
         {:ok, doc} <- Floki.parse_document(xml) do
      
      file_node_id = "file:#{path}"
      
      # Start recursive extraction from body or root
      body = Floki.find(doc, "body") |> List.first() || doc
      elements = extract_granular_blocks([body])

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

  # --- Granular Extraction ---

  defp extract_granular_blocks(nodes) when is_list(nodes) do
    Enum.flat_map(nodes, &extract_granular_blocks/1)
  end

  defp extract_granular_blocks({tag, _, _} = node) when tag in @block_tags do
    # If a block tag contains other block tags, we must go deeper
    children = Floki.children(node)
    if Enum.any?(children, &is_block_element?/1) do
      extract_granular_blocks(children)
    else
      [node] # Leaf block
    end
  end

  defp extract_granular_blocks({tag, _, children}) when tag in @container_tags do
    extract_granular_blocks(children)
  end

  defp extract_granular_blocks(text) when is_binary(text) do
    if String.trim(text) == "", do: [], else: [text]
  end

  defp extract_granular_blocks(_), do: []

  defp is_block_element?({tag, _, _}) when tag in @block_tags, do: true
  defp is_block_element?({tag, _, children}) when tag in @container_tags, do: Enum.any?(children, &is_block_element?/1)
  defp is_block_element?(_), do: false

  # --- Unit Building ---

  defp build_units(elements, path, file_node_id) do
    elements
    |> Enum.with_index()
    |> Enum.reduce({[], %{}, []}, fn {element, index}, {units, nodes, child_ids} ->
      position = index
      node_id = "block:#{path}:#{position}"
      
      {markup, _text} = element_info(element)
      {protected_text, mapping} = Placeholder.protect(markup)

      node = %DocumentTreeNode{
        node_id: node_id,
        node_type: :block,
        source_path: path,
        node_path: "body/[#{index + 1}]",
        position: position,
        level: 2,
        parent_id: file_node_id,
        children_ids: []
      }

      unit = %TranslationUnit{
        unit_key: "block:#{position}",
        position: position,
        source_text: protected_text,
        source_markup: markup,
        placeholders: mapping,
        source_hash: hash_source(markup),
        node_id: node_id,
        node_path: node.node_path,
        metadata: %{}
      }

      {[unit | units], Map.put(nodes, node_id, node), [node_id | child_ids]}
    end)
    |> then(fn {units, nodes, child_ids} ->
      {Enum.reverse(units), nodes, Enum.reverse(child_ids)}
    end)
  end

  defp element_info(element) when is_binary(element), do: {element, element}
  defp element_info(element) do
    markup = Floki.raw_html(element)
    text = Floki.text(element)
    {markup, text}
  end

  defp hash_source(source) do
    :crypto.hash(:sha256, source) |> Base.encode16(case: :lower)
  end
end