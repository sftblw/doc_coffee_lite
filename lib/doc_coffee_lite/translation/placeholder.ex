defmodule DocCoffeeLite.Translation.Placeholder do
  @moduledoc """
  Handles protecting HTML tags by replacing them with placeholders like [[1]]
  and restoring them after translation.
  """

  @doc """
  Replaces HTML tags with placeholders and returns the protected text and a map of original tags.
  """
  def protect(markup) when is_binary(markup) do
    # Regex to find all HTML tags
    regex = ~r/<[^>]+>/
    
    tags = Regex.scan(regex, markup) |> List.flatten()
    
    {protected_text, mapping, _count} =
      Enum.reduce(tags, {markup, %{}, 1}, fn tag, {text, acc, index} ->
        placeholder = "[[#{index}]]"
        # Only replace the FIRST occurrence to handle identical tags correctly
        new_text = String.replace(text, tag, placeholder, global: false)
        {new_text, Map.put(acc, to_string(index), tag), index + 1}
      end)
      
    {protected_text, mapping}
  end

  @doc """
  Restores original tags from placeholders.
  """
  def restore(nil, _), do: ""
  def restore(text, mapping) when is_map(mapping) do
    # Sort indices in descending order to avoid partial replacement issues (e.g. [[10]] replacing [[1]])
    indices = Map.keys(mapping) |> Enum.map(&String.to_integer/1) |> Enum.sort(:desc)
    
    Enum.reduce(indices, text, fn index, acc ->
      tag = Map.get(mapping, to_string(index))
      String.replace(acc, "[[#{index}]]", tag)
    end)
  end
end