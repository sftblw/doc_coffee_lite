defmodule DocCoffeeLite.Translation.Segmenter do
  @moduledoc """
  Segments documents into translation groups with configurable strategies.
  """

  alias DocCoffeeLite.Epub.Session
  alias DocCoffeeLite.Translation.Adapters.EpubAdapter
  alias DocCoffeeLite.Translation.DocumentTree
  alias DocCoffeeLite.Translation.Structs.TranslationGroup
  alias DocCoffeeLite.Translation.Structs.TranslationUnit

  @default_max_units 80
  @default_max_chars 8000

  @type segment_result :: {:ok, %{tree: DocumentTree.t(), groups: [TranslationGroup.t()]}}
  @type segment_error :: {:error, term()}

  @spec segment(:epub, Session.t(), keyword()) :: segment_result | segment_error
  @spec segment(:docx, %{tree: DocumentTree.t(), units: [TranslationUnit.t()]}, keyword()) ::
          segment_result | segment_error
  @spec segment(:docx, %{tree: DocumentTree.t(), groups: [TranslationGroup.t()]}, keyword()) ::
          segment_result | segment_error
  @spec segment(term(), term(), keyword()) :: segment_result | segment_error
  def segment(format, input, opts \\ [])

  def segment(:epub, %Session{} = session, opts) do
    with {:ok, %{tree: tree, groups: groups}} <- EpubAdapter.build(session) do
      groups = apply_group_strategy(groups, opts)
      {:ok, %{tree: tree, groups: groups}}
    end
  end

  def segment(:docx, %{tree: %DocumentTree{} = tree, units: units}, opts) do
    groups = group_units(units, opts)
    {:ok, %{tree: tree, groups: groups}}
  end

  def segment(:docx, %{tree: %DocumentTree{} = tree, groups: groups}, opts) do
    groups = apply_group_strategy(groups, opts)
    {:ok, %{tree: tree, groups: groups}}
  end

  def segment(_format, _input, _opts), do: {:error, :unsupported_format}

  defp apply_group_strategy(groups, opts) do
    case Keyword.get(opts, :strategy, :file) do
      :window -> window_groups(groups, opts)
      _ -> groups
    end
  end

  defp group_units(units, opts) do
    case Keyword.get(opts, :strategy, :heading) do
      :heading ->
        if Enum.any?(units, &heading_key/1) do
          units
          |> group_by_heading(opts)
          |> reindex_groups()
        else
          window_units(units, opts)
        end

      :window ->
        window_units(units, opts)

      _ ->
        window_units(units, opts)
    end
  end

  defp group_by_heading(units, opts) do
    source_path = Keyword.get(opts, :source_path, "docx")
    default_key = "section:0"

    {groups, current_key, current_units, position} =
      Enum.reduce(units, {[], nil, [], 0}, fn unit, {groups, current_key, current_units, pos} ->
        heading = heading_key(unit)
        group_key = normalize_section_key(heading)

        cond do
          is_binary(group_key) and group_key != current_key ->
            {groups, pos} = flush_group(groups, current_key, current_units, pos, source_path)
            {groups, group_key, [unit], pos}

          current_key == nil ->
            {groups, default_key, [unit], pos}

          true ->
            {groups, current_key, [unit | current_units], pos}
        end
      end)

    {groups, _pos} = flush_group(groups, current_key, current_units, position, source_path)
    Enum.reverse(groups)
  end

  defp window_groups(groups, opts) do
    groups
    |> Enum.flat_map(&split_group(&1, opts))
    |> reindex_groups()
  end

  defp window_units(units, opts) do
    source_path = Keyword.get(opts, :source_path, "docx")
    {max_units, max_chars} = window_limits(opts)

    units
    |> chunk_units(max_units, max_chars)
    |> Enum.with_index()
    |> Enum.map(fn {chunk, index} ->
      %TranslationGroup{
        group_key: "window:#{index}",
        group_type: :window,
        position: index,
        source_path: source_path,
        units: chunk
      }
    end)
  end

  defp split_group(%TranslationGroup{} = group, opts) do
    {max_units, max_chars} = window_limits(opts)
    chunks = chunk_units(group.units, max_units, max_chars)

    case chunks do
      [_single] ->
        [group]

      _ ->
        total = length(chunks)

        chunks
        |> Enum.with_index(1)
        |> Enum.map(fn {chunk, index} ->
          metadata =
            group.metadata
            |> Map.put(:window_index, index)
            |> Map.put(:window_total, total)
            |> Map.put(:base_group_key, group.group_key)

          %TranslationGroup{
            group
            | group_key: "#{group.group_key}#window-#{index}",
              group_type: :window,
              units: chunk,
              metadata: metadata
          }
        end)
    end
  end

  defp chunk_units(units, max_units, max_chars) do
    {chunks, current_units, _count, _chars} =
      Enum.reduce(units, {[], [], 0, 0}, fn unit, {chunks, current_units, count, chars} ->
        unit_text = unit.source_text || ""
        unit_chars = String.length(unit_text)
        next_count = count + 1
        next_chars = chars + unit_chars

        if should_split?(current_units, next_count, next_chars, max_units, max_chars) do
          {[Enum.reverse(current_units) | chunks], [unit], 1, unit_chars}
        else
          {chunks, [unit | current_units], next_count, next_chars}
        end
      end)

    chunks =
      if current_units == [] do
        chunks
      else
        [Enum.reverse(current_units) | chunks]
      end

    Enum.reverse(chunks)
  end

  defp should_split?(current_units, count, chars, max_units, max_chars) do
    current_units != [] and
      (limit_exceeded?(count, max_units) or limit_exceeded?(chars, max_chars))
  end

  defp limit_exceeded?(value, max) when is_integer(max), do: value > max
  defp limit_exceeded?(_value, _max), do: false

  defp window_limits(opts) do
    max_units = Keyword.get(opts, :max_units, @default_max_units)
    max_chars = Keyword.get(opts, :max_chars, @default_max_chars)
    {max_units, max_chars}
  end

  defp flush_group(groups, nil, [], position, _source_path), do: {groups, position}

  defp flush_group(groups, group_key, units, position, source_path) do
    group = %TranslationGroup{
      group_key: group_key,
      group_type: :section,
      position: position,
      source_path: source_path,
      units: Enum.reverse(units)
    }

    {[group | groups], position + 1}
  end

  defp reindex_groups(groups) do
    groups
    |> Enum.with_index()
    |> Enum.map(fn {%TranslationGroup{} = group, index} ->
      %TranslationGroup{group | position: index}
    end)
  end

  defp heading_key(%TranslationUnit{metadata: metadata}) do
    case metadata do
      %{} ->
        metadata[:section_key] ||
          metadata["section_key"] ||
          metadata[:heading_id] ||
          metadata["heading_id"]

      _ ->
        nil
    end
  end

  defp normalize_section_key(nil), do: nil

  defp normalize_section_key(value) when is_binary(value) do
    if String.starts_with?(value, "section:") do
      value
    else
      "section:#{value}"
    end
  end

  defp normalize_section_key(value), do: normalize_section_key(to_string(value))
end
