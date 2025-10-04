defmodule Nexlm.Providers.AnthropicTest do
  use ExUnit.Case, async: true
  alias Nexlm.Providers.Anthropic
  alias Nexlm.Error

  setup do
    original_config = Application.get_env(:nexlm, Anthropic)
    original_http_client = Application.get_env(:nexlm, :http_client)

    Application.put_env(:nexlm, Anthropic, api_key: "test_key")
    Application.put_env(:nexlm, :http_client, Test.Support.HTTPStub)
    Test.Support.HTTPStub.reset()

    on_exit(fn ->
      case original_config do
        nil -> Application.delete_env(:nexlm, Anthropic)
        config -> Application.put_env(:nexlm, Anthropic, config)
      end

      if original_http_client do
        Application.put_env(:nexlm, :http_client, original_http_client)
      else
        Application.delete_env(:nexlm, :http_client)
      end
    end)

    :ok
  end

  describe "init/1" do
    test "initializes with valid config" do
      assert {:ok, config} = Anthropic.init(model: "claude-3")
      assert config.model == "claude-3"
      assert config.max_tokens == 4000
    end

    test "fails with invalid config" do
      assert {:error, %Error{type: :configuration_error}} = Anthropic.init([])
    end
  end

  describe "validate_messages/1" do
    test "validates correct messages" do
      messages = [
        %{"role" => "user", "content" => "Hello"}
      ]

      assert {:ok, _} = Anthropic.validate_messages(messages)
    end

    test "fails with invalid messages" do
      messages = [
        %{"role" => "invalid", "content" => "Hello"}
      ]

      assert {:error, %Error{type: :validation_error}} = Anthropic.validate_messages(messages)
    end
  end

  describe "format_request/2" do
    setup do
      {:ok, config} = Anthropic.init(model: "claude-3")
      %{config: config}
    end

    test "formats simple message", %{config: config} do
      messages = [
        %{role: "user", content: "Hello"}
      ]

      assert {:ok, request} = Anthropic.format_request(config, messages)
      assert request.model == "claude-3"
      assert [message] = request.messages
      assert message.role == "user"
      assert [%{type: "text", text: "Hello"}] = message.content
    end

    test "handles system message", %{config: config} do
      messages = [
        %{role: "system", content: "Be helpful"},
        %{role: "user", content: "Hello"}
      ]

      assert {:ok, request} = Anthropic.format_request(config, messages)
      assert request.system == "Be helpful"
      assert [message] = request.messages
      assert message.role == "user"
    end

    test "formats messages with images", %{config: config} do
      messages = [
        %{
          role: "user",
          content: [
            %{type: "text", text: "Check this:"},
            %{type: "image", mime_type: "image/jpeg", data: "base64", cache: true}
          ]
        }
      ]

      assert {:ok, request} = Anthropic.format_request(config, messages)
      assert [message] = request.messages
      assert length(message.content) == 2
      assert %{cache_control: %{type: "ephemeral"}} = Enum.at(message.content, 1)
    end
  end

  describe "call/2" do
    test "includes status in provider error details" do
      Test.Support.HTTPStub.put(fn _url, _opts ->
        {:ok,
         %{
           status: 503,
           headers: [],
           body: %{"error" => %{"message" => "service unavailable"}}
         }}
      end)

      {:ok, config} = Anthropic.init(model: "claude-3")

      assert {:error, %Error{type: :provider_error, details: %{status: 503}}} =
               Anthropic.call(config, %{})
    end
  end
end
