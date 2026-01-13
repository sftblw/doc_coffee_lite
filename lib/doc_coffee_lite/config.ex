defmodule DocCoffeeLite.Config do
  @moduledoc """
  The Config context.
  """

  import Ecto.Query, warn: false
  alias DocCoffeeLite.Repo

  alias DocCoffeeLite.Config.LlmConfig

  @doc """
  Returns the list of llm_configs.

  ## Examples

      iex> list_llm_configs()
      [%LlmConfig{}, ...]

  """
  def list_llm_configs do
    Repo.all(LlmConfig)
  end

  @doc """
  Gets a single llm_config.

  Raises `Ecto.NoResultsError` if the Llm config does not exist.

  ## Examples

      iex> get_llm_config!(123)
      %LlmConfig{}

      iex> get_llm_config!(456)
      ** (Ecto.NoResultsError)

  """
  def get_llm_config!(id), do: Repo.get!(LlmConfig, id)

  @doc """
  Creates a llm_config.

  ## Examples

      iex> create_llm_config(%{field: value})
      {:ok, %LlmConfig{}}

      iex> create_llm_config(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_llm_config(attrs) do
    %LlmConfig{}
    |> LlmConfig.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a llm_config.

  ## Examples

      iex> update_llm_config(llm_config, %{field: new_value})
      {:ok, %LlmConfig{}}

      iex> update_llm_config(llm_config, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_llm_config(%LlmConfig{} = llm_config, attrs) do
    llm_config
    |> LlmConfig.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a llm_config.

  ## Examples

      iex> delete_llm_config(llm_config)
      {:ok, %LlmConfig{}}

      iex> delete_llm_config(llm_config)
      {:error, %Ecto.Changeset{}}

  """
  def delete_llm_config(%LlmConfig{} = llm_config) do
    Repo.delete(llm_config)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking llm_config changes.

  ## Examples

      iex> change_llm_config(llm_config)
      %Ecto.Changeset{data: %LlmConfig{}}

  """
  def change_llm_config(%LlmConfig{} = llm_config, attrs \\ %{}) do
    LlmConfig.changeset(llm_config, attrs)
  end
end
