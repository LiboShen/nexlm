defmodule NexlmTest do
  use ExUnit.Case
  doctest Nexlm, import: true

  # Mock provider module
  defmodule TestProvider do
    @behaviour Nexlm.Behaviour

    @impl true
    def init(_opts), do: {:ok, %{}}

    @impl true
    def validate_messages(messages), do: {:ok, messages}

    @impl true
    def format_request(_config, _messages), do: {:ok, %{}}

    @impl true
    def call(_config, _request), do: {:ok, %{}}

    @impl true
    def parse_response(_response), do: {:ok, %{role: "assistant", content: "mock response"}}
  end

  # Mock registry module
  defmodule TestRegistry do
    def get_provider("test/model"), do: {:ok, NexlmTest.TestProvider}
    def get_provider(_), do: {:error, :unknown_provider}
  end

  setup_all do
    original_registry = Application.get_env(:nexlm, :registry_module)
    Application.put_env(:nexlm, :registry_module, NexlmTest.TestRegistry)

    on_exit(fn ->
      case original_registry do
        nil -> Application.delete_env(:nexlm, :registry_module)
        module -> Application.put_env(:nexlm, :registry_module, module)
      end
    end)

    :ok
  end

  describe "complete/3" do
    test "successful completion" do
      messages = [%{"role" => "user", "content" => "test"}]
      assert {:ok, response} = Nexlm.complete("test/model", messages)
      assert response.role == "assistant"
      assert response.content == "mock response"
    end

    test "validates model format" do
      messages = [%{"role" => "user", "content" => "test"}]
      assert {:error, :unknown_provider} = Nexlm.complete("invalid", messages)
    end

    test "forwards options to service" do
      messages = [%{"role" => "user", "content" => "test"}]
      opts = [temperature: 0.7, max_tokens: 100]
      assert {:ok, _} = Nexlm.complete("test/model", messages, opts)
    end

    test "validates input types" do
      assert_raise FunctionClauseError, fn ->
        Nexlm.complete(123, [])
      end

      assert_raise FunctionClauseError, fn ->
        Nexlm.complete("test/model", "not a list")
      end

      assert_raise FunctionClauseError, fn ->
        Nexlm.complete("test/model", [], "not keywords")
      end
    end
  end
end