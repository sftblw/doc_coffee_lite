defmodule DocCoffeeLite.Translation.Export do
  @moduledoc """
  Assembles translated EPUB content using explicit data-unit-id markers.
  """

  import Ecto.Query
  require Logger
  alias DocCoffeeLite.Repo
  alias DocCoffeeLite.Epub.Writer
  alias DocCoffeeLite.Translation.{Project, SourceDocument, TranslationGroup, TranslationUnit, TranslationRun, BlockTranslation}

  def export_epub(run_id, output_path, opts \\ []) do
    output_path = Path.expand(output_path)
    with {:ok, _run, _source} <- load_context(run_id),
         {:ok, %{work_dir: work_dir}} <- assemble_translated_files(run_id, opts),
         :ok <- Writer.build(work_dir, output_path) do
      :ok
    end
  end

  def assemble_translated_files(run_id, opts \\ []) do
    allow_missing? = Keyword.get(opts, :allow_missing?, false)
    with {:ok, run, source} <- load_context(run_id),
         groups <- fetch_groups(source.id),
         :ok <- apply_groups(run.id, groups, source.work_dir, allow_missing?) do
      {:ok, %{work_dir: source.work_dir, group_count: length(groups)}}
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
    Repo.all(from g in TranslationGroup, where: g.source_document_id == ^source_document_id, order_by: [asc: g.position])
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
    translations = Repo.all(from b in BlockTranslation, where: b.translation_run_id == ^run_id and b.translation_unit_id in ^unit_ids)
    
    # Map by unit_key (which contains the data-unit-id marker)
    units_map = Map.new(units, &{&1.id, &1})
    trans_map = Map.new(translations, fn b -> 
      unit = Map.get(units_map, b.translation_unit_id)
      {unit.unit_key, b.translated_markup}
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
            {_tag, attrs, _children} = node, count ->
              case List.keyfind(attrs, "data-unit-id", 0) do
                {"data-unit-id", id} ->
                  case Map.get(trans_map, id) do
                    nil -> {node, count} # No translation, keep original
                    markup ->
                      case Floki.parse_fragment(markup) do
                        {:ok, [new_node | _]} -> 
                          # Important: remove the marker attribute from the new node!
                          cleaned_node = strip_marker(new_node)
                          {cleaned_node, count + 1}
                        _ -> {node, count}
                      end
                  end
                nil -> {node, count}
              end
            text, count -> {text, count}
          end)
        
        Logger.info("Export: Replaced #{count} blocks in #{group_key}")
        {:ok, Floki.raw_html(updated_doc)}
      {:error, r} -> {:error, r}
    end
  end

  defp strip_marker({tag, attrs, children}) do
    {tag, List.keydelete(attrs, "data-unit-id", 0), children}
  end
  defp strip_marker(node), do: node
end
