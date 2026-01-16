defmodule DocCoffeeLite.Translation.SimilarityGuardTest do
  use ExUnit.Case, async: true

  alias DocCoffeeLite.Translation.SimilarityGuard

  test "strips tags and whitespace before comparing" do
    body = String.duplicate("HelloWorld", 13)
    src = " [[p_1]]#{body}[[/p_1]] "
    dst = "[[p_1]]#{body}[[/p_1]]"

    {:ok, ratio, level} = SimilarityGuard.classify(src, dst)
    assert ratio == 1.0
    assert level == :high
  end

  test "classifies medium similarity between 50% and 90%" do
    src_body = String.duplicate("abcdefg", 19)
    dst_body = String.duplicate("abcxxxx", 19)
    src = "[[p_1]]#{src_body}[[/p_1]]"
    dst = "[[p_1]]#{dst_body}[[/p_1]]"

    {:ok, ratio, level} = SimilarityGuard.classify(src, dst)
    assert ratio >= 0.5
    assert ratio < 0.9
    assert level == :medium
  end

  test "classifies low similarity" do
    src = String.duplicate("abcdefg", 19)
    dst = String.duplicate("zzzzzzz", 19)
    {:ok, ratio, level} = SimilarityGuard.classify(src, dst)
    assert ratio < 0.5
    assert level == :low
  end
end
