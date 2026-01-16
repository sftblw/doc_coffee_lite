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
  @min_content_chars 128

  @text_tags [
    "p",
    "div",
    "span",
    "li",
    "blockquote",
    "dd",
    "dt",
    "figcaption",
    "caption",
    "h1",
    "h2",
    "h3",
    "h4",
    "h5",
    "h6"
  ]

  @non_text_tags [
    "code",
    "pre",
    "kbd",
    "samp",
    "td",
    "th",
    "script",
    "style"
  ]

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

  @spec classify(binary() | nil, binary() | nil) ::
          {:ok, float(), :low | :medium | :high} | {:skip, float(), :skip}
  def classify(src, dst) do
    ratio = similarity(src, dst)

    if eligible?(src) do
      level =
        cond do
          ratio >= @high_threshold -> :high
          ratio >= @medium_threshold -> :medium
          true -> :low
        end

      {:ok, ratio, level}
    else
      {:skip, ratio, :skip}
    end
  end

  @spec check(binary() | nil, binary() | nil) ::
          {:ok, float()} | {:skip, float()} | {:error, SimilarityError.t()}
  def check(src, dst) do
    case classify(src, dst) do
      {:ok, ratio, :high} ->
        {:error,
         %SimilarityError{
           level: :high,
           ratio: ratio,
           message: "Similarity >= 90%"
         }}

      {:ok, ratio, :medium} ->
        {:error,
         %SimilarityError{
           level: :medium,
           ratio: ratio,
           message: "Similarity >= 50%"
         }}

      {:ok, ratio, :low} ->
        {:ok, ratio}

      {:skip, ratio, :skip} ->
        {:skip, ratio}
    end
  end

  @spec check_high(binary() | nil, binary() | nil) ::
          {:ok, float()} | {:skip, float()} | {:error, SimilarityError.t()}
  def check_high(src, dst) do
    case classify(src, dst) do
      {:ok, ratio, :high} ->
        {:error, %SimilarityError{level: :high, ratio: ratio, message: "Similarity >= 90%"}}

      {:ok, ratio, _level} ->
        {:ok, ratio}

      {:skip, ratio, :skip} ->
        {:skip, ratio}
    end
  end

  defp normalize(nil), do: ""

  defp normalize(text) when is_binary(text) do
    text
    |> strip_placeholders()
    |> String.replace(~r/\s+/u, "")
  end

  defp eligible?(src) when is_binary(src) do
    content_len =
      src
      |> strip_placeholders()
      |> String.replace(~r/[^\p{L}\p{N}]+/u, "")
      |> String.length()

    content_len >= @min_content_chars and text_tag_allowed?(src)
  end

  defp eligible?(_), do: false

  defp text_tag_allowed?(src) do
    tags =
      src
      |> extract_tags()
      |> Enum.map(&String.downcase/1)

    cond do
      tags == [] ->
        true

      Enum.any?(tags, &(&1 in @non_text_tags)) ->
        false

      Enum.any?(tags, &(&1 in @text_tags)) ->
        true

      true ->
        false
    end
  end

  defp extract_tags(text) do
    Regex.scan(~r/\[\[\/?([a-zA-Z0-9:-]+)_\d+\/?\]\]/, text)
    |> Enum.map(fn
      [_, tag] -> tag
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp strip_placeholders(text) do
    String.replace(text, ~r/\[\[[^\]]+\]\]/u, "")
  end
end
