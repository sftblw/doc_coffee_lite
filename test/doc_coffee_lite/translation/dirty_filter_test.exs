defmodule DocCoffeeLite.Translation.DirtyFilterTest do
  use DocCoffeeLite.DataCase

  alias DocCoffeeLite.Translation

  describe "list_units_for_review/2 filtering" do
    test "filters by is_dirty flag" do
      project = DocCoffeeLite.TranslationFixtures.project_fixture()
      group = DocCoffeeLite.TranslationFixtures.translation_group_fixture(project_id: project.id)

      # Create dirty unit
      dirty_unit =
        DocCoffeeLite.TranslationFixtures.translation_unit_fixture(
          translation_group_id: group.id,
          is_dirty: true,
          source_text: "Dirty",
          unit_key: "dirty_1"
        )

      # Create clean unit
      _clean_unit =
        DocCoffeeLite.TranslationFixtures.translation_unit_fixture(
          translation_group_id: group.id,
          is_dirty: false,
          source_text: "Clean",
          unit_key: "clean_1"
        )

      # Default (no filter)
      all_units = Translation.list_units_for_review(project.id)
      assert length(all_units) == 2

      # With only_dirty: true
      dirty_units = Translation.list_units_for_review(project.id, only_dirty: true)
      assert length(dirty_units) == 1
      assert hd(dirty_units).id == dirty_unit.id

      # With only_dirty: false
      all_units_explicit = Translation.list_units_for_review(project.id, only_dirty: false)
      assert length(all_units_explicit) == 2
    end
  end

  describe "count_units_for_review/3 filtering" do
    test "counts with is_dirty flag" do
      project = DocCoffeeLite.TranslationFixtures.project_fixture()
      group = DocCoffeeLite.TranslationFixtures.translation_group_fixture(project_id: project.id)

      DocCoffeeLite.TranslationFixtures.translation_unit_fixture(
        translation_group_id: group.id,
        is_dirty: true,
        unit_key: "dirty_2"
      )

      DocCoffeeLite.TranslationFixtures.translation_unit_fixture(
        translation_group_id: group.id,
        is_dirty: false,
        unit_key: "clean_2"
      )

      assert Translation.count_units_for_review(project.id, "", only_dirty: true) == 1
      assert Translation.count_units_for_review(project.id, "", only_dirty: false) == 2
    end
  end
end
