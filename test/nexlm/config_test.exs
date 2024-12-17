defmodule Nexlm.ConfigTest do
  use ExUnit.Case, async: true
  alias Nexlm.Config

  describe "new/1" do
    test "creates valid config with minimal options" do
      assert {:ok, config} = Config.new(model: "test/model")
      assert config.model == "test/model"
      # default value
      assert config.temperature == 0.0
    end

    test "validates required fields" do
      assert {:error,
              %Elixact.Error{code: :required, message: "field is required", path: [:model]}} =
               Config.new([])
    end

    test "validates temperature range" do
      assert {:error,
              %Elixact.Error{path: [:temperature], code: :gteq, message: "failed gteq constraint"}} =
               Config.new(model: "test/model", temperature: -1.0)
    end

    test "validates positive max_tokens" do
      assert {:error,
              %Elixact.Error{path: [:max_tokens], code: :gt, message: "failed gt constraint"}} =
               Config.new(model: "test/model", max_tokens: 0)
    end
  end
end
