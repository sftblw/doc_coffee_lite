defmodule DocCoffeeLite.Translation.AutoHealerTest do
  use ExUnit.Case, async: true
  alias DocCoffeeLite.Translation.AutoHealer

  describe "heal/2" do
    test "restores whitespace structure from source" do
      source = "[[div_1]]\n  [[p_1]]Hello[[/p_1]]\n[[/div_1]]"
      trans = "[[div_1]] [[p_1]]Annyeong[[/p_1]] [[/div_1]]"
      
      expected = "[[div_1]]\n  [[p_1]]Annyeong[[/p_1]]\n[[/div_1]]"
      assert {:ok, result} = AutoHealer.heal(source, trans)
      assert result == expected
    end

    test "heals malformed tags" do
      source = "[[p_1]]Text[[/p_1]]"
      
      # Case 1: Missing closing bracket on open tag
      trans1 = "[[p_1]Annyeong[[/p_1]]"
      assert {:ok, "[[p_1]]Annyeong[[/p_1]]"} = AutoHealer.heal(source, trans1)
      
      # Case 2: Missing opening bracket on close tag
      trans2 = "[[p_1]]Annyeong[/p_1]]"
      assert {:ok, "[[p_1]]Annyeong[[/p_1]]"} = AutoHealer.heal(source, trans2)
    end

    test "handles nested structures correctly" do
      source = "[[div_1]][[p_1]]A[[/p_1]][[p_2]]B[[/p_2]][[/div_1]]"
      trans = "[[div_1]]  [[p_1]] A' [[/p_1]]  [[p_2]] B' [[/p_2]]  [[/div_1]]"
      
      # Source has no whitespace, so result should have no whitespace between tags
      # But inner content of p_1 and p_2 comes from trans
      expected = "[[div_1]][[p_1]] A' [[/p_1]][[p_2]] B' [[/p_2]][[/div_1]]"
      assert {:ok, result} = AutoHealer.heal(source, trans)
      assert result == expected
    end

    test "ignores garbage outside expected structure" do
      source = "[[p_1]]A[[/p_1]]"
      trans = "GARBAGE [[p_1]]A'[[/p_1]] TRASH"
      
      assert {:ok, "[[p_1]]A'[[/p_1]]"} = AutoHealer.heal(source, trans)
    end
    
test "fails gracefully when tags are missing" do
      source = "[[p_1]]A[[/p_1]]"
      trans = "No tags here"
      
      assert {:error, :healing_failed, fallback} = AutoHealer.heal(source, trans)
      # Fallback should attempt to be structural
      assert fallback == "[[p_1]][[/p_1]]"
    end

    test "handles self-closing tags" do
      source = "[[br_1/]]"
      trans = "Some text [[br_1/]] more text"
      
      assert {:ok, "[[br_1/]]"} = AutoHealer.heal(source, trans)
    end
  end
end
