defmodule Nexlm.ServiceTest do
  use ExUnit.Case, async: true
  alias Nexlm.{Service, Config}

  # Mock provider for testing
  defmodule MockProvider do
    @behaviour Nexlm.Behaviour

    @impl true
    def init(opts), do: Config.new(opts)

    @impl true
    def validate_messages(messages), do: {:ok, messages}

    @impl true
    def format_request(_config, messages), do: {:ok, %{messages: messages}}

    @impl true
    def call(_config, _request) do
      {:ok,
       %{
         role: "assistant",
         content: "Mock response"
       }}
    end

    @impl true
    def parse_response(response), do: {:ok, response}
  end

  # Override the Registry.get_provider/1 function for testing
  defmodule TestRegistry do
    def get_provider("mock/test-model"), do: {:ok, MockProvider}
    def get_provider(_), do: {:error, :unknown_provider}
  end

  setup do
    # Replace the real Registry with our test version
    original_registry =
      Application.get_env(:nexlm, :registry_module, Nexlm.Registry)

    Application.put_env(:nexlm, :registry_module, TestRegistry)

    on_exit(fn ->
      Application.put_env(:nexlm, :registry_module, original_registry)
    end)

    :ok
  end

  describe "call/3" do
    test "successfully processes valid request" do
      messages = [
        %{"role" => "user", "content" => "Hello"}
      ]

      assert {:ok, response} = Service.call("mock/test-model", messages)
      assert response.role == "assistant"
      assert response.content == "Mock response"
    end

    test "fails with invalid model" do
      assert {:error, :unknown_provider} = Service.call("invalid/model", [])
    end

    test "fails with invalid messages" do
      messages = [
        %{"role" => "invalid", "content" => "Bad role"}
      ]

      assert {:error, %{type: :validation_error}} = Service.call("mock/test-model", messages)
    end
  end
end
