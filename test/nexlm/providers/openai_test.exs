defmodule Nexlm.Providers.OpenAITest do
  use ExUnit.Case, async: true
  alias Nexlm.Providers.OpenAI
  alias Nexlm.Error

  setup do
    original_config = Application.get_env(:nexlm, OpenAI)

    Application.put_env(:nexlm, OpenAI, api_key: "test_key")

    on_exit(fn ->
      case original_config do
        nil -> Application.delete_env(:nexlm, OpenAI)
        config -> Application.put_env(:nexlm, OpenAI, config)
      end
    end)

    :ok
  end

  describe "init/1" do
    test "initializes with valid config" do
      assert {:ok, config} = OpenAI.init(model: "gpt-4")
      assert config.model == "gpt-4"
      assert config.temperature == 0.0
    end

    test "fails with invalid config" do
      assert {:error, %Error{type: :configuration_error}} = OpenAI.init([])
    end
  end

  describe "validate_messages/1" do
    test "validates correct messages" do
      messages = [
        %{"role" => "user", "content" => "Hello"}
      ]

      assert {:ok, _} = OpenAI.validate_messages(messages)
    end

    test "fails with invalid messages" do
      messages = [
        %{"role" => "invalid", "content" => "Hello"}
      ]

      assert {:error, %Error{type: :validation_error}} = OpenAI.validate_messages(messages)
    end
  end

  describe "format_request/2" do
    setup do
      {:ok, config} = OpenAI.init(model: "gpt-4")
      %{config: config}
    end

    test "formats simple message", %{config: config} do
      messages = [
        %{role: "user", content: "Hello"}
      ]

      assert {:ok, request} = OpenAI.format_request(config, messages)
      assert request.model == "gpt-4"
      assert [message] = request.messages
      assert message.role == "user"
      assert message.content == "Hello"
    end

    test "formats messages with images", %{config: config} do
      messages = [
        %{
          role: "user",
          content: [
            %{type: "text", text: "Check this:"},
            %{type: "image", mime_type: "image/jpeg", data: "base64"}
          ]
        }
      ]

      assert {:ok, request} = OpenAI.format_request(config, messages)
      assert [message] = request.messages
      [text_content, image_content] = message.content
      assert text_content.type == "text"
      assert image_content.type == "image_url"
      assert image_content.image_url.url =~ "data:image/jpeg;base64,base64"
    end

    test "formats request with tools", %{config: config} do
      tools = [
        %{
          name: "get_weather",
          description: "Get the weather for a location",
          parameters: %{
            type: "object",
            properties: %{
              location: %{type: "string", description: "The city"}
            },
            required: ["location"]
          }
        }
      ]

      config_with_tools = %{config | tools: tools}
      messages = [%{role: "user", content: "What's the weather in SF?"}]

      assert {:ok, request} = OpenAI.format_request(config_with_tools, messages)
      assert [tool] = request.tools
      assert tool.type == "function"
      assert tool.function.name == "get_weather"
      assert tool.function.description == "Get the weather for a location"
      assert tool.function.parameters.type == "object"
    end

    test "formats messages with tool calls", %{config: config} do
      messages = [
        %{
          role: "assistant",
          content: "I'll check the weather for you.",
          tool_calls: [
            %{
              id: "call_12345",
              name: "get_weather",
              arguments: %{"location" => "San Francisco"}
            }
          ]
        }
      ]

      assert {:ok, request} = OpenAI.format_request(config, messages)
      [message] = request.messages
      assert message.role == "assistant"
      assert message.content == "I'll check the weather for you."
      [tool_call] = message.tool_calls
      assert tool_call.id == "call_12345"
      assert tool_call.type == "function"
      assert tool_call.function.name == "get_weather"
      assert tool_call.function.arguments == "{\"location\":\"San Francisco\"}"
    end

    test "formats tool result messages", %{config: config} do
      messages = [
        %{
          role: "tool",
          tool_call_id: "call_12345",
          content: "Sunny, 75°F"
        }
      ]

      assert {:ok, request} = OpenAI.format_request(config, messages)
      [message] = request.messages
      assert message.role == "tool"
      assert message.tool_call_id == "call_12345"
      assert message.content == "Sunny, 75°F"
    end

    test "uses max_tokens for traditional models", %{config: config} do
      messages = [%{role: "user", content: "Hello"}]

      assert {:ok, request} = OpenAI.format_request(config, messages)
      assert Map.has_key?(request, :max_tokens)
      assert request.max_tokens == 4000
      refute Map.has_key?(request, :max_completion_tokens)
    end

    test "uses max_completion_tokens for GPT-5 model" do
      {:ok, config} = OpenAI.init(model: "openai/gpt-5")
      messages = [%{role: "user", content: "Hello"}]

      assert {:ok, request} = OpenAI.format_request(config, messages)
      assert Map.has_key?(request, :max_completion_tokens)
      assert request.max_completion_tokens == 4000
      refute Map.has_key?(request, :max_tokens)
    end

    test "uses max_completion_tokens for o1 model" do
      {:ok, config} = OpenAI.init(model: "openai/o1")
      messages = [%{role: "user", content: "Hello"}]

      assert {:ok, request} = OpenAI.format_request(config, messages)
      assert Map.has_key?(request, :max_completion_tokens)
      assert request.max_completion_tokens == 4000
      refute Map.has_key?(request, :max_tokens)
    end

    test "includes temperature for traditional models", %{config: config} do
      messages = [%{role: "user", content: "Hello"}]

      assert {:ok, request} = OpenAI.format_request(config, messages)
      assert Map.has_key?(request, :temperature)
      assert request.temperature == 0.0
    end

    test "excludes temperature for GPT-5 model" do
      {:ok, config} = OpenAI.init(model: "openai/gpt-5")
      messages = [%{role: "user", content: "Hello"}]

      assert {:ok, request} = OpenAI.format_request(config, messages)
      refute Map.has_key?(request, :temperature)
    end

    test "excludes temperature for o1 model" do
      {:ok, config} = OpenAI.init(model: "openai/o1-preview")
      messages = [%{role: "user", content: "Hello"}]

      assert {:ok, request} = OpenAI.format_request(config, messages)
      refute Map.has_key?(request, :temperature)
    end
  end

  describe "parse_response/1" do
    test "parses simple response" do
      response = %{
        "role" => "assistant",
        "content" => "Hello there"
      }

      assert {:ok, parsed} = OpenAI.parse_response(response)
      assert parsed.role == "assistant"
      assert parsed.content == "Hello there"
    end

    test "parses response with tool calls" do
      response = %{
        "role" => "assistant",
        "content" => "I'll check the weather for you.",
        "tool_calls" => [
          %{
            "id" => "call_12345",
            "type" => "function",
            "function" => %{
              "name" => "get_weather",
              "arguments" => "{\"location\":\"San Francisco\"}"
            }
          }
        ]
      }

      assert {:ok, parsed} = OpenAI.parse_response(response)
      assert parsed.role == "assistant"
      assert parsed.content == "I'll check the weather for you."
      assert [tool_call] = parsed.tool_calls
      assert tool_call.id == "call_12345"
      assert tool_call.name == "get_weather"
      assert tool_call.arguments == %{"location" => "San Francisco"}
    end

    test "parses response with multiple tool calls" do
      response = %{
        "role" => "assistant",
        "content" => "I'll check weather for both cities.",
        "tool_calls" => [
          %{
            "id" => "call_12345",
            "type" => "function",
            "function" => %{
              "name" => "get_weather",
              "arguments" => "{\"location\":\"San Francisco\"}"
            }
          },
          %{
            "id" => "call_67890",
            "type" => "function",
            "function" => %{
              "name" => "get_weather",
              "arguments" => "{\"location\":\"New York\"}"
            }
          }
        ]
      }

      assert {:ok, parsed} = OpenAI.parse_response(response)
      assert parsed.role == "assistant"
      assert parsed.content == "I'll check weather for both cities."
      assert length(parsed.tool_calls) == 2
      assert Enum.all?(parsed.tool_calls, &(&1.name == "get_weather"))
    end

    test "parses response with tool call but no content" do
      response = %{
        "role" => "assistant",
        "content" => nil,
        "tool_calls" => [
          %{
            "id" => "call_12345",
            "type" => "function",
            "function" => %{
              "name" => "get_weather",
              "arguments" => "{\"location\":\"San Francisco\"}"
            }
          }
        ]
      }

      assert {:ok, parsed} = OpenAI.parse_response(response)
      assert parsed.role == "assistant"
      assert parsed.content == ""
      assert [tool_call] = parsed.tool_calls
      assert tool_call.name == "get_weather"
    end
  end
end
