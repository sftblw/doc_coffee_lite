defmodule DocCoffeeLite.Translation.Persistence do
  @moduledoc """
  Persists parsed document trees and translation groups into Ecto schemas.
  """

  alias DocCoffeeLite.Repo
  alias DocCoffeeLite.Translation.DocumentNode
  alias DocCoffeeLite.Translation.TranslationGroup
  alias DocCoffeeLite.Translation.TranslationUnit

  alias DocCoffeeLite.Translation.DocumentTree
  alias DocCoffeeLite.Translation.DocumentTreeNode, as: TreeNode
  alias DocCoffeeLite.Translation.Structs.TranslationGroup, as: GroupStruct

  @spec persist(DocumentTree.t(), [GroupStruct.t()], String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def persist(%DocumentTree{} = tree, groups, project_id, source_document_id, _opts \\ []) do
    Repo.transaction(fn ->
      with {:ok, node_map} <- persist_nodes(tree.nodes, source_document_id),
           {:ok, group_map} <- persist_groups(groups, project_id, source_document_id, node_map),
           {:ok, unit_records} <- persist_units(groups, group_map, node_map) do
        %{nodes: node_map, groups: group_map, units: unit_records}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp persist_nodes(nodes, source_document_id) do
    nodes
    |> Map.values()
    |> Enum.sort_by(&(&1.level || 0))
    |> Enum.reduce_while({:ok, %{}}, fn node, {:ok, acc} ->
      case persist_node(node, source_document_id, acc) do
        {:ok, record} ->
          {:cont, {:ok, Map.put(acc, node.node_id, record)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp persist_node(%TreeNode{} = node, source_document_id, node_map) do
    parent_id = resolve_parent_node_id(node.parent_id, node_map)

    attrs = %{
      node_id: node.node_id,
      node_type: to_string(node.node_type),
      source_path: node.source_path,
      node_path: node.node_path,
      position: node.position || 0,
      level: node.level || 0,
      title: node.title,
      metadata: node.metadata || %{},
      source_document_id: source_document_id,
      parent_node_id: parent_id
    }

    %DocumentNode{}
    |> DocumentNode.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:source_document_id, :node_id]
    )
  end

  defp persist_groups(groups, project_id, source_document_id, node_map) do
    Enum.reduce_while(groups, {:ok, %{}}, fn group, {:ok, acc} ->
      case persist_group(group, project_id, source_document_id, node_map) do
        {:ok, record} ->
          {:cont, {:ok, Map.put(acc, group.group_key, record)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp persist_group(%GroupStruct{} = group, project_id, source_document_id, node_map) do
    document_node_id = resolve_group_node_id(group.node_id, node_map)

    attrs = %{
      group_key: group.group_key,
      group_type: to_string(group.group_type),
      position: group.position || 0,
      metadata: group.metadata || %{},
      project_id: project_id,
      source_document_id: source_document_id,
      document_node_id: document_node_id,
      status: "pending",
      progress: 0,
      cursor: 0
    }

    %TranslationGroup{}
    |> TranslationGroup.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:project_id, :group_key]
    )
  end

  defp persist_units(groups, group_map, node_map) do
    units =
      groups
      |> Enum.flat_map(fn group ->
        case Map.fetch(group_map, group.group_key) do
          {:ok, group_record} ->
            prepare_group_units(group, group_record, node_map)

          _ ->
            []
        end
      end)

    # For simplicity, we insert them one by one or use insert_all
    # Let's use Repo.insert for now to handle conflicts easily
    results =
      Enum.map(units, fn attrs ->
        %TranslationUnit{}
        |> TranslationUnit.changeset(attrs)
        |> Repo.insert(
          on_conflict: {:replace_all_except, [:id, :inserted_at]},
          conflict_target: [:translation_group_id, :unit_key]
        )
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(results, fn {:ok, r} -> r end)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp prepare_group_units(%GroupStruct{} = group, group_record, node_map) do
    Enum.map(group.units, fn unit ->
      document_node_id = resolve_unit_node_id(unit.node_id, node_map)

      %{
        unit_key: unit.unit_key,
        position: unit.position || 0,
        source_text: unit.source_text,
        source_markup: unit.source_markup,
        placeholders: unit.placeholders || %{},
        source_hash: unit.source_hash || hash_source(unit.source_markup),
        metadata: unit.metadata || %{},
        translation_group_id: group_record.id,
        document_node_id: document_node_id,
        status: "pending"
      }
    end)
  end

  defp resolve_parent_node_id(nil, _node_map), do: nil

  defp resolve_parent_node_id(parent_key, node_map) do
    case Map.fetch(node_map, parent_key) do
      {:ok, node} -> node.id
      _ -> nil
    end
  end

  defp resolve_group_node_id(nil, _node_map), do: nil

  defp resolve_group_node_id(node_id, node_map) do
    case Map.fetch(node_map, node_id) do
      {:ok, node} -> node.id
      _ -> nil
    end
  end

  defp resolve_unit_node_id(nil, _node_map), do: nil

  defp resolve_unit_node_id(node_id, node_map) do
    case Map.fetch(node_map, node_id) do
      {:ok, node} -> node.id
      _ -> nil
    end
  end

  defp hash_source(source) when is_binary(source) do
    :crypto.hash(:sha256, source)
    |> Base.encode16(case: :lower)
  end

  defp hash_source(_), do: nil
end
