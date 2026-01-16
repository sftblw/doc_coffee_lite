defmodule DocCoffeeLite.TranslationTest do
  use DocCoffeeLite.DataCase

  alias DocCoffeeLite.Translation

  describe "projects" do
    alias DocCoffeeLite.Translation.Project

    import DocCoffeeLite.TranslationFixtures

    @invalid_attrs %{
      status: nil,
      progress: nil,
      title: nil,
      settings: nil,
      source_lang: nil,
      target_lang: nil
    }

    test "list_projects/0 returns all projects" do
      project = project_fixture()
      assert Translation.list_projects() == [project]
    end

    test "get_project!/1 returns the project with given id" do
      project = project_fixture()
      assert Translation.get_project!(project.id) == project
    end

    test "create_project/1 with valid data creates a project" do
      valid_attrs = %{
        status: "some status",
        progress: 42,
        title: "some title",
        settings: %{},
        source_lang: "some source_lang",
        target_lang: "some target_lang"
      }

      assert {:ok, %Project{} = project} = Translation.create_project(valid_attrs)
      assert project.status == "some status"
      assert project.progress == 42
      assert project.title == "some title"
      assert project.settings == %{}
      assert project.source_lang == "some source_lang"
      assert project.target_lang == "some target_lang"
    end

    test "create_project/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Translation.create_project(@invalid_attrs)
    end

    test "update_project/2 with valid data updates the project" do
      project = project_fixture()

      update_attrs = %{
        status: "some updated status",
        progress: 43,
        title: "some updated title",
        settings: %{},
        source_lang: "some updated source_lang",
        target_lang: "some updated target_lang"
      }

      assert {:ok, %Project{} = project} = Translation.update_project(project, update_attrs)
      assert project.status == "some updated status"
      assert project.progress == 43
      assert project.title == "some updated title"
      assert project.settings == %{}
      assert project.source_lang == "some updated source_lang"
      assert project.target_lang == "some updated target_lang"
    end

    test "update_project/2 with invalid data returns error changeset" do
      project = project_fixture()
      assert {:error, %Ecto.Changeset{}} = Translation.update_project(project, @invalid_attrs)
      assert project == Translation.get_project!(project.id)
    end

    test "delete_project/1 deletes the project" do
      project = project_fixture()
      assert {:ok, %Project{}} = Translation.delete_project(project)
      assert_raise Ecto.NoResultsError, fn -> Translation.get_project!(project.id) end
    end

    test "change_project/1 returns a project changeset" do
      project = project_fixture()
      assert %Ecto.Changeset{} = Translation.change_project(project)
    end
  end

  describe "source_documents" do
    alias DocCoffeeLite.Translation.SourceDocument

    import DocCoffeeLite.TranslationFixtures

    @invalid_attrs %{format: nil, checksum: nil, metadata: nil, source_path: nil, work_dir: nil}

    test "list_source_documents/0 returns all source_documents" do
      source_document = source_document_fixture()
      assert Translation.list_source_documents() == [source_document]
    end

    test "get_source_document!/1 returns the source_document with given id" do
      source_document = source_document_fixture()
      assert Translation.get_source_document!(source_document.id) == source_document
    end

    test "create_source_document/1 with valid data creates a source_document" do
      valid_attrs = %{
        format: "some format",
        checksum: "some checksum",
        metadata: %{},
        source_path: "some source_path",
        work_dir: "some work_dir"
      }

      assert {:ok, %SourceDocument{} = source_document} =
               Translation.create_source_document(valid_attrs)

      assert source_document.format == "some format"
      assert source_document.checksum == "some checksum"
      assert source_document.metadata == %{}
      assert source_document.source_path == "some source_path"
      assert source_document.work_dir == "some work_dir"
    end

    test "create_source_document/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Translation.create_source_document(@invalid_attrs)
    end

    test "update_source_document/2 with valid data updates the source_document" do
      source_document = source_document_fixture()

      update_attrs = %{
        format: "some updated format",
        checksum: "some updated checksum",
        metadata: %{},
        source_path: "some updated source_path",
        work_dir: "some updated work_dir"
      }

      assert {:ok, %SourceDocument{} = source_document} =
               Translation.update_source_document(source_document, update_attrs)

      assert source_document.format == "some updated format"
      assert source_document.checksum == "some updated checksum"
      assert source_document.metadata == %{}
      assert source_document.source_path == "some updated source_path"
      assert source_document.work_dir == "some updated work_dir"
    end

    test "update_source_document/2 with invalid data returns error changeset" do
      source_document = source_document_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Translation.update_source_document(source_document, @invalid_attrs)

      assert source_document == Translation.get_source_document!(source_document.id)
    end

    test "delete_source_document/1 deletes the source_document" do
      source_document = source_document_fixture()
      assert {:ok, %SourceDocument{}} = Translation.delete_source_document(source_document)

      assert_raise Ecto.NoResultsError, fn ->
        Translation.get_source_document!(source_document.id)
      end
    end

    test "change_source_document/1 returns a source_document changeset" do
      source_document = source_document_fixture()
      assert %Ecto.Changeset{} = Translation.change_source_document(source_document)
    end
  end

  describe "document_nodes" do
    alias DocCoffeeLite.Translation.DocumentNode

    import DocCoffeeLite.TranslationFixtures

    @invalid_attrs %{
      node_type: nil,
      position: nil,
      level: nil,
      title: nil,
      metadata: nil,
      source_path: nil,
      node_id: nil,
      node_path: nil
    }

    test "list_document_nodes/0 returns all document_nodes" do
      document_node = document_node_fixture()
      assert Translation.list_document_nodes() == [document_node]
    end

    test "get_document_node!/1 returns the document_node with given id" do
      document_node = document_node_fixture()
      assert Translation.get_document_node!(document_node.id) == document_node
    end

    test "create_document_node/1 with valid data creates a document_node" do
      valid_attrs = %{
        node_type: "some node_type",
        position: 42,
        level: 42,
        title: "some title",
        metadata: %{},
        source_path: "some source_path",
        node_id: "some node_id",
        node_path: "some node_path"
      }

      assert {:ok, %DocumentNode{} = document_node} =
               Translation.create_document_node(valid_attrs)

      assert document_node.node_type == "some node_type"
      assert document_node.position == 42
      assert document_node.level == 42
      assert document_node.title == "some title"
      assert document_node.metadata == %{}
      assert document_node.source_path == "some source_path"
      assert document_node.node_id == "some node_id"
      assert document_node.node_path == "some node_path"
    end

    test "create_document_node/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Translation.create_document_node(@invalid_attrs)
    end

    test "update_document_node/2 with valid data updates the document_node" do
      document_node = document_node_fixture()

      update_attrs = %{
        node_type: "some updated node_type",
        position: 43,
        level: 43,
        title: "some updated title",
        metadata: %{},
        source_path: "some updated source_path",
        node_id: "some updated node_id",
        node_path: "some updated node_path"
      }

      assert {:ok, %DocumentNode{} = document_node} =
               Translation.update_document_node(document_node, update_attrs)

      assert document_node.node_type == "some updated node_type"
      assert document_node.position == 43
      assert document_node.level == 43
      assert document_node.title == "some updated title"
      assert document_node.metadata == %{}
      assert document_node.source_path == "some updated source_path"
      assert document_node.node_id == "some updated node_id"
      assert document_node.node_path == "some updated node_path"
    end

    test "update_document_node/2 with invalid data returns error changeset" do
      document_node = document_node_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Translation.update_document_node(document_node, @invalid_attrs)

      assert document_node == Translation.get_document_node!(document_node.id)
    end

    test "delete_document_node/1 deletes the document_node" do
      document_node = document_node_fixture()
      assert {:ok, %DocumentNode{}} = Translation.delete_document_node(document_node)
      assert_raise Ecto.NoResultsError, fn -> Translation.get_document_node!(document_node.id) end
    end

    test "change_document_node/1 returns a document_node changeset" do
      document_node = document_node_fixture()
      assert %Ecto.Changeset{} = Translation.change_document_node(document_node)
    end
  end

  describe "translation_groups" do
    alias DocCoffeeLite.Translation.TranslationGroup

    import DocCoffeeLite.TranslationFixtures

    @invalid_attrs %{
      position: nil,
      status: nil,
      progress: nil,
      metadata: nil,
      cursor: nil,
      group_key: nil,
      group_type: nil,
      context_summary: nil
    }

    test "list_translation_groups/0 returns all translation_groups" do
      translation_group = translation_group_fixture()
      assert Translation.list_translation_groups() == [translation_group]
    end

    test "get_translation_group!/1 returns the translation_group with given id" do
      translation_group = translation_group_fixture()
      assert Translation.get_translation_group!(translation_group.id) == translation_group
    end

    test "create_translation_group/1 with valid data creates a translation_group" do
      valid_attrs = %{
        position: 42,
        status: "some status",
        progress: 42,
        metadata: %{},
        cursor: 42,
        group_key: "some group_key",
        group_type: "some group_type",
        context_summary: "some context_summary"
      }

      assert {:ok, %TranslationGroup{} = translation_group} =
               Translation.create_translation_group(valid_attrs)

      assert translation_group.position == 42
      assert translation_group.status == "some status"
      assert translation_group.progress == 42
      assert translation_group.metadata == %{}
      assert translation_group.cursor == 42
      assert translation_group.group_key == "some group_key"
      assert translation_group.group_type == "some group_type"
      assert translation_group.context_summary == "some context_summary"
    end

    test "create_translation_group/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Translation.create_translation_group(@invalid_attrs)
    end

    test "update_translation_group/2 with valid data updates the translation_group" do
      translation_group = translation_group_fixture()

      update_attrs = %{
        position: 43,
        status: "some updated status",
        progress: 43,
        metadata: %{},
        cursor: 43,
        group_key: "some updated group_key",
        group_type: "some updated group_type",
        context_summary: "some updated context_summary"
      }

      assert {:ok, %TranslationGroup{} = translation_group} =
               Translation.update_translation_group(translation_group, update_attrs)

      assert translation_group.position == 43
      assert translation_group.status == "some updated status"
      assert translation_group.progress == 43
      assert translation_group.metadata == %{}
      assert translation_group.cursor == 43
      assert translation_group.group_key == "some updated group_key"
      assert translation_group.group_type == "some updated group_type"
      assert translation_group.context_summary == "some updated context_summary"
    end

    test "update_translation_group/2 with invalid data returns error changeset" do
      translation_group = translation_group_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Translation.update_translation_group(translation_group, @invalid_attrs)

      assert translation_group == Translation.get_translation_group!(translation_group.id)
    end

    test "delete_translation_group/1 deletes the translation_group" do
      translation_group = translation_group_fixture()
      assert {:ok, %TranslationGroup{}} = Translation.delete_translation_group(translation_group)

      assert_raise Ecto.NoResultsError, fn ->
        Translation.get_translation_group!(translation_group.id)
      end
    end

    test "change_translation_group/1 returns a translation_group changeset" do
      translation_group = translation_group_fixture()
      assert %Ecto.Changeset{} = Translation.change_translation_group(translation_group)
    end
  end

  describe "translation_units" do
    alias DocCoffeeLite.Translation.TranslationUnit

    import DocCoffeeLite.TranslationFixtures

    @invalid_attrs %{
      position: nil,
      status: nil,
      metadata: nil,
      unit_key: nil,
      source_text: nil,
      source_markup: nil,
      placeholders: nil,
      source_hash: nil
    }

    test "list_translation_units/0 returns all translation_units" do
      translation_unit = translation_unit_fixture()
      assert Translation.list_translation_units() == [translation_unit]
    end

    test "get_translation_unit!/1 returns the translation_unit with given id" do
      translation_unit = translation_unit_fixture()
      assert Translation.get_translation_unit!(translation_unit.id) == translation_unit
    end

    test "create_translation_unit/1 with valid data creates a translation_unit" do
      valid_attrs = %{
        position: 42,
        status: "some status",
        metadata: %{},
        unit_key: "some unit_key",
        source_text: "some source_text",
        source_markup: "some source_markup",
        placeholders: %{},
        source_hash: "some source_hash"
      }

      assert {:ok, %TranslationUnit{} = translation_unit} =
               Translation.create_translation_unit(valid_attrs)

      assert translation_unit.position == 42
      assert translation_unit.status == "some status"
      assert translation_unit.metadata == %{}
      assert translation_unit.unit_key == "some unit_key"
      assert translation_unit.source_text == "some source_text"
      assert translation_unit.source_markup == "some source_markup"
      assert translation_unit.placeholders == %{}
      assert translation_unit.source_hash == "some source_hash"
    end

    test "create_translation_unit/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Translation.create_translation_unit(@invalid_attrs)
    end

    test "update_translation_unit/2 with valid data updates the translation_unit" do
      translation_unit = translation_unit_fixture()

      update_attrs = %{
        position: 43,
        status: "some updated status",
        metadata: %{},
        unit_key: "some updated unit_key",
        source_text: "some updated source_text",
        source_markup: "some updated source_markup",
        placeholders: %{},
        source_hash: "some updated source_hash"
      }

      assert {:ok, %TranslationUnit{} = translation_unit} =
               Translation.update_translation_unit(translation_unit, update_attrs)

      assert translation_unit.position == 43
      assert translation_unit.status == "some updated status"
      assert translation_unit.metadata == %{}
      assert translation_unit.unit_key == "some updated unit_key"
      assert translation_unit.source_text == "some updated source_text"
      assert translation_unit.source_markup == "some updated source_markup"
      assert translation_unit.placeholders == %{}
      assert translation_unit.source_hash == "some updated source_hash"
    end

    test "update_translation_unit/2 with invalid data returns error changeset" do
      translation_unit = translation_unit_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Translation.update_translation_unit(translation_unit, @invalid_attrs)

      assert translation_unit == Translation.get_translation_unit!(translation_unit.id)
    end

    test "delete_translation_unit/1 deletes the translation_unit" do
      translation_unit = translation_unit_fixture()
      assert {:ok, %TranslationUnit{}} = Translation.delete_translation_unit(translation_unit)

      assert_raise Ecto.NoResultsError, fn ->
        Translation.get_translation_unit!(translation_unit.id)
      end
    end

    test "change_translation_unit/1 returns a translation_unit changeset" do
      translation_unit = translation_unit_fixture()
      assert %Ecto.Changeset{} = Translation.change_translation_unit(translation_unit)
    end
  end

  describe "translation_runs" do
    alias DocCoffeeLite.Translation.TranslationRun

    import DocCoffeeLite.TranslationFixtures

    @invalid_attrs %{
      status: nil,
      progress: nil,
      started_at: nil,
      policy_snapshot: nil,
      glossary_snapshot: nil,
      llm_config_snapshot: nil,
      completed_at: nil
    }

    test "list_translation_runs/0 returns all translation_runs" do
      translation_run = translation_run_fixture()
      assert Translation.list_translation_runs() == [translation_run]
    end

    test "get_translation_run!/1 returns the translation_run with given id" do
      translation_run = translation_run_fixture()
      assert Translation.get_translation_run!(translation_run.id) == translation_run
    end

    test "create_translation_run/1 with valid data creates a translation_run" do
      valid_attrs = %{
        status: "some status",
        progress: 42,
        started_at: ~U[2026-01-12 14:54:00Z],
        policy_snapshot: %{},
        glossary_snapshot: %{},
        llm_config_snapshot: %{},
        completed_at: ~U[2026-01-12 14:54:00Z]
      }

      assert {:ok, %TranslationRun{} = translation_run} =
               Translation.create_translation_run(valid_attrs)

      assert translation_run.status == "some status"
      assert translation_run.progress == 42
      assert translation_run.started_at == ~U[2026-01-12 14:54:00Z]
      assert translation_run.policy_snapshot == %{}
      assert translation_run.glossary_snapshot == %{}
      assert translation_run.llm_config_snapshot == %{}
      assert translation_run.completed_at == ~U[2026-01-12 14:54:00Z]
    end

    test "create_translation_run/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Translation.create_translation_run(@invalid_attrs)
    end

    test "update_translation_run/2 with valid data updates the translation_run" do
      translation_run = translation_run_fixture()

      update_attrs = %{
        status: "some updated status",
        progress: 43,
        started_at: ~U[2026-01-13 14:54:00Z],
        policy_snapshot: %{},
        glossary_snapshot: %{},
        llm_config_snapshot: %{},
        completed_at: ~U[2026-01-13 14:54:00Z]
      }

      assert {:ok, %TranslationRun{} = translation_run} =
               Translation.update_translation_run(translation_run, update_attrs)

      assert translation_run.status == "some updated status"
      assert translation_run.progress == 43
      assert translation_run.started_at == ~U[2026-01-13 14:54:00Z]
      assert translation_run.policy_snapshot == %{}
      assert translation_run.glossary_snapshot == %{}
      assert translation_run.llm_config_snapshot == %{}
      assert translation_run.completed_at == ~U[2026-01-13 14:54:00Z]
    end

    test "update_translation_run/2 with invalid data returns error changeset" do
      translation_run = translation_run_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Translation.update_translation_run(translation_run, @invalid_attrs)

      assert translation_run == Translation.get_translation_run!(translation_run.id)
    end

    test "delete_translation_run/1 deletes the translation_run" do
      translation_run = translation_run_fixture()
      assert {:ok, %TranslationRun{}} = Translation.delete_translation_run(translation_run)

      assert_raise Ecto.NoResultsError, fn ->
        Translation.get_translation_run!(translation_run.id)
      end
    end

    test "change_translation_run/1 returns a translation_run changeset" do
      translation_run = translation_run_fixture()
      assert %Ecto.Changeset{} = Translation.change_translation_run(translation_run)
    end
  end

  describe "block_translations" do
    alias DocCoffeeLite.Translation.BlockTranslation

    import DocCoffeeLite.TranslationFixtures

    @invalid_attrs %{
      status: nil,
      metadata: nil,
      translated_text: nil,
      translated_markup: nil,
      placeholders: nil,
      llm_response: nil,
      metrics: nil
    }

    test "list_block_translations/0 returns all block_translations" do
      block_translation = block_translation_fixture()
      assert Translation.list_block_translations() == [block_translation]
    end

    test "get_block_translation!/1 returns the block_translation with given id" do
      block_translation = block_translation_fixture()
      assert Translation.get_block_translation!(block_translation.id) == block_translation
    end

    test "create_block_translation/1 with valid data creates a block_translation" do
      valid_attrs = %{
        status: "some status",
        metadata: %{},
        translated_text: "some translated_text",
        translated_markup: "some translated_markup",
        placeholders: %{},
        llm_response: %{},
        metrics: %{}
      }

      assert {:ok, %BlockTranslation{} = block_translation} =
               Translation.create_block_translation(valid_attrs)

      assert block_translation.status == "some status"
      assert block_translation.metadata == %{}
      assert block_translation.translated_text == "some translated_text"
      assert block_translation.translated_markup == "some translated_markup"
      assert block_translation.placeholders == %{}
      assert block_translation.llm_response == %{}
      assert block_translation.metrics == %{}
    end

    test "create_block_translation/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Translation.create_block_translation(@invalid_attrs)
    end

    test "update_block_translation/2 with valid data updates the block_translation" do
      block_translation = block_translation_fixture()

      update_attrs = %{
        status: "some updated status",
        metadata: %{},
        translated_text: "some updated translated_text",
        translated_markup: "some updated translated_markup",
        placeholders: %{},
        llm_response: %{},
        metrics: %{}
      }

      assert {:ok, %BlockTranslation{} = block_translation} =
               Translation.update_block_translation(block_translation, update_attrs)

      assert block_translation.status == "some updated status"
      assert block_translation.metadata == %{}
      assert block_translation.translated_text == "some updated translated_text"
      assert block_translation.translated_markup == "some updated translated_markup"
      assert block_translation.placeholders == %{}
      assert block_translation.llm_response == %{}
      assert block_translation.metrics == %{}
    end

    test "update_block_translation/2 with invalid data returns error changeset" do
      block_translation = block_translation_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Translation.update_block_translation(block_translation, @invalid_attrs)

      assert block_translation == Translation.get_block_translation!(block_translation.id)
    end

    test "delete_block_translation/1 deletes the block_translation" do
      block_translation = block_translation_fixture()
      assert {:ok, %BlockTranslation{}} = Translation.delete_block_translation(block_translation)

      assert_raise Ecto.NoResultsError, fn ->
        Translation.get_block_translation!(block_translation.id)
      end
    end

    test "change_block_translation/1 returns a block_translation changeset" do
      block_translation = block_translation_fixture()
      assert %Ecto.Changeset{} = Translation.change_block_translation(block_translation)
    end
  end

  describe "policy_sets" do
    alias DocCoffeeLite.Translation.PolicySet

    import DocCoffeeLite.TranslationFixtures

    @invalid_attrs %{
      priority: nil,
      status: nil,
      metadata: nil,
      title: nil,
      source: nil,
      policy_key: nil,
      policy_text: nil,
      policy_type: nil
    }

    test "list_policy_sets/0 returns all policy_sets" do
      policy_set = policy_set_fixture()
      assert Translation.list_policy_sets() == [policy_set]
    end

    test "get_policy_set!/1 returns the policy_set with given id" do
      policy_set = policy_set_fixture()
      assert Translation.get_policy_set!(policy_set.id) == policy_set
    end

    test "create_policy_set/1 with valid data creates a policy_set" do
      valid_attrs = %{
        priority: 42,
        status: "some status",
        metadata: %{},
        title: "some title",
        source: "some source",
        policy_key: "some policy_key",
        policy_text: "some policy_text",
        policy_type: "some policy_type"
      }

      assert {:ok, %PolicySet{} = policy_set} = Translation.create_policy_set(valid_attrs)
      assert policy_set.priority == 42
      assert policy_set.status == "some status"
      assert policy_set.metadata == %{}
      assert policy_set.title == "some title"
      assert policy_set.source == "some source"
      assert policy_set.policy_key == "some policy_key"
      assert policy_set.policy_text == "some policy_text"
      assert policy_set.policy_type == "some policy_type"
    end

    test "create_policy_set/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Translation.create_policy_set(@invalid_attrs)
    end

    test "update_policy_set/2 with valid data updates the policy_set" do
      policy_set = policy_set_fixture()

      update_attrs = %{
        priority: 43,
        status: "some updated status",
        metadata: %{},
        title: "some updated title",
        source: "some updated source",
        policy_key: "some updated policy_key",
        policy_text: "some updated policy_text",
        policy_type: "some updated policy_type"
      }

      assert {:ok, %PolicySet{} = policy_set} =
               Translation.update_policy_set(policy_set, update_attrs)

      assert policy_set.priority == 43
      assert policy_set.status == "some updated status"
      assert policy_set.metadata == %{}
      assert policy_set.title == "some updated title"
      assert policy_set.source == "some updated source"
      assert policy_set.policy_key == "some updated policy_key"
      assert policy_set.policy_text == "some updated policy_text"
      assert policy_set.policy_type == "some updated policy_type"
    end

    test "update_policy_set/2 with invalid data returns error changeset" do
      policy_set = policy_set_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Translation.update_policy_set(policy_set, @invalid_attrs)

      assert policy_set == Translation.get_policy_set!(policy_set.id)
    end

    test "delete_policy_set/1 deletes the policy_set" do
      policy_set = policy_set_fixture()
      assert {:ok, %PolicySet{}} = Translation.delete_policy_set(policy_set)
      assert_raise Ecto.NoResultsError, fn -> Translation.get_policy_set!(policy_set.id) end
    end

    test "change_policy_set/1 returns a policy_set changeset" do
      policy_set = policy_set_fixture()
      assert %Ecto.Changeset{} = Translation.change_policy_set(policy_set)
    end
  end

  describe "glossary_terms" do
    alias DocCoffeeLite.Translation.GlossaryTerm

    import DocCoffeeLite.TranslationFixtures

    @invalid_attrs %{
      status: nil,
      metadata: nil,
      source: nil,
      source_text: nil,
      target_text: nil,
      notes: nil,
      usage_count: nil
    }

    test "list_glossary_terms/0 returns all glossary_terms" do
      glossary_term = glossary_term_fixture()
      assert Translation.list_glossary_terms() == [glossary_term]
    end

    test "get_glossary_term!/1 returns the glossary_term with given id" do
      glossary_term = glossary_term_fixture()
      assert Translation.get_glossary_term!(glossary_term.id) == glossary_term
    end

    test "create_glossary_term/1 with valid data creates a glossary_term" do
      valid_attrs = %{
        status: "some status",
        metadata: %{},
        source: "some source",
        source_text: "some source_text",
        target_text: "some target_text",
        notes: "some notes",
        usage_count: 42
      }

      assert {:ok, %GlossaryTerm{} = glossary_term} =
               Translation.create_glossary_term(valid_attrs)

      assert glossary_term.status == "some status"
      assert glossary_term.metadata == %{}
      assert glossary_term.source == "some source"
      assert glossary_term.source_text == "some source_text"
      assert glossary_term.target_text == "some target_text"
      assert glossary_term.notes == "some notes"
      assert glossary_term.usage_count == 42
    end

    test "create_glossary_term/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Translation.create_glossary_term(@invalid_attrs)
    end

    test "update_glossary_term/2 with valid data updates the glossary_term" do
      glossary_term = glossary_term_fixture()

      update_attrs = %{
        status: "some updated status",
        metadata: %{},
        source: "some updated source",
        source_text: "some updated source_text",
        target_text: "some updated target_text",
        notes: "some updated notes",
        usage_count: 43
      }

      assert {:ok, %GlossaryTerm{} = glossary_term} =
               Translation.update_glossary_term(glossary_term, update_attrs)

      assert glossary_term.status == "some updated status"
      assert glossary_term.metadata == %{}
      assert glossary_term.source == "some updated source"
      assert glossary_term.source_text == "some updated source_text"
      assert glossary_term.target_text == "some updated target_text"
      assert glossary_term.notes == "some updated notes"
      assert glossary_term.usage_count == 43
    end

    test "update_glossary_term/2 with invalid data returns error changeset" do
      glossary_term = glossary_term_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Translation.update_glossary_term(glossary_term, @invalid_attrs)

      assert glossary_term == Translation.get_glossary_term!(glossary_term.id)
    end

    test "delete_glossary_term/1 deletes the glossary_term" do
      glossary_term = glossary_term_fixture()
      assert {:ok, %GlossaryTerm{}} = Translation.delete_glossary_term(glossary_term)
      assert_raise Ecto.NoResultsError, fn -> Translation.get_glossary_term!(glossary_term.id) end
    end

    test "change_glossary_term/1 returns a glossary_term changeset" do
      glossary_term = glossary_term_fixture()
      assert %Ecto.Changeset{} = Translation.change_glossary_term(glossary_term)
    end
  end
end
