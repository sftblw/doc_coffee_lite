defmodule DocCoffeeLite.Translation.ImportExport do
  @moduledoc """
  Handles Export and Import of project data using YAML metadata and ZIP archives.
  """

  import Ecto.Query
  require Logger
  alias DocCoffeeLite.Repo
  alias DocCoffeeLite.Translation
  alias DocCoffeeLite.Translation.{Project, SourceDocument, TranslationUnit}
  alias DocCoffeeLite.Epub
  alias DocCoffeeLite.Translation.Segmenter
  alias DocCoffeeLite.Translation.Persistence
  alias DocCoffeeLite.Translation.PolicyGenerator
  alias DocCoffeeLite.Translation.GlossaryCollector
  alias DocCoffeeLite.Translation.RunCreator

  @metadata_filename "doc_coffee.yaml"
  @translations_filename "translations.yaml"
  @source_dir "source"

  # --- EXPORT ---

  def export_project(project_id) do
    project = Repo.get!(Project, project_id)
    source_doc = Repo.one(from s in SourceDocument, where: s.project_id == ^project.id)

    if is_nil(source_doc) do
      {:error, :no_source_document}
    else
      manifest = build_manifest(project, source_doc)
      translations = fetch_translations(project.id)
      create_archive(manifest, source_doc, translations)
    end
  end

  defp build_manifest(project, source_doc) do
    %{
      "version" => "1.0",
      "exported_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "project" => %{
        "title" => project.title,
        "source_lang" => project.source_lang,
        "target_lang" => project.target_lang,
        "settings" => project.settings || %{}
      },
      "source_document" => %{
        "filename" => Path.basename(source_doc.source_path),
        "checksum" => source_doc.checksum,
        "format" => source_doc.format
      }
    }
  end

  defp fetch_translations(project_id) do
    # Fetch all units that have at least one block translation
    # We want the latest translation for each unit.
    query =
      from u in TranslationUnit,
        join: g in assoc(u, :translation_group),
        where: g.project_id == ^project_id,
        join: bt in assoc(u, :block_translations),
        distinct: u.id,
        order_by: [u.id, desc: bt.inserted_at],
        select: {u, bt}

    Repo.all(query)
    |> Enum.map(fn {unit, bt} ->
      %{
        "unit_key" => unit.unit_key,
        "source_hash" => unit.source_hash,
        "translated_text" => bt.translated_text,
        "translated_markup" => bt.translated_markup,
        "is_dirty" => unit.is_dirty
      }
    end)
  end

  defp create_archive(manifest, source_doc, translations) do
    # 1. Create Temp Directory
    tmp_dir = Path.join(System.tmp_dir(), "export_#{Ecto.UUID.generate()}")
    File.mkdir_p!(tmp_dir)

    try do
      # 2. Write YAML Manifest
      yaml_content = Ymlr.document!(manifest, sort_maps: true)
      File.write!(Path.join(tmp_dir, @metadata_filename), yaml_content)

      # 3. Write Translations
      translations_content = Ymlr.document!(translations, sort_maps: true)
      File.write!(Path.join(tmp_dir, @translations_filename), translations_content)

      # 4. Copy Source File
      dest_source_dir = Path.join(tmp_dir, @source_dir)
      File.mkdir_p!(dest_source_dir)

      # We assume source_doc.source_path exists and is accessible.
      # If stored in priv/uploads or similar, ensure path is correct.
      original_filename = Path.basename(source_doc.source_path)
      dest_source_path = Path.join(dest_source_dir, original_filename)

      # If source_path is relative, it might be relative to project root or work_dir?
      # Usually DB stores relative path or absolute path. We verify existence.
      real_source_path = resolve_source_path(source_doc.source_path)

      if File.exists?(real_source_path) do
        File.cp!(real_source_path, dest_source_path)

        # 5. Zip It
        project_title = manifest["project"]["title"]
        zip_filename = "doc_coffee_export_#{project_title |> slugify()}_#{Date.utc_today()}.zip"
        zip_path = Path.join(System.tmp_dir(), zip_filename)

        files_to_zip =
          File.ls!(tmp_dir)
          |> Enum.map(&String.to_charlist/1)

        {:ok, _} =
          :zip.create(
            String.to_charlist(zip_path),
            files_to_zip,
            cwd: String.to_charlist(tmp_dir)
          )

        {:ok, zip_path}
      else
        {:error, :source_file_not_found}
      end
    after
      File.rm_rf(tmp_dir)
    end
  end

  defp resolve_source_path(path) do
    if Path.type(path) == :absolute do
      path
    else
      Path.expand(path)
    end
  end

  defp slugify(string) do
    string
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
  end

  # --- IMPORT: EXISTING ---

  def import_to_existing(project_id, zip_path) do
    project = Repo.get!(Project, project_id)

    case unzip_archive(zip_path) do
      {:ok, tmp_dir} ->
        result =
          with {:ok, manifest} <- read_manifest(tmp_dir),
               {:ok, translations} <- read_translations(tmp_dir, manifest),
               :ok <- verify_compatibility(project, manifest),
               {:ok, count} <- apply_translations(project, translations) do
            {:ok, count}
          end

        File.rm_rf(tmp_dir)
        result

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp verify_compatibility(project, manifest) do
    # Check checksum of source document
    source_doc = Repo.one(from s in SourceDocument, where: s.project_id == ^project.id)

    # Checksum verification (Optional but recommended)
    manifest_checksum = get_in(manifest, ["source_document", "checksum"])

    cond do
      is_nil(source_doc) ->
        {:error, :no_source_document}

      source_doc.checksum == manifest_checksum ->
        :ok

      true ->
        # Allow force? For now, strict.
        {:error, :checksum_mismatch}
    end
  end

  defp apply_translations(project, translations) do
    result =
      Repo.transaction(fn ->
        Enum.reduce(translations, %{count: 0, skipped: 0}, fn entry, acc ->
          unit_key = entry["unit_key"]
          source_hash = entry["source_hash"]

          # Find unit by key
          unit =
            Repo.one(
              from u in TranslationUnit,
                join: g in assoc(u, :translation_group),
                where: g.project_id == ^project.id and u.unit_key == ^unit_key
            )

          cond do
            is_nil(unit) ->
              %{acc | skipped: acc.skipped + 1}

            is_binary(source_hash) and unit.source_hash != source_hash ->
              %{acc | skipped: acc.skipped + 1}

            true ->
              # Create BlockTranslation
              {:ok, _} =
                Translation.create_block_translation(%{
                  translation_unit_id: unit.id,
                  translation_run_id: nil,
                  translated_text: entry["translated_text"],
                  translated_markup: entry["translated_markup"] || entry["translated_text"],
                  metadata: %{"source" => "import"}
                })

              # Mark as translated
              Translation.update_translation_unit(unit, %{
                status: "translated",
                is_dirty: entry["is_dirty"] || false
              })

              %{acc | count: acc.count + 1}
          end
        end)
      end)

    case result do
      {:ok, %{count: count, skipped: skipped}} ->
        if skipped > 0 do
          Logger.warning(
            "Import skipped #{skipped} translations due to missing/mismatched units."
          )
        end

        {:ok, count}

      other ->
        other
    end
  end

  # --- IMPORT: NEW ---

  def import_as_new(zip_path) do
    case unzip_archive(zip_path) do
      {:ok, tmp_dir} ->
        result =
          with {:ok, manifest} <- read_manifest(tmp_dir),
               {:ok, translations} <- read_translations(tmp_dir, manifest),
               {:ok, project} <- create_project_from_manifest(manifest),
               {:ok, source_doc} <- setup_source_document(project, tmp_dir, manifest),
               :ok <- parse_source_document(project, source_doc),
               {:ok, _count} <- apply_translations(project, translations) do
            {:ok, project}
          end

        File.rm_rf(tmp_dir)
        result

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_project_from_manifest(manifest) do
    proj_data = manifest["project"] || %{}

    Translation.create_project(%{
      title: "#{proj_data["title"] || "Imported Project"} (Imported)",
      source_lang: proj_data["source_lang"],
      target_lang: proj_data["target_lang"],
      settings: proj_data["settings"] || %{}
    })
  end

  defp setup_source_document(project, tmp_dir, manifest) do
    src_data = manifest["source_document"]
    filename = src_data["filename"]

    # We expect file at source/filename inside tmp_dir
    extracted_source_path = Path.join([tmp_dir, @source_dir, filename])

    if File.exists?(extracted_source_path) do
      # Move to a permanent location
      upload_dir = Path.join(Application.app_dir(:doc_coffee_lite, "priv/uploads"), "imports")
      File.mkdir_p!(upload_dir)

      new_filename = "#{Ecto.UUID.generate()}_#{filename}"
      permanent_path = Path.join(upload_dir, new_filename)

      File.cp!(extracted_source_path, permanent_path)

      Translation.create_source_document(%{
        project_id: project.id,
        format: src_data["format"] || "epub",
        source_path: permanent_path,
        # Temp work dir for parsing
        work_dir: Path.join(upload_dir, "work_#{Ecto.UUID.generate()}"),
        checksum: src_data["checksum"],
        metadata: %{}
      })
    else
      {:error, :source_file_missing_in_archive}
    end
  end

  defp parse_source_document(project, source_doc) do
    # Ensure work_dir is ready
    File.mkdir_p!(source_doc.work_dir)

    with {:ok, session} <- Epub.open(source_doc.source_path, source_doc.work_dir),
         {:ok, %{tree: tree, groups: groups}} <- Segmenter.segment(:epub, session),
         {:ok, _persisted} <- Persistence.persist(tree, groups, project.id, source_doc.id),
         {:ok, _policies} <- PolicyGenerator.generate_from_session(project.id, session),
         {:ok, _terms} <- GlossaryCollector.collect(project.id),
         {:ok, _run} <-
           RunCreator.create(project.id, status: "draft", llm_opts: [allow_missing?: true]) do
      :ok
    else
      error -> error
    end
  end

  # --- UTILS ---

  defp unzip_archive(zip_path) do
    tmp_dir = Path.join(System.tmp_dir(), "import_#{Ecto.UUID.generate()}")
    File.mkdir_p!(tmp_dir)

    case :zip.unzip(String.to_charlist(zip_path), cwd: String.to_charlist(tmp_dir)) do
      {:ok, _} -> {:ok, tmp_dir}
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_manifest(tmp_dir) do
    manifest_path = Path.join(tmp_dir, @metadata_filename)

    if File.exists?(manifest_path) do
      YamlElixir.read_from_file(manifest_path)
    else
      {:error, :manifest_not_found}
    end
  end

  defp read_translations(tmp_dir, manifest) do
    translations_path = Path.join(tmp_dir, @translations_filename)

    cond do
      File.exists?(translations_path) ->
        case YamlElixir.read_from_file(translations_path) do
          {:ok, list} when is_list(list) -> {:ok, list}
          {:ok, %{"translations" => list}} when is_list(list) -> {:ok, list}
          {:ok, _} -> {:error, :invalid_translations}
          {:error, reason} -> {:error, reason}
        end

      is_list(manifest["translations"]) ->
        {:ok, manifest["translations"]}

      true ->
        Logger.warning("Translations file missing; import will proceed with no translations.")
        {:ok, []}
    end
  end
end
