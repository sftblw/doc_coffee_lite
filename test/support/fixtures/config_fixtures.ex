defmodule DocCoffeeLite.ConfigFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `DocCoffeeLite.Config` context.
  """

  @doc """
  Generate a llm_config.
  """
  def llm_config_fixture(attrs \\ %{}) do
    {:ok, llm_config} =
      attrs
      |> Enum.into(%{
        active: true,
        api_key: "some api_key",
        base_url: "some base_url",
        fallback: true,
        model: "some model",
        name: "some name",
        provider: "some provider",
        settings: %{},
        tier: "some tier",
        usage_type: "some usage_type"
      })
      |> DocCoffeeLite.Config.create_llm_config()

    llm_config
  end
end
