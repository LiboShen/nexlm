defmodule Nexlm.ConfigTest do
  use ExUnit.Case, async: true
  alias Nexlm.Config

  # Helper function to convert changeset errors into a map of messages.
  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  describe "new/1" do
    test "creates valid config with minimal options" do
      assert {:ok, config} = Config.new(model: "test/model")
      assert config.model == "test/model"
      # default value
      assert config.temperature == 0.0
    end

    test "validates required fields" do
      assert {:error, changeset} = Config.new([])
      assert "can't be blank" in errors_on(changeset).model
    end

    test "validates temperature range" do
      assert {:error, changeset} = Config.new(model: "test/model", temperature: -1.0)
      assert "must be greater than or equal to 0" in errors_on(changeset).temperature
    end

    test "validates positive max_tokens" do
      assert {:error, changeset} = Config.new(model: "test/model", max_tokens: 0)
      assert "must be greater than 0" in errors_on(changeset).max_tokens
    end
  end
end
