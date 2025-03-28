defmodule Nexlm.RegistryTest do
  use ExUnit.Case, async: true
  alias Nexlm.Registry

  describe "get_provider/1" do
    test "returns provider module for valid model" do
      assert {:ok, Nexlm.Providers.Anthropic} = Registry.get_provider("anthropic/claude-3")
      assert {:ok, Nexlm.Providers.OpenAI} = Registry.get_provider("openai/gpt-4")
      assert {:ok, Nexlm.Providers.Google} = Registry.get_provider("google/gemini-pro")
    end

    test "returns error for unknown provider" do
      assert {:error, :unknown_provider} = Registry.get_provider("unknown/model")
    end

    test "returns error for invalid model format" do
      assert {:error, :invalid_model_format} = Registry.get_provider("invalid-format")
    end
  end

  describe "list_providers/0" do
    test "returns list of available providers" do
      providers = Registry.list_providers()
      assert "anthropic" in providers
      assert "openai" in providers
      assert "google" in providers
    end
  end
end
