defmodule DocCoffeeLite.Translation.Export do
  @moduledoc """
  Assembles translated EPUB content using explicit data-unit-id markers.
  """

  import Ecto.Query
  require Logger
  alias DocCoffeeLite.Repo
  alias DocCoffeeLite.Epub
  alias DocCoffeeLite.Epub.Writer
  alias DocCoffeeLite.Translation.Segmenter

  alias DocCoffeeLite.Translation.{
    Project,
    SourceDocument,
    TranslationGroup,
    TranslationUnit,
    TranslationRun,
    BlockTranslation
  }

  def export_epub(run_id, output_path, opts \\ []) do
    output_path = Path.expand(output_path)

    with {:ok, _run, _source} <- load_context(run_id),
         {:ok, %{work_dir: work_dir, cleanup?: cleanup?}} <-
           assemble_translated_files(run_id, opts),
         :ok <- Writer.build(work_dir, output_path) do
      if cleanup?, do: File.rm_rf(work_dir)
      :ok
    end
  end

  def assemble_translated_files(run_id, opts \\ []) do
    allow_missing? = Keyword.get(opts, :allow_missing?, false)

    with {:ok, run, source} <- load_context(run_id),
         {:ok, work_dir} <- prepare_work_dir(source),
         groups <- fetch_groups(source.id),
         :ok <- apply_groups(run.id, groups, work_dir, allow_missing?) do
      {:ok, %{work_dir: work_dir, group_count: length(groups), cleanup?: true}}
    end
  end

  defp load_context(run_id) do
    run = Repo.get(TranslationRun, run_id)

    if run do
      project = Repo.get(Project, run.project_id)
      source = Repo.one(from s in SourceDocument, where: s.project_id == ^project.id)
      {:ok, run, source}
    else
      {:error, :run_not_found}
    end
  end

  defp fetch_groups(source_document_id) do
    Repo.all(
      from g in TranslationGroup,
        where: g.source_document_id == ^source_document_id,
        order_by: [asc: g.position]
    )
  end

  defp prepare_work_dir(%SourceDocument{source_path: source_path}) do
    work_dir = Path.join(System.tmp_dir!(), "export_work_#{Ecto.UUID.generate()}")

    with :ok <- File.mkdir_p(work_dir),
         {:ok, session} <- Epub.open(source_path, work_dir),
         {:ok, _} <- Segmenter.segment(:epub, session) do
      {:ok, work_dir}
    end
  end

  defp apply_groups(run_id, groups, work_dir, allow_missing?) do
    Enum.reduce_while(groups, :ok, fn group, :ok ->
      case apply_group(run_id, group, work_dir, allow_missing?) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp apply_group(run_id, group, work_dir, _allow_missing?) do
    units = Repo.all(from u in TranslationUnit, where: u.translation_group_id == ^group.id)
    unit_ids = Enum.map(units, & &1.id)

    run_translations =
      run_id
      |> fetch_run_translations(unit_ids)
      |> Map.new(&{&1.translation_unit_id, &1})

    latest_translations =
      unit_ids
      |> fetch_latest_translations()
      |> Map.new(&{&1.translation_unit_id, &1})

    translations = select_translations(run_translations, latest_translations, unit_ids)

    # Map by unit_key (which contains the data-unit-id marker)
    units_map = Map.new(units, &{&1.id, &1})

    trans_map =
      translations
      |> Enum.reduce(%{}, fn {_unit_id, b}, acc ->
        case Map.get(units_map, b.translation_unit_id) do
          %TranslationUnit{} = unit -> Map.put(acc, unit.unit_key, b.translated_markup)
          _ -> acc
        end
      end)

    full_path = Path.join(work_dir, group.group_key)

    with {:ok, content} <- File.read(full_path),
         {:ok, updated} <- replace_by_markers(content, trans_map, group.group_key) do
      File.write(full_path, updated)
    end
  end

  defp replace_by_markers(content, trans_map, group_key) do
    case Floki.parse_document(content) do
      {:ok, doc} ->
        {updated_doc, count} =
          Floki.traverse_and_update(doc, 0, fn
            {_tag, attrs, _children} = node, count when is_list(attrs) ->
              case List.keyfind(attrs, "data-unit-id", 0) do
                {"data-unit-id", id} ->
                  case Map.get(trans_map, id) do
                    # No translation, keep original
                    nil ->
                      {node, count}

                    markup ->
                      {updated_node, replaced?} = replace_node(node, markup)
                      {updated_node, if(replaced?, do: count + 1, else: count)}
                  end

                nil ->
                  {node, count}
              end

            text, count ->
              {text, count}
          end)

        Logger.info("Export: Replaced #{count} blocks in #{group_key}")
        {:ok, Floki.raw_html(updated_doc)}

      {:error, r} ->
        {:error, r}
    end
  end

  defp replace_node({tag, _attrs, _children} = node, markup) do
    case parse_translated_markup(markup) do
      {:ok, nodes} ->
        updated =
          case nodes do
            [{new_tag, _new_attrs, _new_children} = new_node] ->
              if to_string(new_tag) == to_string(tag) do
                # Keep the translated tag if it matches the source wrapper.
                strip_marker(new_node)
              else
                # Preserve the original wrapper and use translated nodes as children.
                replace_children(node, nodes)
              end

            _ ->
              replace_children(node, nodes)
          end

        {updated, true}

      {:error, _} ->
        # Fall back to text content so the export remains valid XML.
        {replace_children(node, [markup]), true}
    end
  end

  defp parse_translated_markup(markup) do
    case Floki.parse_fragment(markup) do
      {:ok, nodes} ->
        {:ok, nodes}

      {:error, _} ->
        markup = escape_loose_angles(markup)
        Floki.parse_fragment(markup)
    end
  end

  defp escape_loose_angles(markup) do
    String.replace(markup, ~r|<(?![A-Za-z/!?])|, "&lt;")
  end

  defp replace_children({tag, attrs, _children}, new_children) do
    {tag, List.keydelete(attrs, "data-unit-id", 0), new_children}
  end

  defp strip_marker({tag, attrs, children}) do
    {tag, List.keydelete(attrs, "data-unit-id", 0), children}
  end

  defp strip_marker(node), do: node

  defp fetch_run_translations(nil, _unit_ids), do: []

  defp fetch_run_translations(run_id, unit_ids) do
    Repo.all(
      from b in BlockTranslation,
        where: b.translation_run_id == ^run_id and b.translation_unit_id in ^unit_ids
    )
  end

  defp fetch_latest_translations(unit_ids) do
    Repo.all(
      from b in BlockTranslation,
        where: b.translation_unit_id in ^unit_ids,
        distinct: b.translation_unit_id,
        order_by: [
          asc: b.translation_unit_id,
          desc: b.updated_at,
          desc: b.inserted_at,
          desc: b.id
        ]
    )
  end

  defp select_translations(run_translations, latest_translations, unit_ids) do
    Enum.reduce(unit_ids, %{}, fn unit_id, acc ->
      run_bt = Map.get(run_translations, unit_id)
      latest_bt = Map.get(latest_translations, unit_id)
      chosen = pick_latest_translation(run_bt, latest_bt)

      if chosen do
        Map.put(acc, unit_id, chosen)
      else
        acc
      end
    end)
  end

  defp pick_latest_translation(nil, latest), do: latest
  defp pick_latest_translation(run, nil), do: run

  defp pick_latest_translation(run, latest) do
    run_ts = translation_timestamp(run)
    latest_ts = translation_timestamp(latest)

    case DateTime.compare(run_ts, latest_ts) do
      :gt -> run
      :lt -> latest
      :eq -> if run.id >= latest.id, do: run, else: latest
    end
  end

  defp translation_timestamp(%BlockTranslation{} = bt) do
    bt.updated_at || bt.inserted_at
  end
end
