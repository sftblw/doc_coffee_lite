defmodule DocCoffeeLite.Translation.Export do
  @moduledoc """
  Assembles translated EPUB content and builds the final archive.
  """

  import Ecto.Query
  alias DocCoffeeLite.Repo
  alias DocCoffeeLite.Epub.Path, as: EpubPath
  alias DocCoffeeLite.Epub.Writer
  alias DocCoffeeLite.Translation.{Project, SourceDocument, TranslationGroup, TranslationUnit, TranslationRun, BlockTranslation}

  @block_tags ~w(p h1 h2 h3 h4 h5 h6 li dt dd pre code blockquote td th figcaption caption)
  @block_xpath @block_tags |> Enum.map(&"local-name()='#{&1}'") |> Enum.join(" or ") |> then(&".//*[#{&1}]") |> String.to_charlist()

  def export_epub(run_id, output_path, opts \\ []) do
    output_path = Path.expand(output_path)
    
    with {:ok, run, source} <- load_context(run_id),
         {:ok, %{work_dir: work_dir}} <- assemble_translated_files(run_id, opts),
         :ok <- Writer.build(work_dir, output_path) do
      :ok
    end
  end

  def assemble_translated_files(run_id, opts \\ []) do
    allow_missing? = Keyword.get(opts, :allow_missing?, false)
    
    with {:ok, run, source} <- load_context(run_id),
         {:ok, work_dir} <- prepare_work_dir(source, opts),
         groups <- fetch_groups(source.id),
         :ok <- apply_groups(run.id, groups, work_dir, allow_missing?) do
      {:ok, %{work_dir: work_dir, group_count: length(groups)}}
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

  defp prepare_work_dir(%SourceDocument{work_dir: work_dir}, _opts) do
    # For now, we use the existing work_dir or copy it
    # Simplified: just use existing work_dir
    {:ok, work_dir}
  end

  defp apply_groups(run_id, groups, work_dir, allow_missing?) do
    Enum.reduce_while(groups, :ok, fn group, :ok ->
      case apply_group(run_id, group, work_dir, allow_missing?) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp apply_group(run_id, group, work_dir, allow_missing?) do
    units = Repo.all(from u in TranslationUnit, where: u.translation_group_id == ^group.id, order_by: [asc: u.position])
    unit_ids = Enum.map(units, & &1.id)
    translations = Repo.all(from b in BlockTranslation, where: b.translation_run_id == ^run_id and b.translation_unit_id in ^unit_ids)
    
    with {:ok, replacements} <- build_replacements(units, translations, allow_missing?),
         {:ok, content} <- read_file(work_dir, group.group_key),
         {:ok, updated} <- replace_markup(content, replacements) do
      write_file(work_dir, group.group_key, updated)
    end
  end

  defp build_replacements(units, translations, allow_missing?) do
    map = Map.new(translations, &{&1.translation_unit_id, &1.translated_markup})
    results = Enum.map(units, fn u ->
      case Map.get(map, u.id) do
        nil -> if allow_missing?, do: {:ok, u.source_markup}, else: {:error, :missing}
        markup -> {:ok, markup}
      end
    end)
    
    if Enum.any?(results, &match?({:error, _}, &1)) do
      {:error, :missing_translation}
    else
      {:ok, Enum.map(results, fn {:ok, m} -> m end)}
    end
  end

  defp replace_markup(content, replacements) do
    # Ported logic from original
    with {:ok, doc} <- parse_xml(content),
         {:ok, {strategy, target_count}} <- detect_strategy(doc) do
      if length(replacements) == target_count do
        simple_root = :xmerl_lib.simplify_element(root_element(doc))
        {updated, _} = replace_nodes(simple_root, replacements, strategy)
        {:ok, export_simple(updated)}
      else
        {:error, :count_mismatch}
      end
    end
  end

  defp detect_strategy(doc) do
    body = find_body(doc)
    elements = :xmerl_xpath.string(@block_xpath, body)
    if elements == [] do
      fallback = :xmerl_xpath.string(~c"/*", body)
      {:ok, {:body_children, length(fallback)}}
    else
      {:ok, {:block_tags, length(elements)}}
    end
  end

  defp root_element(doc) do
    [root] = :xmerl_xpath.string(~c"/*", doc)
    root
  end

  defp find_body(doc) do
    case :xmerl_xpath.string(~c"//*[local-name()='body']", doc) do
      [body | _] -> body
      [] -> doc
    end
  end

  defp replace_nodes({tag, attrs, children}, replacements, :block_tags) do
    if to_string(tag) in @block_tags do
      case replacements do
        [r | rest] -> {parse_to_simple(r), rest}
        [] -> {{tag, attrs, children}, []}
      end
    else
      {new_children, remaining} = Enum.reduce(children, {[], replacements}, fn child, {acc, reps} ->
        if is_tuple(child) do
          {nc, nr} = replace_nodes(child, reps, :block_tags)
          {[nc | acc], nr}
        else
          {[child | acc], reps}
        end
      end)
      {{tag, attrs, Enum.reverse(new_children)}, remaining}
    end
  end
  defp replace_nodes(text, reps, _), do: {text, reps}

  defp parse_to_simple(markup) do
    wrapped = "<root>#{markup}</root>"
    {doc, _} = :xmerl_scan.string(:erlang.binary_to_list(wrapped))
    [element] = :xmerl_xpath.string(~c"/*/*", doc)
    :xmerl_lib.simplify_element(element)
  end

  defp export_simple(simple) do
    simple |> List.wrap() |> :xmerl.export_simple(:xmerl_xml) |> IO.iodata_to_binary()
  end

  defp parse_xml(content) do
    try do
      {doc, _} = :xmerl_scan.string(:erlang.binary_to_list(content))
      {:ok, doc}
    catch _, r -> {:error, r} end
  end

  defp read_file(work_dir, path), do: File.read(Path.join(work_dir, path))
  defp write_file(work_dir, path, content), do: File.write(Path.join(work_dir, path), content)
end
