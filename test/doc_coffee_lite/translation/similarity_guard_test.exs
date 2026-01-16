defmodule DocCoffeeLite.Translation.SimilarityGuardTest do
  use ExUnit.Case, async: true

  alias DocCoffeeLite.Translation.SimilarityGuard

  test "strips tags and whitespace before comparing" do
    src = " [[p_1]]Hello World[[/p_1]] "
    dst = "[[p_1]]HelloWorld[[/p_1]]"

    {:ok, ratio, level} = SimilarityGuard.classify(src, dst)
    assert ratio == 1.0
    assert level == :high
  end

  test "classifies medium similarity between 50% and 90%" do
    src = "[[p_1]]abcdefg[[/p_1]]"
    dst = "[[p_1]]abcxxxx[[/p_1]]"

    {:ok, ratio, level} = SimilarityGuard.classify(src, dst)
    assert ratio >= 0.5
    assert ratio < 0.9
    assert level == :medium
  end

  test "classifies low similarity" do
    {:ok, ratio, level} = SimilarityGuard.classify("abcdefg", "zzzzzzz")
    assert ratio < 0.5
    assert level == :low
  end
end
