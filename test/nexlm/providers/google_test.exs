defmodule Nexlm.Providers.GoogleTest do
  use ExUnit.Case, async: true
  alias Nexlm.Providers.Google
  alias Nexlm.Error

  setup do
    original_config = Application.get_env(:nexlm, Google)

    Application.put_env(:nexlm, Google, api_key: "test_key")

    on_exit(fn ->
      case original_config do
        nil -> Application.delete_env(:nexlm, Google)
        config -> Application.put_env(:nexlm, Google, config)
      end
    end)

    :ok
  end

  describe "init/1" do
    test "initializes with valid config" do
      assert {:ok, config} = Google.init(model: "gemini-1.5-flash-latest")
      assert config.model == "gemini-1.5-flash-latest"
      assert config.temperature == 0.0
      assert config.top_p == 0.95
    end

    test "fails with invalid config" do
      assert {:error, %Error{type: :configuration_error}} = Google.init([])
    end
  end

  describe "validate_messages/1" do
    test "validates correct messages" do
      messages = [
        %{"role" => "user", "content" => "Hello"}
      ]

      assert {:ok, _} = Google.validate_messages(messages)
    end

    test "fails with invalid messages" do
      messages = [
        %{"role" => "invalid", "content" => "Hello"}
      ]

      assert {:error, %Error{type: :validation_error}} = Google.validate_messages(messages)
    end
  end

  describe "format_request/2" do
    setup do
      {:ok, config} = Google.init(model: "gemini-1.5-flash-latest")
      %{config: config}
    end

    test "formats simple message", %{config: config} do
      messages = [
        %{role: "user", content: "Hello"}
      ]

      assert {:ok, request} = Google.format_request(config, messages)
      assert [content] = request.contents
      assert content.role == "user"
      assert [%{text: "Hello"}] = content.parts
    end

    test "handles system message", %{config: config} do
      messages = [
        %{role: "system", content: "Be helpful"},
        %{role: "user", content: "Hello"}
      ]

      assert {:ok, request} = Google.format_request(config, messages)
      assert request.systemInstruction == %{parts: [%{text: "Be helpful"}]}
      assert length(request.contents) == 1
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

      assert {:ok, request} = Google.format_request(config, messages)
      [content] = request.contents
      [text_part, image_part] = content.parts
      assert text_part.text == "Check this:"
      assert image_part.inlineData.mimeType == "image/jpeg"
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

      assert {:ok, request} = Google.format_request(config_with_tools, messages)
      assert %{functionDeclarations: [tool]} = request.tools
      assert tool.name == "get_weather"
      assert tool.description == "Get the weather for a location"
      assert tool.parameters.type == "object"
    end

    test "formats messages with tool calls", %{config: config} do
      messages = [
        %{
          role: "assistant",
          content: "I'll check the weather for you.",
          tool_calls: [
            %{
              id: "call_get_weather_12345678",
              name: "get_weather",
              arguments: %{"location" => "San Francisco"}
            }
          ]
        }
      ]

      assert {:ok, request} = Google.format_request(config, messages)
      [content] = request.contents
      assert content.role == "model"
      assert length(content.parts) == 2

      [text_part, function_call_part] = content.parts
      assert text_part.text == "I'll check the weather for you."
      assert function_call_part.functionCall.name == "get_weather"
      assert function_call_part.functionCall.args == %{"location" => "San Francisco"}
    end

    test "formats tool result messages", %{config: config} do
      messages = [
        %{
          role: "tool",
          tool_call_id: "call_get_weather_12345678",
          content: "Sunny, 75°F"
        }
      ]

      assert {:ok, request} = Google.format_request(config, messages)
      [content] = request.contents
      assert content.role == "function"
      [function_response] = content.parts
      assert function_response.functionResponse.name == "get_weather"
      assert function_response.functionResponse.response.result == "Sunny, 75°F"
    end
  end

  describe "parse_response/1" do
    test "converts model role to assistant" do
      response = %{
        "role" => "model",
        "parts" => [%{"text" => "Hello there"}]
      }

      assert {:ok, parsed} = Google.parse_response(response)
      assert parsed.role == "assistant"
      assert parsed.content == "Hello there"
    end

    test "parses response with function calls" do
      response = %{
        "role" => "model",
        "parts" => [
          %{"text" => "I'll check the weather for you."},
          %{
            "functionCall" => %{
              "name" => "get_weather",
              "args" => %{"location" => "San Francisco"}
            }
          }
        ]
      }

      assert {:ok, parsed} = Google.parse_response(response)
      assert parsed.role == "assistant"
      assert parsed.content == "I'll check the weather for you."
      assert [tool_call] = parsed.tool_calls
      assert tool_call.name == "get_weather"
      assert tool_call.arguments == %{"location" => "San Francisco"}
      assert String.starts_with?(tool_call.id, "call_get_weather_")
    end

    test "parses response with multiple function calls" do
      response = %{
        "role" => "model",
        "parts" => [
          %{"text" => "I'll check both locations."},
          %{
            "functionCall" => %{
              "name" => "get_weather",
              "args" => %{"location" => "San Francisco"}
            }
          },
          %{
            "functionCall" => %{
              "name" => "get_weather",
              "args" => %{"location" => "New York"}
            }
          }
        ]
      }

      assert {:ok, parsed} = Google.parse_response(response)
      assert parsed.role == "assistant"
      assert parsed.content == "I'll check both locations."
      assert length(parsed.tool_calls) == 2
      assert Enum.all?(parsed.tool_calls, &(&1.name == "get_weather"))
    end

    test "parses response with function call but no text" do
      response = %{
        "role" => "model",
        "parts" => [
          %{
            "functionCall" => %{
              "name" => "get_weather",
              "args" => %{"location" => "San Francisco"}
            }
          }
        ]
      }

      assert {:ok, parsed} = Google.parse_response(response)
      assert parsed.role == "assistant"
      assert parsed.content == ""
      assert [tool_call] = parsed.tool_calls
      assert tool_call.name == "get_weather"
    end
  end
end
