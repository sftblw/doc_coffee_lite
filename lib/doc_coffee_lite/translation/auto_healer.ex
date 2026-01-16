defmodule DocCoffeeLite.Translation.AutoHealer do
  @moduledoc """
  Auto-heal LLM outputs that contain simplified tag tokens like [[p_1]] ... [[/p_1]].

  Strategy:
  - Source tokens (strict gold only) define the correct tag skeleton.
  - Target tokens (lenient) are used only as anchors; all target tag tokens are dropped.
  - Text is preserved; tags are re-inserted from source.
  - Closing tags prefer the latest viable match (to keep text inside when duplicates exist).
  - Missing closing tags are deferred to capture as much text as possible.
  """

  defmodule Token do
    @enforce_keys [:kind, :tag, :num, :raw, :start, :stop, :quality]
    defstruct [:kind, :tag, :num, :raw, :start, :stop, :quality]
    # kind: :open | :close | :self
    # quality: :gold | :broken_left | :broken_right
  end

  defmodule HealError do
    @enforce_keys [:reason, :stats]
    defstruct [:reason, :stats, :message, :debug]
    # reason: :source_not_well_formed | :too_many_missing | :no_anchor
  end

  @type opt ::
          {:max_insert_ratio, float()}
          | {:fail_if_no_anchor, boolean()}

  @default_max_insert_ratio 0.70
  @default_fail_if_no_anchor false

  @ws_bytes [?\s, ?\t, ?\n, ?\r, ?\f, ?\v]

  @doc """
  Heals `dst` to match the tag skeleton of `src`.

  Returns:
    {:ok, healed}
    {:error, %HealError{}}

  Options:
    - max_insert_ratio (default 0.70): if inserted tags exceed this ratio, error.
    - fail_if_no_anchor (default false): if no src-tag is found in dst at all, error.
  """
  @spec heal(binary(), binary(), [opt()]) :: {:ok, binary()} | {:error, HealError.t()}
  def heal(src, dst, opts \\ []) when is_binary(src) and is_binary(dst) do
    max_insert_ratio = Keyword.get(opts, :max_insert_ratio, @default_max_insert_ratio)
    fail_if_no_anchor = Keyword.get(opts, :fail_if_no_anchor, @default_fail_if_no_anchor)

    {src_lead, _src_core, src_trail} = split_outer_ascii_ws(src)
    dst_trimmed = trim_outer_ascii_ws(dst)

    src_tokens = tokenize_strict(src)

    with :ok <- validate_well_formed(src_tokens) do
      dst_tokens = tokenize_lenient(dst_trimmed)
      expected = reorder_expected_tokens(src_tokens, dst_tokens)

      {healed_core, stats} =
        rebuild_from_skeleton(expected, dst_trimmed, dst_tokens)

      expected_count = length(expected)
      inserted = stats.inserted
      matched = stats.matched

      cond do
        expected_count > 0 and fail_if_no_anchor and matched == 0 ->
          {:error,
           %HealError{
             reason: :no_anchor,
             stats: stats,
             message: "dst에서 src 태그 앵커를 1개도 찾지 못했습니다."
           }}

        expected_count > 0 and inserted / expected_count > max_insert_ratio ->
          {:error,
           %HealError{
             reason: :too_many_missing,
             stats: stats,
             message: "dst 태그 손상이 심해 src 태그를 너무 많이 생성했습니다."
           }}

        true ->
          {:ok, src_lead <> healed_core <> src_trail}
      end
    else
      {:error, %HealError{} = e} -> {:error, e}
    end
  end

  # -------------------------
  # Skeleton rebuild
  # -------------------------

  defp reorder_expected_tokens(src_tokens, dst_tokens) do
    dst_anchors = anchor_index_map(dst_tokens)

    src_tokens
    |> build_tag_tree()
    |> reorder_tree(dst_anchors)
    |> flatten_tree_tokens()
  end

  defp anchor_index_map(tokens) do
    tokens
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {tok, idx}, acc ->
      Map.put_new(acc, {tok.tag, tok.num}, idx)
    end)
  end

  defp build_tag_tree(tokens) do
    root = %{id: :root, open: nil, close: nil, self: nil, children: []}

    stack =
      Enum.reduce(tokens, [root], fn tok, stack ->
        case tok.kind do
          :open ->
            node = %{id: {tok.tag, tok.num}, open: tok, close: nil, self: nil, children: []}
            [node | stack]

          :self ->
            node = %{id: {tok.tag, tok.num}, open: nil, close: nil, self: tok, children: []}
            add_child(stack, node)

          :close ->
            [node | rest] = stack
            node = %{node | close: tok}
            add_child(rest, node)
        end
      end)

    case stack do
      [root_done] -> root_done
      [root_done | _] -> root_done
    end
  end

  defp add_child([parent | rest], child) do
    updated = %{parent | children: parent.children ++ [child]}
    [updated | rest]
  end

  defp reorder_tree(node, anchor_map) do
    reordered_children =
      node.children
      |> reorder_children(anchor_map)
      |> Enum.map(&reorder_tree(&1, anchor_map))

    %{node | children: reordered_children}
  end

  defp reorder_children(children, anchor_map) do
    anchored =
      children
      |> Enum.filter(&anchored_child?(&1, anchor_map))
      |> Enum.sort_by(&anchor_index(&1, anchor_map))

    {reordered, _} =
      Enum.map_reduce(children, anchored, fn child, queue ->
        if anchored_child?(child, anchor_map) do
          [next | rest] = queue
          {next, rest}
        else
          {child, queue}
        end
      end)

    reordered
  end

  defp anchored_child?(%{id: id}, anchor_map), do: Map.has_key?(anchor_map, id)
  defp anchor_index(%{id: id}, anchor_map), do: Map.get(anchor_map, id)

  defp flatten_tree_tokens(node) do
    node.children
    |> Enum.flat_map(&node_tokens/1)
  end

  defp node_tokens(%{self: %Token{} = tok}), do: [tok]

  defp node_tokens(%{open: %Token{} = open, close: %Token{} = close, children: children}) do
    [open | Enum.flat_map(children, &node_tokens/1)] ++ [close]
  end

  defp rebuild_from_skeleton(expected_tokens, dst_bin, dst_tokens) do
    tokens = List.to_tuple(dst_tokens)
    n = tuple_size(tokens)

    # deferred: list of raw closing tags that were missing and need to be appended after text
    {out_rev, pos, j, stats, deferred} =
      apply_expected(
        expected_tokens,
        expected_tokens |> tl_or_empty(),
        dst_bin,
        tokens,
        n,
        0,
        0,
        [],
        %{
          matched: 0,
          inserted: 0,
          dropped: 0
        },
        []
      )

    # drop remaining dst tag tokens, keep text
    {out_rev2, pos2, _j2, stats2} = drop_rest(dst_bin, tokens, n, pos, j, out_rev, stats)

    # append remaining text, THEN append deferred closing tags
    tail_text = slice(dst_bin, pos2, byte_size(dst_bin))
    final_rev = deferred ++ [tail_text | out_rev2]

    out = Enum.reverse(final_rev) |> IO.iodata_to_binary()

    {out, stats2}
  end

  defp apply_expected([], _tails, _dst, _tokens, _n, pos, j, out_rev, stats, deferred),
    do: {out_rev, pos, j, stats, deferred}

  defp apply_expected([exp | rest], tails, dst, tokens, n, pos, j, out_rev, stats, deferred) do
    tail_expected = tl_or_empty(tails)

    chosen =
      choose_match_index(exp, tail_expected, tokens, n, j)

    case chosen do
      nil ->
        # Missing tag
        if exp.kind == :close do
          # Defer closing tag to capture text
          apply_expected(
            rest,
            tail_expected,
            dst,
            tokens,
            n,
            pos,
            j,
            out_rev,
            %{stats | inserted: stats.inserted + 1},
            [exp.raw | deferred]
          )
        else
          # Open/Self tag missing: Flush deferred, then insert this tag
          out_rev_flushed = [exp.raw | deferred ++ out_rev]

          apply_expected(
            rest,
            tail_expected,
            dst,
            tokens,
            n,
            pos,
            j,
            out_rev_flushed,
            %{stats | inserted: stats.inserted + 1},
            []
          )
        end

      k ->
        # Matched tag
        # consume and drop dst tag tokens until k
        {out_rev1, pos1, _j1, stats1} = drop_until(dst, tokens, pos, j, k, out_rev, stats)

        tok = elem(tokens, k)

        # keep text before matched token, then flush deferred, then insert exp.raw
        pre_text = slice(dst, pos1, tok.start)
        out_rev2 = [exp.raw | deferred ++ [pre_text | out_rev1]]

        apply_expected(
          rest,
          tail_expected,
          dst,
          tokens,
          n,
          tok.stop,
          k + 1,
          out_rev2,
          %{stats1 | matched: stats1.matched + 1},
          []
        )
    end
  end

  defp choose_match_index(%Token{kind: kind} = exp, tail_expected, tokens, n, j) do
    candidates = find_candidates(exp, tokens, n, j)

    case kind do
      :close ->
        candidates
        |> Enum.reverse()
        |> Enum.find(fn k -> can_match_tail?(tail_expected, tokens, n, k + 1) end)

      :open ->
        candidates
        |> Enum.find(fn k -> can_match_tail?(tail_expected, tokens, n, k + 1) end)

      :self ->
        candidates
        |> Enum.find(fn k -> can_match_tail?(tail_expected, tokens, n, k + 1) end)
    end
  end

  defp can_match_tail?([], _tokens, _n, _start), do: true

  defp can_match_tail?([exp | rest], tokens, n, start) do
    k = find_first_match(exp, tokens, n, start)
    if is_nil(k), do: false, else: can_match_tail?(rest, tokens, n, k + 1)
  end

  defp find_first_match(exp, tokens, n, start) do
    if start >= n do
      nil
    else
      Enum.reduce_while(start..(n - 1), nil, fn i, _acc ->
        if match_token?(exp, elem(tokens, i)), do: {:halt, i}, else: {:cont, nil}
      end)
    end
  end

  defp find_candidates(exp, tokens, n, j) do
    if j >= n do
      []
    else
      Enum.reduce(j..(n - 1), [], fn i, acc ->
        if match_token?(exp, elem(tokens, i)), do: [i | acc], else: acc
      end)
      |> Enum.reverse()
    end
  end

  defp match_token?(%Token{kind: k, tag: t, num: n}, %Token{kind: k2, tag: t2, num: n2}),
    do: k == k2 and t == t2 and n == n2

  defp drop_until(_dst, _tokens, pos, j, k, out_rev, stats) when j >= k,
    do: {out_rev, pos, j, stats}

  defp drop_until(dst, tokens, pos, j, k, out_rev, stats) do
    tok = elem(tokens, j)
    # keep text before this token; drop the token itself
    pre = slice(dst, pos, tok.start)
    out_rev2 = [pre | out_rev]
    drop_until(dst, tokens, tok.stop, j + 1, k, out_rev2, %{stats | dropped: stats.dropped + 1})
  end

  defp drop_rest(_dst, _tokens, n, pos, j, out_rev, stats) when j >= n,
    do: {out_rev, pos, j, stats}

  defp drop_rest(dst, tokens, n, pos, j, out_rev, stats) do
    tok = elem(tokens, j)
    pre = slice(dst, pos, tok.start)
    out_rev2 = [pre | out_rev]
    drop_rest(dst, tokens, n, tok.stop, j + 1, out_rev2, %{stats | dropped: stats.dropped + 1})
  end

  defp tl_or_empty([]), do: []
  defp tl_or_empty([_ | t]), do: t

  defp slice(_bin, a, b) when a >= b, do: ""
  defp slice(bin, a, b), do: binary_part(bin, a, b - a)

  # -------------------------
  # Validation (src)
  # -------------------------

  defp validate_well_formed(tokens) do
    case do_validate(tokens, []) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error,
         %HealError{
           reason: :source_not_well_formed,
           stats: %{reason: reason},
           message: "src 태그가 well-formed가 아닙니다: #{inspect(reason)}"
         }}
    end
  end

  defp do_validate([], []), do: :ok
  defp do_validate([], stack), do: {:error, {:unclosed, Enum.reverse(stack)}}

  defp do_validate([%Token{kind: :self} | rest], stack), do: do_validate(rest, stack)

  defp do_validate([%Token{kind: :open, tag: t, num: n} | rest], stack),
    do: do_validate(rest, [{t, n} | stack])

  defp do_validate([%Token{kind: :close, tag: t, num: n} | rest], [{t, n} | stack]),
    do: do_validate(rest, stack)

  defp do_validate([%Token{kind: :close, tag: t, num: n} | _rest], stack),
    do: {:error, {:unexpected_close, {t, n}, stack}}

  # -------------------------
  # Tokenizers
  # -------------------------

  @doc "Strict: only [[tag_num]], [[/tag_num]], [[tag_num/]]"
  def tokenize_strict(bin) when is_binary(bin) do
    tokenize(bin, :strict)
  end

  @doc "Lenient: also accepts broken-left ([tag_num]] ...) and broken-right ([[tag_num] ...)"
  def tokenize_lenient(bin) when is_binary(bin) do
    tokenize(bin, :lenient)
  end

  defp tokenize(bin, mode) do
    len = byte_size(bin)
    do_tokenize(bin, mode, len, 0, [])
  end

  defp do_tokenize(_bin, _mode, len, i, acc) when i >= len, do: Enum.reverse(acc)

  defp do_tokenize(bin, mode, len, i, acc) do
    case :binary.at(bin, i) do
      ?[ ->
        cond do
          i + 1 < len and :binary.at(bin, i + 1) == ?[ ->
            case parse_tag_at(bin, mode, len, i, 2) do
              {:ok, tok, next_i} -> do_tokenize(bin, mode, len, next_i, [tok | acc])
              :error -> do_tokenize(bin, mode, len, i + 1, acc)
            end

          mode == :lenient ->
            case parse_tag_at(bin, mode, len, i, 1) do
              {:ok, tok, next_i} -> do_tokenize(bin, mode, len, next_i, [tok | acc])
              :error -> do_tokenize(bin, mode, len, i + 1, acc)
            end

          true ->
            do_tokenize(bin, mode, len, i + 1, acc)
        end

      _ ->
        do_tokenize(bin, mode, len, i + 1, acc)
    end
  end

  defp parse_tag_at(bin, mode, len, start, open_len) do
    j = start + open_len

    {is_close, j} =
      if j < len and :binary.at(bin, j) == ?/ do
        {true, j + 1}
      else
        {false, j}
      end

    with {:ok, tag, j2} <- read_name(bin, len, j),
         true <- (j2 < len and :binary.at(bin, j2) == ?_) or :error,
         {:ok, num, j3} <- read_digits(bin, len, j2 + 1),
         {is_self, j4} <- read_optional_self_slash(bin, len, j3),
         true <- not (is_close and is_self) or :error,
         {:ok, quality, close_len} <- read_closer(bin, mode, len, j4, open_len) do
      stop = j4 + close_len
      raw = binary_part(bin, start, stop - start)

      kind =
        cond do
          is_close -> :close
          is_self -> :self
          true -> :open
        end

      {:ok,
       %Token{
         kind: kind,
         tag: tag,
         num: num,
         raw: raw,
         start: start,
         stop: stop,
         quality: quality
       }, stop}
    else
      _ -> :error
    end
  end

  defp read_name(bin, len, j) do
    # allow: [A-Za-z0-9:-] at least 1 char
    start = j

    j2 =
      advance_while(bin, len, j, fn b ->
        (b >= ?a and b <= ?z) or (b >= ?A and b <= ?Z) or (b >= ?0 and b <= ?9) or b in [?:, ?-]
      end)

    if j2 > start do
      {:ok, binary_part(bin, start, j2 - start), j2}
    else
      :error
    end
  end

  defp read_digits(bin, len, j) do
    start = j
    j2 = advance_while(bin, len, j, fn b -> b >= ?0 and b <= ?9 end)

    if j2 > start do
      num = binary_part(bin, start, j2 - start) |> String.to_integer()
      {:ok, num, j2}
    else
      :error
    end
  end

  defp read_optional_self_slash(bin, len, j) do
    if j < len and :binary.at(bin, j) == ?/ do
      {true, j + 1}
    else
      {false, j}
    end
  end

  defp read_closer(bin, mode, len, j, open_len) do
    cond do
      open_len == 2 and j + 1 < len and :binary.at(bin, j) == ?] and :binary.at(bin, j + 1) == ?] ->
        {:ok, :gold, 2}

      open_len == 2 and mode == :lenient and j < len and :binary.at(bin, j) == ?] ->
        {:ok, :broken_right, 1}

      open_len == 1 and mode == :lenient and j + 1 < len and :binary.at(bin, j) == ?] and
          :binary.at(bin, j + 1) == ?] ->
        {:ok, :broken_left, 2}

      true ->
        :error
    end
  end

  defp advance_while(bin, len, j, fun) do
    cond do
      j >= len -> j
      fun.(:binary.at(bin, j)) -> advance_while(bin, len, j + 1, fun)
      true -> j
    end
  end

  # -------------------------
  # ASCII whitespace helpers
  # -------------------------

  defp ws_byte?(b), do: b in @ws_bytes

  defp split_outer_ascii_ws(bin) do
    len = byte_size(bin)
    lead_len = leading_ws_len(bin, len, 0)
    trail_len = trailing_ws_len(bin, len, len - 1, 0)

    lead = binary_part(bin, 0, lead_len)
    core = binary_part(bin, lead_len, len - lead_len - trail_len)
    trail = binary_part(bin, len - trail_len, trail_len)
    {lead, core, trail}
  end

  defp leading_ws_len(_bin, len, i) when i >= len, do: len

  defp leading_ws_len(bin, len, i) do
    if ws_byte?(:binary.at(bin, i)), do: leading_ws_len(bin, len, i + 1), else: i
  end

  defp trailing_ws_len(_bin, _len, i, acc) when i < 0, do: acc

  defp trailing_ws_len(bin, len, i, acc) do
    if ws_byte?(:binary.at(bin, i)),
      do: trailing_ws_len(bin, len, i - 1, acc + 1),
      else: acc
  end

  defp trim_outer_ascii_ws(bin) do
    {_, core, _} = split_outer_ascii_ws(bin)
    core
  end
end
