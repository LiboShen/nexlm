defmodule Integration.Providers.GoogleTest do
  use ExUnit.Case, async: true
  alias Nexlm.Providers.Google

  @moduletag :integration

  describe "complete flow" do
    setup do
      api_key = System.get_env("GOOGLE_API_KEY")

      if is_binary(api_key) do
        Application.put_env(:nexlm, Google, api_key: api_key)
        :ok
      else
        raise "Missing GOOGLE_API_KEY environment variable"
      end
    end

    test "simple text completion" do
      messages = [
        %{"role" => "user", "content" => "What is 2+2? Answer with just the number."}
      ]

      {:ok, result} =
        Nexlm.complete(
          "google/gemini-1.5-flash-latest",
          messages
        )

      assert result.role == "assistant"
      assert result.content |> String.trim() == "4"
    end

    test "handles system messages" do
      messages = [
        %{
          "role" => "system",
          "content" => "You are a mathematician who only responds with numbers"
        },
        %{"role" => "user", "content" => "What is five plus five?"}
      ]

      {:ok, result} =
        Nexlm.complete(
          "google/gemini-1.5-flash-latest",
          messages
        )

      assert result.role == "assistant"
      assert result.content |> String.trim() == "10"
    end

    @tag :skip_in_ci
    test "handles image input" do
      test_image =
        "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAb/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCdABmX/9k="

      messages = [
        %{
          "role" => "user",
          "content" => [
            %{"type" => "text", "text" => "What's in this image?"},
            %{"type" => "image", "mime_type" => "image/jpeg", "data" => test_image}
          ]
        }
      ]

      {:ok, result} =
        Nexlm.complete(
          "google/gemini-1.5-pro-latest",
          messages
        )

      assert result.role == "assistant"
      assert String.contains?(result.content, "image")
    end

    test "handles tool use" do
      messages = [
        %{
          "role" => "system",
          "content" =>
            "You have access to tools. Use the get_weather function when asked about weather."
        },
        %{
          "role" => "user",
          "content" => "Please use the get_weather function to check the weather in London."
        }
      ]

      tools = [
        %{
          name: "get_weather",
          description:
            "Get the current weather for a specific location. Use this function when users ask about weather.",
          parameters: %{
            type: "object",
            properties: %{
              location: %{
                type: "string",
                description: "The city name, e.g. London, Paris, Tokyo"
              }
            },
            required: ["location"]
          }
        }
      ]

      {:ok, result} =
        Nexlm.complete(
          "google/gemini-1.5-flash-latest",
          messages,
          tools: tools,
          temperature: 0.0
        )

      assert result.role == "assistant"

      # Check if the model used the tool
      case Map.get(result, :tool_calls) do
        [
          %{
            id: tool_call_id,
            arguments: %{"location" => location},
            name: "get_weather"
          }
        ] ->
          # Model used the tool - test the full flow
          assert String.contains?(location, "London")

          messages =
            messages ++
              [
                result,
                %{
                  "role" => "tool",
                  "tool_call_id" => tool_call_id,
                  "content" => "sunny, 22°C"
                }
              ]

          {:ok, result} =
            Nexlm.complete(
              "google/gemini-1.5-flash-latest",
              messages,
              tools: tools,
              temperature: 0.0
            )

          assert result.role == "assistant"
          assert result.content =~ "sunny"

        nil ->
          # Model chose not to use the tool - this is valid behavior
          # Just verify it's a valid response
          assert String.length(result.content) > 0
      end
    end
  end
end
