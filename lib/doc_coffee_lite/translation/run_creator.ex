defmodule DocCoffeeLite.Translation.RunCreator do
  @moduledoc """
  Creates translation runs with policy and glossary snapshots.
  """

  import Ecto.Query
  alias DocCoffeeLite.Repo
  alias DocCoffeeLite.Translation.TranslationRun
  alias DocCoffeeLite.Translation.PolicySnapshot
  alias DocCoffeeLite.Translation.GlossarySnapshot
  alias DocCoffeeLite.Translation.LlmSelector

  @spec create(String.t(), keyword()) :: {:ok, TranslationRun.t()} | {:error, term()}
  def create(project_id, opts \\ []) do
    case latest_run(project_id) do
      %TranslationRun{} = run -> {:ok, run}
      nil -> create_new(project_id, opts)
    end
  end

  defp create_new(project_id, opts) do
    run_status = Keyword.get(opts, :status, "draft")
    policy_opts = Keyword.get(opts, :policy_opts, [])
    glossary_opts = Keyword.get(opts, :glossary_opts, [])
    llm_snapshot_opt = Keyword.get(opts, :llm_snapshot, :auto)
    llm_opts = Keyword.get(opts, :llm_opts, [])
    started_at = if run_status == "running", do: DateTime.utc_now(), else: nil

    with {:ok, policy_snapshot} <- PolicySnapshot.build(project_id, policy_opts),
         {:ok, glossary_snapshot} <- GlossarySnapshot.build(project_id, glossary_opts),
         {:ok, llm_snapshot} <- resolve_llm_snapshot(project_id, llm_snapshot_opt, llm_opts) do
      attrs = %{
        project_id: project_id,
        status: run_status,
        policy_snapshot: policy_snapshot,
        glossary_snapshot: glossary_snapshot,
        llm_config_snapshot: llm_snapshot,
        started_at: started_at,
        progress: 0
      }

      %TranslationRun{}
      |> TranslationRun.changeset(attrs)
      |> Repo.insert()
    end
    |> handle_create_result(project_id)
  end

  defp handle_create_result({:error, %Ecto.Changeset{} = changeset}, project_id) do
    case latest_run(project_id) do
      %TranslationRun{} = run -> {:ok, run}
      nil -> {:error, changeset}
    end
  end

  defp handle_create_result(result, _project_id), do: result

  defp resolve_llm_snapshot(project_id, :auto, opts) do
    LlmSelector.snapshot(project_id, opts)
  end

  defp resolve_llm_snapshot(_project_id, snapshot, _opts) when is_map(snapshot),
    do: {:ok, snapshot}

  defp resolve_llm_snapshot(_project_id, nil, _opts), do: {:ok, %{}}
  defp resolve_llm_snapshot(_project_id, :skip, _opts), do: {:ok, %{}}

  defp resolve_llm_snapshot(_project_id, snapshot, _opts),
    do: {:error, {:invalid_llm_snapshot, snapshot}}

  defp latest_run(project_id) do
    Repo.one(
      from r in TranslationRun,
        where: r.project_id == ^project_id,
        order_by: [desc: r.inserted_at],
        limit: 1
    )
  end
end
