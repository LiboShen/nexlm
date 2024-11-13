defmodule Nexlm.ErrorTest do
  use ExUnit.Case, async: true
  alias Nexlm.Error

  describe "new/4" do
    test "creates error with all fields" do
      error = Error.new(:validation_error, "test message", :test_provider, %{key: "value"})
      assert error.type == :validation_error
      assert error.message == "test message"
      assert error.provider == :test_provider
      assert error.details == %{key: "value"}
    end

    test "creates error with default empty details" do
      error = Error.new(:validation_error, "test message", :test_provider)
      assert error.details == %{}
    end
  end

  describe "message/1" do
    test "formats error message correctly" do
      error = Error.new(:validation_error, "test message", :test_provider)
      assert Error.message(error) == "test_provider: test message"
    end
  end
end
