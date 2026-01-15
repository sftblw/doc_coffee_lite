defmodule DocCoffeeLite.Translation.AutoHealerTest do
  use ExUnit.Case, async: true

  alias DocCoffeeLite.Translation.AutoHealer

  defp heal!(src, dst, opts \\ []) do
    case AutoHealer.heal(src, dst, opts) do
      {:ok, out} -> out
      {:error, e} -> flunk("expected ok, got error: #{inspect(e)}")
    end
  end

  test "gold -> 그대로 유지 (단, 바깥 공백은 src 기준)" do
    src = " \n[[p_1]]Hello[[/p_1]]\n "
    dst = "\t[[p_1]]안녕[[/p_1]]\t"
    out = heal!(src, dst)
    assert out == " \n[[p_1]]안녕[[/p_1]]\n "
  end

  test "broken-left close: [/p_1]]" do
    src = "[[p_1]]A[[/p_1]]"
    dst = "[[p_1]]번역[/p_1]]"
    out = heal!(src, dst)
    assert out == "[[p_1]]번역[[/p_1]]"
  end

  test "broken-right open: [[p_1]" do
    src = "[[p_1]]A[[/p_1]]"
    dst = "[[p_1]번역[[/p_1]]"
    out = heal!(src, dst)
    assert out == "[[p_1]]번역[[/p_1]]"
  end

  test "missing close: 없으면 생성" do
    src = "[[p_1]]A[[/p_1]]"
    dst = "[[p_1]]번역만있음"
    out = heal!(src, dst)
    assert out == "[[p_1]]번역만있음[[/p_1]]"
  end

  test "repeated close at end: [/p_1]][[/p_1]] 같은 꼬리 정리" do
    src = "[[p_1]]A[[/p_1]]"
    dst = "[[p_1]]번역[[/p_1]][[/p_1]]"
    out = heal!(src, dst)
    assert out == "[[p_1]]번역[[/p_1]]"
  end

  test "edge: early broken close then text then proper close -> 바깥(close는 늦게 매칭)" do
    src = "[[p_1]]A[[/p_1]]"
    dst = "[/p_1]] 야호 [[/p_1]]"
    out = heal!(src, dst)
    # open은 없어서 생성, close는 뒤쪽을 골라서 '야호'가 안에 남습니다.
    assert out == "[[p_1]] 야호 [[/p_1]]"
  end

  test "nested skeleton: 중첩 구조도 src 스켈레톤 유지" do
    src = "[[p_1]]a [[b_2]]X[[/b_2]] y[[/p_1]]"
    dst = "[[p_1]]a [[b_2]번역X[[/b_2]] y[[/p_1]]"
    out = heal!(src, dst)
    assert out == "[[p_1]]a [[b_2]]번역X[[/b_2]] y[[/p_1]]"
  end

  test "fail_if_no_anchor: dst에서 태그 앵커 0개면 실패시키기" do
    src = "[[p_1]]A[[/p_1]]"
    dst = "그냥 텍스트만"
    assert {:error, _} = AutoHealer.heal(src, dst, fail_if_no_anchor: true)
  end

  test "too_many_missing: 태그 생성 비율이 너무 높으면 실패시키기" do
    src = "[[p_1]]a[[/p_1]][[p_2]]b[[/p_2]][[p_3]]c[[/p_3]]"
    dst = "텍스트"
    assert {:error, _} = AutoHealer.heal(src, dst, max_insert_ratio: 0.3)
  end
end