defmodule DocCoffeeLite.ConfigTest do
  use DocCoffeeLite.DataCase

  alias DocCoffeeLite.Config

  describe "llm_configs" do
    alias DocCoffeeLite.Config.LlmConfig

    import DocCoffeeLite.ConfigFixtures

    @invalid_attrs %{
      active: nil,
      name: nil,
      fallback: nil,
      api_key: nil,
      provider: nil,
      usage_type: nil,
      tier: nil,
      model: nil,
      base_url: nil,
      settings: nil
    }

    test "list_llm_configs/0 returns all llm_configs" do
      llm_config = llm_config_fixture()
      assert Config.list_llm_configs() == [llm_config]
    end

    test "get_llm_config!/1 returns the llm_config with given id" do
      llm_config = llm_config_fixture()
      assert Config.get_llm_config!(llm_config.id) == llm_config
    end

    test "create_llm_config/1 with valid data creates a llm_config" do
      valid_attrs = %{
        active: true,
        name: "some name",
        fallback: true,
        api_key: "some api_key",
        provider: "some provider",
        usage_type: "some usage_type",
        tier: "some tier",
        model: "some model",
        base_url: "some base_url",
        settings: %{}
      }

      assert {:ok, %LlmConfig{} = llm_config} = Config.create_llm_config(valid_attrs)
      assert llm_config.active == true
      assert llm_config.name == "some name"
      assert llm_config.fallback == true
      assert llm_config.api_key == "some api_key"
      assert llm_config.provider == "some provider"
      assert llm_config.usage_type == "some usage_type"
      assert llm_config.tier == "some tier"
      assert llm_config.model == "some model"
      assert llm_config.base_url == "some base_url"
      assert llm_config.settings == %{}
    end

    test "create_llm_config/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Config.create_llm_config(@invalid_attrs)
    end

    test "update_llm_config/2 with valid data updates the llm_config" do
      llm_config = llm_config_fixture()

      update_attrs = %{
        active: false,
        name: "some updated name",
        fallback: false,
        api_key: "some updated api_key",
        provider: "some updated provider",
        usage_type: "some updated usage_type",
        tier: "some updated tier",
        model: "some updated model",
        base_url: "some updated base_url",
        settings: %{}
      }

      assert {:ok, %LlmConfig{} = llm_config} = Config.update_llm_config(llm_config, update_attrs)
      assert llm_config.active == false
      assert llm_config.name == "some updated name"
      assert llm_config.fallback == false
      assert llm_config.api_key == "some updated api_key"
      assert llm_config.provider == "some updated provider"
      assert llm_config.usage_type == "some updated usage_type"
      assert llm_config.tier == "some updated tier"
      assert llm_config.model == "some updated model"
      assert llm_config.base_url == "some updated base_url"
      assert llm_config.settings == %{}
    end

    test "update_llm_config/2 with invalid data returns error changeset" do
      llm_config = llm_config_fixture()
      assert {:error, %Ecto.Changeset{}} = Config.update_llm_config(llm_config, @invalid_attrs)
      assert llm_config == Config.get_llm_config!(llm_config.id)
    end

    test "delete_llm_config/1 deletes the llm_config" do
      llm_config = llm_config_fixture()
      assert {:ok, %LlmConfig{}} = Config.delete_llm_config(llm_config)
      assert_raise Ecto.NoResultsError, fn -> Config.get_llm_config!(llm_config.id) end
    end

    test "change_llm_config/1 returns a llm_config changeset" do
      llm_config = llm_config_fixture()
      assert %Ecto.Changeset{} = Config.change_llm_config(llm_config)
    end
  end
end
