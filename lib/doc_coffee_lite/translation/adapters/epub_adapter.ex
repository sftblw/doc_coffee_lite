defmodule DocCoffeeLite.Translation.Adapters.EpubAdapter do
  @moduledoc """
  Granularly segments EPUB content and injects data-unit-id markers into the source files.
  """

  alias DocCoffeeLite.Epub.Session
  alias DocCoffeeLite.Translation.DocumentTree
  alias DocCoffeeLite.Translation.DocumentTreeNode
  alias DocCoffeeLite.Translation.Structs.TranslationGroup
  alias DocCoffeeLite.Translation.Structs.TranslationUnit
  alias DocCoffeeLite.Translation.Placeholder

  @block_tags ~w(p h1 h2 h3 h4 h5 h6 li dt dd td th figcaption caption pre code address nav)
  @container_tags ~w(html body div section article aside header footer main ol ul table tr blockquote)

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

    case build_groups(session, content_paths, root_id, %{root_id => root_node}) do
      {:ok, {nodes, groups, file_ids}} ->
        root_node = %{root_node | children_ids: Enum.reverse(file_ids)}
        nodes = Map.put(nodes, root_id, root_node)

        tree = %DocumentTree{
          format: :epub,
          source_path: session.source_path,
          work_dir: session.work_dir,
          nodes: nodes,
          root_ids: [root_id]
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
          nodes = nodes |> Map.put(file_node.node_id, file_node) |> Map.merge(block_nodes)
          {:cont, {:ok, {nodes, [group | groups], [file_node.node_id | file_ids]}}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp build_group(session, path, index, root_id) do
    with {:ok, xml} <- Session.read_file(session, path),
         {:ok, doc} <- Floki.parse_document(xml) do
      file_node_id = "file:#{path}"

      # 1. Inject markers and collect units
      {tagged_doc, elements} = inject_markers(doc, path)

      # 2. Save the tagged document back to work_dir!
      # This is the "Anchor" that Export will use later.
      tagged_xml = Floki.raw_html(tagged_doc)
      full_path = Path.join(session.work_dir, path)
      File.write!(full_path, tagged_xml)

      # 3. Build units from collected elements
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

  defp inject_markers(doc, _path) do
    {updated_doc, {elements, _count}} =
      Floki.traverse_and_update(doc, {[], 0}, fn
        {tag, attrs, children} = node, {acc, count} ->
          tag_s = to_string(tag)

          cond do
            # If it's a container OR a block that contains more blocks, keep going deeper
            tag_s in @container_tags or (tag_s in @block_tags and has_block_child?(children)) ->
              # Don't tag containers, just traverse
              {node, {acc, count}}

            tag_s in @block_tags ->
              # Leaf block! Tag it.
              id = "u_#{count}"
              new_node = {tag, [{"data-unit-id", id} | attrs], children}
              {new_node, {acc ++ [{id, new_node}], count + 1}}

            true ->
              {node, {acc, count}}
          end

        text, {acc, count} when is_binary(text) ->
          if String.trim(text) != "" do
            # Naked text - we can't easily tag it without wrapping, 
            # so let's wrap it in a span for safety
            id = "u_#{count}"
            new_node = {"span", [{"data-unit-id", id}], [text]}
            {new_node, {acc ++ [{id, new_node}], count + 1}}
          else
            {text, {acc, count}}
          end

        node, acc ->
          {node, acc}
      end)

    {updated_doc, elements}
  end

  defp has_block_child?(nodes) when is_list(nodes) do
    Enum.any?(nodes, fn
      {tag, _, children} ->
        tag_s = to_string(tag)
        tag_s in @block_tags or tag_s in @container_tags or has_block_child?(children)

      _ ->
        false
    end)
  end

  defp has_block_child?(_), do: false

  defp build_units(elements, path, file_node_id) do
    elements
    |> Enum.with_index()
    |> Enum.reduce({[], %{}, []}, fn {{id, element}, index}, {units, nodes, child_ids} ->
      node_id = "block:#{path}:#{index}"
      markup = Floki.raw_html(element)
      {protected_text, mapping} = Placeholder.protect(markup)

      node = %DocumentTreeNode{
        node_id: node_id,
        node_type: :block,
        source_path: path,
        node_path: "body/[#{index + 1}]",
        position: index,
        level: 2,
        parent_id: file_node_id,
        children_ids: []
      }

      unit = %TranslationUnit{
        # Use the marker ID as unit_key!
        unit_key: id,
        position: index,
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
    |> then(fn {units, nodes, ids} ->
      {Enum.reverse(units), nodes, Enum.reverse(ids)}
    end)
  end

  defp hash_source(source), do: :crypto.hash(:sha256, source) |> Base.encode16(case: :lower)
end
