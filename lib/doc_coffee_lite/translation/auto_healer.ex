defmodule DocCoffeeLite.Translation.AutoHealer do
  @moduledoc """
  Restores structure and heals malformed placeholders in translated text
  based on the original source structure.
  """

  @type heal_result :: {:ok, String.t()} | {:error, :healing_failed, String.t()}

  defmodule Node do
    defstruct [:id, :tag_name, :full_tag_open, :full_tag_close, :children, :type]
    # type: :container (has children), :self_closing
  end

  defmodule Text do
    defstruct [:content]
  end

  @doc """
  Heals the translated text by enforcing the structure of the source text.
  Restores whitespace (newlines, tabs, spaces) from the source.
  Fixes malformed tags in translation (e.g., [[p_1] -> [[p_1]]).
  """
  @spec heal(String.t(), String.t()) :: heal_result
  def heal(source_text, translated_text) do
    # 1. Parse Source into a Tree Structure
    case parse_source(source_text) do
      {:ok, source_tree} ->
        # 2. Process translation against the source tree with chunking logic
        process_nodes(source_tree, translated_text)

      {:error, _reason} = err ->
        err
    end
  end

  # --- Parsing Source ---

  defp parse_source(text) do
    tokens = tokenize(text)
    build_tree(tokens, [], [])
  end

  defp tokenize(text) do
    # Capture [[...]] tags. Relies on tags not containing ']' internally.
    regex = ~r/(\[\[[^\]]+\]\])/
    
    Regex.split(regex, text, include_captures: true, trim: true)
    |> Enum.map(fn token ->
      if String.starts_with?(token, "[[") and String.ends_with?(token, "]]") do
         inner = String.slice(token, 2..-3//1)
         cond do
           String.starts_with?(inner, "/") -> {:close, String.slice(inner, 1..-1//1), token}
           String.ends_with?(inner, "/") -> {:self_closing, String.slice(inner, 0..-2//1), token}
           true -> {:open, inner, token}
         end
      else
         {:text, token}
      end
    end)
  end

  defp build_tree([], _stack, acc) do
    {:ok, Enum.reverse(acc)}
  end

  defp build_tree([token | rest], stack, acc) do
    case token do
      {:text, content} ->
        build_tree(rest, stack, [%Text{content: content} | acc])

      {:self_closing, id, full_tag} ->
        node = %Node{
          id: id,
          tag_name: id,
          full_tag_open: full_tag,
          type: :self_closing,
          children: []
        }
        build_tree(rest, stack, [node | acc])

      {:open, id, full_tag} ->
        build_tree(rest, [{id, full_tag, acc} | stack], [])

      {:close, id, full_tag} ->
        case stack do
          [{parent_id, parent_open, parent_acc} | stack_rest] ->
            if parent_id == id do
              children = Enum.reverse(acc)
              node = %Node{
                id: id,
                full_tag_open: parent_open,
                full_tag_close: full_tag,
                children: children,
                type: :container
              }
              build_tree(rest, stack_rest, [node | parent_acc])
            else
              # Mismatch fallback
              build_tree(rest, stack, [%Text{content: full_tag} | acc])
            end
          [] ->
             # Orphan fallback
             build_tree(rest, stack, [%Text{content: full_tag} | acc])
        end
    end
  end

  # --- Processing Translation ---

  defp process_nodes(nodes, translated_text) do
    # Group nodes into chunks: {[TextNodes], NextTagNode | nil}
    chunks = chunk_nodes(nodes)
    
    {final_text, _, status} = 
      Enum.reduce(chunks, {"", translated_text, :ok}, fn {text_nodes, tag_node}, {acc_out, acc_trans, acc_status} ->
        
        {processed_text, next_trans, chunk_status} = 
          process_chunk(text_nodes, tag_node, acc_trans)
        
        new_status = if acc_status == :ok and chunk_status == :ok, do: :ok, else: :error
        
        {acc_out <> processed_text, next_trans, new_status}
      end)

    if status == :ok do
      {:ok, final_text}
    else
      # If healing failed, we still return the best-effort final text
      {:error, :healing_failed, final_text}
    end
  end

  # Helper to group consecutive text nodes with the following tag node
  defp chunk_nodes(nodes) do
    {current_text_nodes, chunks} = 
      Enum.reduce(nodes, {[], []}, fn node, {txt_acc, chunk_acc} ->
        case node do
          %Text{} -> {[node | txt_acc], chunk_acc}
          %Node{} -> 
            # Found a tag. Complete the current chunk.
            # Text nodes were accumulated in reverse, reverse them back.
            chunk = {Enum.reverse(txt_acc), node}
            {[], [chunk | chunk_acc]}
        end
      end)
    
    # Add the final chunk (trailing text nodes with no following tag)
    final_chunk = {Enum.reverse(current_text_nodes), nil}
    Enum.reverse([final_chunk | chunks])
  end

  defp process_chunk(text_nodes, tag_node, translated_text) do
    case tag_node do
      nil ->
        # No following tag. The remaining translated text belongs to these text nodes.
        # We assume the rest of translation is content for these nodes.
        processed_text = resolve_text_nodes(text_nodes, translated_text)
        {processed_text, "", :ok}

      %Node{id: id, type: type} = node ->
        # Look for this tag in translation
        search_type = if type == :container, do: :open, else: :self_closing
        
        case find_tag(translated_text, id, search_type) do
          {:match, match_str, after_match, before_match} ->
            # 'before_match' is the content for 'text_nodes'
            processed_pre_text = resolve_text_nodes(text_nodes, before_match)
            
            # Now process the tag itself
            {processed_tag, final_remaining, tag_status} = 
              process_tag_node(node, match_str, after_match)
              
            {processed_pre_text <> processed_tag, final_remaining, tag_status}

          :not_found ->
            # Tag missing. 
            # Fallback strategy:
            # 1. Resolve text nodes using ALL translated text (hoping it matches).
            # 2. Append the FORCED source tag (empty content).
            # 3. Return error.
            
            processed_text = resolve_text_nodes(text_nodes, translated_text)
            
            # Force the tag
            forced_tag = force_tag_string(node)
            
            {processed_text <> forced_tag, "", :error}
        end
    end
  end

  defp process_tag_node(%Node{type: :self_closing, full_tag_open: full_tag}, _match_str, remaining_trans) do
    # For self-closing, we just return the cleaned source tag.
    {full_tag, remaining_trans, :ok}
  end

  defp process_tag_node(%Node{type: :container, id: id, children: children, full_tag_open: tag_open, full_tag_close: tag_close}, _match_open, remaining_trans) do
    # We found the open tag. Now find the close tag in 'remaining_trans'.
    
    case find_tag(remaining_trans, id, :close) do
      {:match, _match_close, after_close, inner_content} ->
        # Found the pair!
        # Recursively process children with the bounded inner content
        {healed_inner, inner_status} = 
          case process_nodes(children, inner_content) do
            {:ok, text} -> {text, :ok}
            {:error, _, text} -> {text, :error}
          end
        
        reconstructed = tag_open <> healed_inner <> tag_close
        {reconstructed, after_close, inner_status}

      :not_found ->
        # Open found, but Close missing.
        # Safest fallback: Empty content.
        {tag_open <> tag_close, remaining_trans, :error}
    end
  end

  defp resolve_text_nodes([], _), do: ""
  defp resolve_text_nodes(text_nodes, candidate_trans) do
    # Concatenate all source text content to check its nature
    source_content = Enum.map_join(text_nodes, & &1.content)
    
    if is_pure_whitespace?(source_content) do
      # It is structural whitespace. Restore strict source.
      source_content
    else
      # It contains content. Use the translation candidate.
      candidate_trans
    end
  end

  defp is_pure_whitespace?(str) do
    String.trim(str) == ""
  end
  
  defp force_tag_string(%Node{type: :self_closing, full_tag_open: t}), do: t
  defp force_tag_string(%Node{type: :container, full_tag_open: o, full_tag_close: c}), do: o <> c

  # --- Fuzzy Tag Finding ---

  defp find_tag(text, id, type) do
    escaped_id = Regex.escape(id)
    
    # Patterns: 
    # Match [ or [[ + optional slashes + ID + optional slashes + ] or ]]
    # Strict about leading/trailing slashes based on type.
    
    pattern = 
      case type do
        :close -> 
           # Must have leading slash: [ /id ]
           "\\\[{1,2}\\\/" <> escaped_id <> "\\/?\]{1,2}"
        :self_closing ->
           # Must have trailing slash: [ id/ ]
           "\\\[{1,2}" <> escaped_id <> "\\/\]{1,2}"
        :open ->
           # Must NOT have leading slash: [ id ]
           "\\\[{1,2}" <> escaped_id <> "\\/?\]{1,2}" 
      end

    regex = Regex.compile!(pattern, "s")
    
    case Regex.run(regex, text, return: :index) do
      [{start_idx, len}] ->
        match_str = String.slice(text, start_idx, len)
        
        before_part = String.slice(text, 0, start_idx)
        after_part = String.slice(text, start_idx + len, String.length(text))
        
        # Always return 3-tuple including before_part
        {:match, match_str, after_part, before_part}
        
      nil ->
        :not_found
    end
  end
end