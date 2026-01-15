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

        test "preserves legitimate broken-tag-like text in source" do
          # Source content ends with escaped &#91;&#91;/h 
          source = "[[p_1]]Content ending with &#91;&#91;/h[[/p_1]]"
          # Translation preserves it but drops the closing tag
          trans = "[[p_1]]Content ending with &#91;&#91;/h" 
          
          # We expect Healer to force [[/p_1]] but KEEP &#91;&#91;/h because it doesn't look like a broken tag [[...
          assert {:error, :healing_failed, result} = AutoHealer.heal(source, trans)
          assert result == "[[p_1]]Content ending with &#91;&#91;/h[[/p_1]]"
        end
    test "cleans up hallucinated broken tags" do
      source = "[[p_1]]Content[[/p_1]]"
      # LLM hallucinated [[/p at the end
      trans = "[[p_1]]Content[[/p"
      
      # We expect Healer to remove [[/p and force [[/p_1]]
      assert {:error, :healing_failed, result} = AutoHealer.heal(source, trans)
      assert result == "[[p_1]]Content[[/p_1]]"
    end
  end
end