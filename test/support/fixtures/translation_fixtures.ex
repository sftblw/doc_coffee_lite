defmodule DocCoffeeLite.TranslationFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `DocCoffeeLite.Translation` context.
  """

  @doc """
  Generate a project.
  """
  def project_fixture(attrs \\ %{}) do
    {:ok, project} =
      attrs
      |> Enum.into(%{
        progress: 42,
        settings: %{},
        source_lang: "some source_lang",
        status: "some status",
        target_lang: "some target_lang",
        title: "some title"
      })
      |> DocCoffeeLite.Translation.create_project()

    project
  end

  @doc """
  Generate a source_document.
  """
  def source_document_fixture(attrs \\ %{}) do
    {:ok, source_document} =
      attrs
      |> Enum.into(%{
        checksum: "some checksum",
        format: "some format",
        metadata: %{},
        source_path: "some source_path",
        work_dir: "some work_dir"
      })
      |> DocCoffeeLite.Translation.create_source_document()

    source_document
  end

  @doc """
  Generate a document_node.
  """
  def document_node_fixture(attrs \\ %{}) do
    {:ok, document_node} =
      attrs
      |> Enum.into(%{
        level: 42,
        metadata: %{},
        node_id: "some node_id",
        node_path: "some node_path",
        node_type: "some node_type",
        position: 42,
        source_path: "some source_path",
        title: "some title"
      })
      |> DocCoffeeLite.Translation.create_document_node()

    document_node
  end

  @doc """
  Generate a translation_group.
  """
  def translation_group_fixture(attrs \\ %{}) do
    {:ok, translation_group} =
      attrs
      |> Enum.into(%{
        context_summary: "some context_summary",
        cursor: 42,
        group_key: "some group_key",
        group_type: "some group_type",
        metadata: %{},
        position: 42,
        progress: 42,
        status: "some status"
      })
      |> DocCoffeeLite.Translation.create_translation_group()

    translation_group
  end

  @doc """
  Generate a translation_unit.
  """
  def translation_unit_fixture(attrs \\ %{}) do
    {:ok, translation_unit} =
      attrs
      |> Enum.into(%{
        metadata: %{},
        placeholders: %{},
        position: 42,
        source_hash: "some source_hash",
        source_markup: "some source_markup",
        source_text: "some source_text",
        status: "some status",
        unit_key: "some unit_key"
      })
      |> DocCoffeeLite.Translation.create_translation_unit()

    translation_unit
  end

  @doc """
  Generate a translation_run.
  """
  def translation_run_fixture(attrs \\ %{}) do
    {:ok, translation_run} =
      attrs
      |> Enum.into(%{
        completed_at: ~U[2026-01-12 14:54:00Z],
        glossary_snapshot: %{},
        llm_config_snapshot: %{},
        policy_snapshot: %{},
        progress: 42,
        started_at: ~U[2026-01-12 14:54:00Z],
        status: "some status"
      })
      |> DocCoffeeLite.Translation.create_translation_run()

    translation_run
  end

  @doc """
  Generate a block_translation.
  """
  def block_translation_fixture(attrs \\ %{}) do
    {:ok, block_translation} =
      attrs
      |> Enum.into(%{
        llm_response: %{},
        metadata: %{},
        metrics: %{},
        placeholders: %{},
        status: "some status",
        translated_markup: "some translated_markup",
        translated_text: "some translated_text"
      })
      |> DocCoffeeLite.Translation.create_block_translation()

    block_translation
  end

  @doc """
  Generate a policy_set.
  """
  def policy_set_fixture(attrs \\ %{}) do
    {:ok, policy_set} =
      attrs
      |> Enum.into(%{
        metadata: %{},
        policy_key: "some policy_key",
        policy_text: "some policy_text",
        policy_type: "some policy_type",
        priority: 42,
        source: "some source",
        status: "some status",
        title: "some title"
      })
      |> DocCoffeeLite.Translation.create_policy_set()

    policy_set
  end

  @doc """
  Generate a glossary_term.
  """
  def glossary_term_fixture(attrs \\ %{}) do
    {:ok, glossary_term} =
      attrs
      |> Enum.into(%{
        metadata: %{},
        notes: "some notes",
        source: "some source",
        source_text: "some source_text",
        status: "some status",
        target_text: "some target_text",
        usage_count: 42
      })
      |> DocCoffeeLite.Translation.create_glossary_term()

    glossary_term
  end
end
