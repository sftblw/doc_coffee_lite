defmodule DocCoffeeLite.Epub.Path do
  @moduledoc false

  @spec validate_relative_path(String.t()) :: :ok | {:error, atom()}
  def validate_relative_path(path) when is_binary(path) do
    normalized = String.replace(path, "\\", "/")

    cond do
      normalized in ["", "."] ->
        {:error, :empty_path}

      Elixir.Path.type(normalized) == :absolute ->
        {:error, :absolute_path}

      String.match?(normalized, ~r/^[A-Za-z]:/) ->
        {:error, :absolute_path}

      URI.parse(normalized).scheme != nil ->
        {:error, :absolute_path}

      normalized
      |> String.split("/", trim: true)
      |> Enum.any?(&(&1 == "..")) ->
        {:error, :unsafe_path}

      true ->
        :ok
    end
  end

  @spec safe_entry_path?(String.t()) :: boolean()
  def safe_entry_path?(path), do: validate_relative_path(path) == :ok

  @spec safe_join(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def safe_join(base_dir, path) do
    with :ok <- validate_relative_path(path) do
      base_dir = Elixir.Path.expand(base_dir)
      full_path = Elixir.Path.expand(Elixir.Path.join(base_dir, path))

      if full_path == base_dir or String.starts_with?(full_path, base_dir <> "/") do
        {:ok, full_path}
      else
        {:error, :path_escape}
      end
    end
  end
end
