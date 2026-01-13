defmodule DocCoffeeLite.Translation.Export do
  @moduledoc """
  Assembles translated EPUB content using granular block replacement.
  """

  import Ecto.Query
  alias DocCoffeeLite.Repo
  alias DocCoffeeLite.Epub.Writer
  alias DocCoffeeLite.Translation.{Project, SourceDocument, TranslationGroup, TranslationUnit, TranslationRun, BlockTranslation}

  @block_tags ~w(p h1 h2 h3 h4 h5 h6 li dt dd td th figcaption caption pre code address)
  @container_tags ~w(body div section nav article aside header footer main ol ul table tr blockquote)

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

  defp apply_group(run_id, group, work_dir, allow_missing?) do
    units = Repo.all(from u in TranslationUnit, where: u.translation_group_id == ^group.id, order_by: [asc: u.position])
    unit_ids = Enum.map(units, & &1.id)
    translations = Repo.all(from b in BlockTranslation, where: b.translation_run_id == ^run_id and b.translation_unit_id in ^unit_ids)

    with {:ok, replacements} <- build_replacements(units, translations, allow_missing?),
         full_path <- Path.join(work_dir, group.group_key),
         {:ok, content} <- File.read(full_path),
         {:ok, updated} <- replace_markup(content, replacements) do
      File.write(full_path, updated)
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
    case Floki.parse_document(content) do
      {:ok, doc} ->
        # Use the same recursive logic as EpubAdapter to find target nodes
        {updated_doc, _} = do_replace(doc, replacements)
        {:ok, Floki.raw_html(updated_doc)}
      {:error, r} -> {:error, r}
    end
  end

  defp do_replace(nodes, replacements) when is_list(nodes) do
    Enum.reduce(nodes, {[], replacements}, fn node, {acc, reps} ->
      {new_node, remaining_reps} = do_replace(node, reps)
      {[new_node | acc], remaining_reps}
    end)
    |> then(fn {acc, reps} -> {Enum.reverse(acc), reps} end)
  end

  defp do_replace({tag, attrs, _children} = node, [next_rep | rest_reps] = reps) do
    cond do
      to_string(tag) in @block_tags ->
        # If it has block children, we must recurse inside (matches EpubAdapter)
        if has_block_child?(node) do
          {new_children, remaining} = do_replace(Floki.children(node), reps)
          {{tag, attrs, new_children}, remaining}
        else
          # Leaf block! Replace it.
          case Floki.parse_fragment(next_rep) do
            {:ok, [new_node | _]} -> {new_node, rest_reps}
            _ -> {node, rest_reps}
          end
        end
      to_string(tag) in @container_tags ->
        {new_children, remaining} = do_replace(Floki.children(node), reps)
        {{tag, attrs, new_children}, remaining}
      true -> {node, reps}
    end
  end

  defp do_replace(text, [next_rep | rest_reps]) when is_binary(text) do
    if String.trim(text) == "" do
      {text, [next_rep | rest_reps]}
    else
      # It was a "naked" text unit in EpubAdapter.
      # parse_fragment handles plain text too.
      case Floki.parse_fragment(next_rep) do
        {:ok, [new_node | _]} -> {new_node, rest_reps}
        _ -> {text, rest_reps}
      end
    end
  end

  defp do_replace(node, reps), do: {node, reps}

  defp has_block_child?({_, _, children}) do
    Enum.any?(children, fn
      {tag, _, _} = node ->
        to_string(tag) in @block_tags or has_block_child?(node)
      _ -> false
    end)
  end
  defp has_block_child?(_), do: false
end
