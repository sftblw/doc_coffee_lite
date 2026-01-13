defmodule DocCoffeeLite.Translation.PolicyGenerator do
  @moduledoc """
  Generates initial policy sets from document metadata and table of contents.
  """

  alias DocCoffeeLite.Repo
  alias DocCoffeeLite.Epub.Path, as: EpubPath
  alias DocCoffeeLite.Epub.Session
  alias DocCoffeeLite.Translation.DocumentTree
  alias DocCoffeeLite.Translation.PolicySet

  @default_toc_limit 50

  @spec generate_from_session(String.t(), Session.t(), keyword()) ::
          {:ok, [PolicySet.t()]} | {:error, term()}
  def generate_from_session(project_id, %Session{} = session, opts \\ []) do
    metadata = session.package.metadata || %{}
    title = fetch_title(metadata)

    toc_paths = %{
      nav_path: session.package.nav_path,
      toc_ncx_path: session.package.toc_ncx_path
    }

    reader = fn path -> Session.read_file(session, path) end

    generate(project_id, title, metadata, toc_paths, reader, opts)
  end

  @spec generate_from_tree(String.t(), DocumentTree.t(), keyword()) ::
          {:ok, [PolicySet.t()]} | {:error, term()}
  def generate_from_tree(project_id, %DocumentTree{} = tree, opts \\ []) do
    metadata = fetch_tree_metadata(tree)
    title = fetch_title(metadata)
    toc_paths = fetch_toc_paths(tree)

    with {:ok, reader} <- tree_reader(tree) do
      generate(project_id, title, metadata, toc_paths, reader, opts)
    end
  end

  defp generate(project_id, title, metadata, toc_paths, reader, opts) do
    toc_info = read_toc_entries(toc_paths, reader, opts)
    policies = build_policies(title, metadata, toc_info, opts)
    persist_policies(project_id, policies, opts)
  end

  defp build_policies(title, metadata, toc_info, opts) do
    policies = [global_policy(opts)]
    policies = maybe_add_title_policy(policies, title)
    policies = maybe_add_toc_policy(policies, toc_info, opts)
    policies = maybe_add_metadata_policy(policies, metadata, opts)

    Enum.reject(policies, &is_nil/1)
  end

  defp global_policy(_opts) do
    %{policy_key: "auto:global",
      title: "Translation baseline",
      policy_text: """
      Translate faithfully without omitting content. Preserve placeholders and inline markup.
      Keep block boundaries; translate within each block only. Preserve list, table, and code
      structure while translating their text.
      """,
      policy_type: "global",
      source: "auto",
      status: "active",
      priority: 0,
      metadata: %{}
    }
  end

  defp maybe_add_title_policy(policies, nil), do: policies

  defp maybe_add_title_policy(policies, title) when is_binary(title) do
    [
      %{policy_key: "auto:title",
        title: "Title translation",
        policy_text: """
        Book title: "#{title}"
        Translate the title consistently and reuse the same translation in headings and metadata.
        """,
        policy_type: "title",
        source: "auto",
        status: "active",
        priority: 10,
        metadata: %{}
      }
      | policies
    ]
  end

  defp maybe_add_toc_policy(policies, %{entries: []}, _opts), do: policies

  defp maybe_add_toc_policy(policies, %{entries: entries, source: source}, opts) do
    limit = Keyword.get(opts, :toc_limit, @default_toc_limit)
    {limited, truncated?} = limit_entries(entries, limit)

    toc_text =
      limited
      |> Enum.map(&"- #{&1}")
      |> Enum.join("\n")

    metadata = %{
      toc_count: length(entries),
      toc_source: to_string(source),
      toc_truncated?: truncated?
    }

    [
      %{policy_key: "auto:toc",
        title: "Table of contents",
        policy_text: """
        Table of contents entries (translate consistently):
        #{toc_text}
        """,
        policy_type: "toc",
        source: "auto",
        status: "active",
        priority: 20,
        metadata: metadata
      }
      | policies
    ]
  end

  defp maybe_add_metadata_policy(policies, metadata, opts) do
    metadata = drop_title_metadata(metadata)
    lines = metadata_lines(metadata)
    limit = Keyword.get(opts, :metadata_limit, 20)
    {limited, truncated?} = limit_entries(lines, limit)

    case limited do
      [] ->
        policies

      _ ->
        metadata_text =
          limited
          |> Enum.map(&"- #{&1}")
          |> Enum.join("\n")

        metadata_map = %{
          metadata_count: length(lines),
          metadata_truncated?: truncated?
        }

        [
          %{policy_key: "auto:metadata",
            title: "Metadata references",
            policy_text: """
            Metadata for reference (keep proper nouns consistent):
            #{metadata_text}
            """,
            policy_type: "custom",
            source: "auto",
            status: "active",
            priority: 30,
            metadata: metadata_map
          }
          | policies
        ]
    end
  end

  defp persist_policies(project_id, policies, _opts) do
    Repo.transaction(fn ->
      Enum.map(policies, fn attrs ->
        attrs = Map.put(attrs, :project_id, project_id)

        %PolicySet{}
        |> PolicySet.changeset(attrs)
        |> Repo.insert!(
          on_conflict: {:replace_all_except, [:id, :inserted_at]},
          conflict_target: [:project_id, :policy_key]
        )
      end)
    end)
  end

  defp read_toc_entries(toc_paths, reader, _opts) do
    nav_path = fetch_toc_path(toc_paths, :nav_path)
    ncx_path = fetch_toc_path(toc_paths, :toc_ncx_path)

    nav_entries =
      case nav_path do
        nil -> {:ok, []}
        _ -> read_nav_toc(nav_path, reader)
      end

    case nav_entries do
      {:ok, entries} when entries != [] ->
        %{entries: clean_entries(entries), source: :nav}

      _ ->
        ncx_entries =
          case ncx_path do
            nil -> {:ok, []}
            _ -> read_ncx_toc(ncx_path, reader)
          end

        case ncx_entries do
          {:ok, entries} ->
            %{entries: clean_entries(entries), source: :ncx}

          _ ->
            %{entries: [], source: :none}
        end
    end
  end

  defp read_nav_toc(path, reader) do
    with {:ok, xml} <- reader.(path),
         {:ok, doc} <- parse_xml(xml) do
      navs = xpath(doc, ~c"//*[local-name()='nav']")
      nav = find_nav_toc(navs) || List.first(navs)

      case nav do
        nil ->
          {:ok, []}

        _ ->
          links = xpath(nav, ~c".//*[local-name()='a']")
          entries = Enum.map(links, &xpath_text(&1, ~c".//text()"))
          {:ok, entries}
      end
    end
  end

  defp read_ncx_toc(path, reader) do
    with {:ok, xml} <- reader.(path),
         {:ok, doc} <- parse_xml(xml) do
      navpoints = xpath(doc, ~c"//*[local-name()='navPoint']")

      entries =
        Enum.map(navpoints, fn navpoint ->
          xpath_text(navpoint, ~c".//*[local-name()='navLabel']/*[local-name()='text']/text()")
        end)

      {:ok, entries}
    end
  end

  defp find_nav_toc(navs) do
    Enum.find(navs, fn nav ->
      {_, attrs, _} = :xmerl_lib.simplify_element(nav)

      case attr_value(attrs, :type) || attr_value(attrs, :"epub:type") do
        "toc" -> true
        _ -> false
      end
    end)
  end

  defp fetch_tree_metadata(%DocumentTree{metadata: metadata}) when is_map(metadata) do
    case map_get(metadata, :metadata) do
      %{} = map -> map
      _ -> %{}
    end
  end

  defp fetch_tree_metadata(_tree), do: %{}

  defp fetch_toc_paths(%DocumentTree{metadata: metadata}) when is_map(metadata) do
    %{nav_path: map_get(metadata, :nav_path),
      toc_ncx_path: map_get(metadata, :toc_ncx_path)
    }
  end

  defp fetch_toc_paths(_tree), do: %{nav_path: nil, toc_ncx_path: nil}

  defp tree_reader(%DocumentTree{work_dir: nil}), do: {:error, :missing_work_dir}

  defp tree_reader(%DocumentTree{work_dir: work_dir}) do
    reader = fn path ->
      with :ok <- EpubPath.validate_relative_path(path),
           {:ok, full_path} <- EpubPath.safe_join(work_dir, path) do
        File.read(full_path)
      end
    end

    {:ok, reader}
  end

  defp fetch_title(metadata) when is_map(metadata) do
    map_get(metadata, :title)
  end

  defp fetch_title(_), do: nil

  defp drop_title_metadata(metadata) when is_map(metadata) do
    metadata
    |> Map.drop([:title, "title"])
  end

  defp drop_title_metadata(_), do: %{}

  defp metadata_lines(metadata) when is_map(metadata) do
    metadata
    |> Enum.reject(fn {_key, value} -> is_nil(value) or to_string(value) == "" end)
    |> Enum.map(fn {key, value} -> "#{key}: #{value}" end)
    |> Enum.sort()
  end

  defp metadata_lines(_), do: []

  defp limit_entries(entries, limit) when is_integer(limit) and limit > 0 do
    limited = Enum.take(entries, limit)
    truncated? = length(entries) > length(limited)
    {limited, truncated?}
  end

  defp limit_entries(entries, _limit), do: {entries, false}

  defp clean_entries(entries) do
    entries
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp fetch_toc_path(paths, key) when is_map(paths) do
    map_get(paths, key)
  end

  defp fetch_toc_path(_paths, _key), do: nil

  defp map_get(map, key, default \\ nil) when is_map(map) do
    cond do
      Map.has_key?(map, key) -> Map.get(map, key, default)
      Map.has_key?(map, to_string(key)) -> Map.get(map, to_string(key), default)
      true -> default
    end
  end

  defp xpath(doc, path) do
    :xmerl_xpath.string(path, doc)
  end

  defp xpath_text(doc, path) do
    doc
    |> xpath(path)
    |> Enum.map(&text_from_node/1)
    |> Enum.join()
    |> String.trim()
  end

  defp text_from_node({:xmlText, _parents, _pos, _lang, value, _type}), do: to_string(value)
  defp text_from_node(value) when is_list(value), do: to_string(value)
  defp text_from_node(value) when is_binary(value), do: value
  defp text_from_node(_), do: ""

  defp attr_value(attrs, name) do
    case List.keyfind(attrs, name, 0) do
      {^name, value} -> value |> to_string() |> String.trim()
      nil -> nil
    end
  end

  defp parse_xml(xml) do
    try do
      {doc, _} = :xmerl_scan.string(:erlang.binary_to_list(xml))
      {:ok, doc}
    catch
      _, reason -> {:error, {:xml_parse_error, reason}}
    end
  end
end
