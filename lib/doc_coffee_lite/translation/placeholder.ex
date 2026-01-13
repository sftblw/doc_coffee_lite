defmodule DocCoffeeLite.Translation.Placeholder do
  @moduledoc """
  Protects HTML tags using paired placeholders like [[1]]...[[/1]].
  """

  @doc """
  Replaces HTML tags with paired placeholders.
  Example: "Hello <b>World</b>" -> "Hello [[1]]World[[/1]]"
  """
  def protect(markup) when is_binary(markup) do
    # Regex to capture HTML tags: opening, closing, or self-closing
    # Groups: 1: full tag, 2: "/" if closing, 3: tag name, 4: "/" if self-closing
    regex = ~r/<(\/?)([a-zA-Z0-9:]+)(?:\s+[^>]*?)?(\/?)>/
    
    tags = Regex.scan(regex, markup, capture: :all)
    
    # We use a stack to match opening and closing tags with the same ID
    {protected_text, mapping, _, _} =
      Enum.reduce(tags, {markup, %{}, [], 1}, fn [full_tag, slash, _name, self_slash], {text, acc, stack, next_id} ->
        is_closing = slash == "/"
        is_self_closing = self_slash == "/"
        
        cond do
          is_self_closing ->
            id = next_id
            placeholder = "[[#{id}/]]"
            new_text = String.replace(text, full_tag, placeholder, global: false)
            {new_text, Map.put(acc, "#{id}/", full_tag), stack, next_id + 1}
            
          is_closing ->
            case stack do
              [{id, _opened_tag} | rest_stack] ->
                placeholder = "[[/#{id}]]"
                new_text = String.replace(text, full_tag, placeholder, global: false)
                {new_text, Map.put(acc, "/#{id}", full_tag), rest_stack, next_id}
              [] ->
                # Orphan closing tag, give it a unique ID
                id = next_id
                placeholder = "[[/#{id}]]"
                new_text = String.replace(text, full_tag, placeholder, global: false)
                {new_text, Map.put(acc, "/#{id}", full_tag), [], next_id + 1}
            end
            
          true -> # Opening tag
            id = next_id
            placeholder = "[[#{id}]]"
            new_text = String.replace(text, full_tag, placeholder, global: false)
            {new_text, Map.put(acc, "#{id}", full_tag), [{id, full_tag} | stack], next_id + 1}
        end
      end)
      
    {protected_text, mapping}
  end

  @doc """
  Restores original tags from paired placeholders.
  Supports both [[n]], [[/n]], and [[n/]].
  """
  def restore(nil, _), do: ""
  def restore(text, mapping) when is_map(mapping) do
    # Replace closing tags and self-closing tags first to avoid partial overlap issues
    # Keys like "/10", "/1", "10/", "1/"
    sorted_keys = 
      Map.keys(mapping) 
      |> Enum.sort_by(fn k -> 
        # Sort by numeric ID descending to avoid replacing [[10]] when looking for [[1]]
        id = k |> String.replace(~r/[^\d]/, "") |> String.to_integer()
        {-id, String.length(k)}
      end)

    Enum.reduce(sorted_keys, text, fn key, acc ->
      tag = Map.get(mapping, key)
      String.replace(acc, "[[#{key}]]", tag)
    end)
  end
end
