defmodule Nexlm.Providers.GroqTest do
  use ExUnit.Case, async: true
  alias Nexlm.Providers.Groq
  alias Nexlm.Error

  setup do
    original_config = Application.get_env(:nexlm, Groq)

    Application.put_env(:nexlm, Groq, api_key: "test_key")

    on_exit(fn ->
      case original_config do
        nil -> Application.delete_env(:nexlm, Groq)
        config -> Application.put_env(:nexlm, Groq, config)
      end
    end)

    :ok
  end

  describe "init/1" do
    test "initializes with valid config" do
      assert {:ok, config} = Groq.init(model: "mixtral-8x7b-32768")
      assert config.model == "mixtral-8x7b-32768"
      # 0.0 gets converted to 1e-8
      assert config.temperature == 1.0e-8
    end

    test "initializes with custom temperature" do
      assert {:ok, config} = Groq.init(model: "mixtral-8x7b-32768", temperature: 1.5)
      assert config.temperature == 1.5
    end

    test "fails with invalid config" do
      assert {:error, %Error{type: :configuration_error}} = Groq.init([])
    end
  end

  describe "validate_messages/1" do
    test "validates correct messages" do
      messages = [
        %{"role" => "user", "content" => "Hello"}
      ]

      assert {:ok, _} = Groq.validate_messages(messages)
    end

    test "validates tool messages" do
      messages = [
        %{"role" => "user", "content" => "What's the weather?"},
        %{
          "role" => "assistant",
          "content" => "",
          "tool_calls" => [
            %{
              "id" => "call_123",
              "name" => "get_weather",
              "arguments" => %{"location" => "London"}
            }
          ]
        },
        %{"role" => "tool", "tool_call_id" => "call_123", "content" => "sunny"}
      ]

      assert {:ok, _} = Groq.validate_messages(messages)
    end

    test "fails with invalid messages" do
      messages = [
        %{"role" => "invalid", "content" => "Hello"}
      ]

      assert {:error, %Error{type: :validation_error}} = Groq.validate_messages(messages)
    end
  end

  describe "format_request/2" do
    setup do
      {:ok, config} = Groq.init(model: "mixtral-8x7b-32768")
      %{config: config}
    end

    test "formats simple message", %{config: config} do
      messages = [
        %{role: "user", content: "Hello"}
      ]

      assert {:ok, request} = Groq.format_request(config, messages)
      assert request.model == "mixtral-8x7b-32768"
      assert [message] = request.messages
      assert message.role == "user"
      assert message.content == "Hello"
    end

    test "formats messages with text only", %{config: config} do
      messages = [
        %{
          role: "user",
          content: [
            %{type: "text", text: "Check this:"},
            %{type: "text", text: "Another text"}
          ]
        }
      ]

      assert {:ok, request} = Groq.format_request(config, messages)
      assert [message] = request.messages
      [first, second] = message.content
      assert first.type == "text"
      assert first.text == "Check this:"
      assert second.type == "text"
      assert second.text == "Another text"
    end
  end

  describe "parse_response/1" do
    test "parses simple response" do
      response = %{
        "role" => "assistant",
        "content" => "Hello"
      }

      assert {:ok, message} = Groq.parse_response(response)
      assert message.role == "assistant"
      assert message.content == "Hello"
    end

    test "parses tool call response" do
      response = %{
        "role" => "assistant",
        "content" => "",
        "tool_calls" => [
          %{
            "id" => "call_123",
            "function" => %{
              "name" => "get_weather",
              "arguments" => "{\"location\":\"London\"}"
            }
          }
        ]
      }

      assert {:ok, message} = Groq.parse_response(response)
      assert message.role == "assistant"
      assert [tool_call] = message.tool_calls
      assert tool_call.id == "call_123"
      assert tool_call.name == "get_weather"
      assert tool_call.arguments == %{"location" => "London"}
    end

    test "fails with invalid response" do
      response = %{
        "role" => "invalid",
        "content" => "Hello"
      }

      assert {:error, %Error{type: :provider_error}} = Groq.parse_response(response)
    end
  end
end
