defmodule DocCoffeeLite.Translation.SimilarityGuard do
  @moduledoc """
  Compares source/translated text after stripping placeholders and whitespace.
  """

  defmodule SimilarityError do
    @enforce_keys [:level, :ratio]
    defstruct [:level, :ratio, :message]
  end

  @high_threshold 0.90
  @medium_threshold 0.50

  @spec similarity(binary() | nil, binary() | nil) :: float()
  def similarity(src, dst) do
    normalized_src = normalize(src)
    normalized_dst = normalize(dst)

    cond do
      normalized_src == "" and normalized_dst == "" -> 1.0
      normalized_src == "" or normalized_dst == "" -> 0.0
      true -> String.jaro_distance(normalized_src, normalized_dst)
    end
  end

  @spec classify(binary() | nil, binary() | nil) :: {:ok, float(), :low | :medium | :high}
  def classify(src, dst) do
    ratio = similarity(src, dst)

    level =
      cond do
        ratio >= @high_threshold -> :high
        ratio >= @medium_threshold -> :medium
        true -> :low
      end

    {:ok, ratio, level}
  end

  @spec check(binary() | nil, binary() | nil) :: {:ok, float()} | {:error, SimilarityError.t()}
  def check(src, dst) do
    {:ok, ratio, level} = classify(src, dst)

    case level do
      :high ->
        {:error,
         %SimilarityError{
           level: :high,
           ratio: ratio,
           message: "Similarity >= 90%"
         }}

      :medium ->
        {:error,
         %SimilarityError{
           level: :medium,
           ratio: ratio,
           message: "Similarity >= 50%"
         }}

      :low ->
        {:ok, ratio}
    end
  end

  @spec check_high(binary() | nil, binary() | nil) ::
          {:ok, float()} | {:error, SimilarityError.t()}
  def check_high(src, dst) do
    {:ok, ratio, level} = classify(src, dst)

    if level == :high do
      {:error, %SimilarityError{level: :high, ratio: ratio, message: "Similarity >= 90%"}}
    else
      {:ok, ratio}
    end
  end

  defp normalize(nil), do: ""

  defp normalize(text) when is_binary(text) do
    text
    |> String.replace(~r/\[\[[^\]]+\]\]/u, "")
    |> String.replace(~r/\s+/u, "")
  end
end
