defmodule Integration.Providers.GroqTest do
  use ExUnit.Case, async: true
  alias Nexlm.Providers.Groq

  @moduletag :integration

  describe "complete flow" do
    setup do
      api_key = System.get_env("GROQ_API_KEY")
      Application.put_env(:nexlm, Groq, api_key: api_key)

      case Application.get_env(:nexlm, Groq) do
        [api_key: key] when is_binary(key) -> :ok
        _ -> raise "Missing Groq API key"
      end
    end

    test "simple text completion" do
      messages = [
        %{"role" => "user", "content" => "What is 2+2? Answer with just the number."}
      ]

      {:ok, result} = Nexlm.complete(
        "groq/gemma2-9b-it",
        messages
      )

      assert result.role == "assistant"
      assert String.contains?(result.content, "4")
    end

    test "handles system messages" do
      messages = [
        %{
          "role" => "system",
          "content" => "You are a mathematician who only responds with numbers"
        },
        %{"role" => "user", "content" => "What is five plus five?"}
      ]

      {:ok, result} = Nexlm.complete(
        "groq/gemma2-9b-it",
        messages
      )

      assert result.role == "assistant"
      assert String.contains?(result.content, "10")
    end

    test "handles temperature adjustment" do
      messages = [
        %{"role" => "user", "content" => "What is 2+2? Answer with just the number."}
      ]

      {:ok, result} = Nexlm.complete(
        "groq/gemma2-9b-it",
        messages,
        temperature: 0.0
      )

      assert result.role == "assistant"
      assert String.contains?(result.content, "4")
    end

    test "handles tool use" do
      messages = [
        %{"role" => "user", "content" => "What is the weather in London?"}
      ]

      tools = [
        %{
          name: "get_weather",
          description: "Get the weather for a location",
          parameters: %{
            type: "object",
            properties: %{
              location: %{
                type: "string",
                description: "The city and state, e.g. San Francisco, CA"
              }
            },
            required: ["location"]
          }
        }
      ]

      {:ok, result} = Nexlm.complete(
        "groq/gemma2-9b-it",
        messages,
        tools: tools
      )

      assert result.role == "assistant"

      assert [
               %{
                 id: tool_call_id,
                 arguments: %{"location" => "London"},
                 name: "get_weather"
               }
             ] = result.tool_calls

      # Test tool response handling
          messages =
        messages ++
          [
            result,
            %{
              "role" => "tool",
              "tool_call_id" => tool_call_id,
              "content" => "sunny"
            }
          ]

      {:ok, result} = Nexlm.complete(
        "groq/gemma2-9b-it",
        messages,
        tools: tools
      )

      assert result.role == "assistant"
      assert result.content =~ "sunny"
    end

    test "handles errors gracefully" do
      messages = [
        %{"role" => "user", "content" => "What is 2+2?"}
      ]

      # Test with invalid model
      assert {:error, error} = Nexlm.complete(
        "groq/invalid-model",
        messages
      )

      assert error.type == :provider_error
      assert error.provider == :groq

      # Test with invalid API key
      original_key = Application.get_env(:nexlm, Groq)[:api_key]
      Application.put_env(:nexlm, Groq, api_key: "invalid_key")

      assert {:error, error} = Nexlm.complete(
        "groq/gemma2-9b-it",
        messages
      )

      assert error.type == :authentication_error
      assert error.provider == :groq

      # Restore original key
      Application.put_env(:nexlm, Groq, api_key: original_key)
    end
  end
end
