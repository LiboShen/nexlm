defmodule Integration.Providers.OpenAITest do
  use ExUnit.Case, async: true
  alias Nexlm.Providers.OpenAI

  @moduletag :integration

  describe "complete flow" do
    setup do
      api_key = System.get_env("OPENAI_API_KEY")
      Application.put_env(:nexlm, OpenAI, api_key: api_key)

      case Application.get_env(:nexlm, OpenAI) do
        [api_key: key] when is_binary(key) -> :ok
        _ -> raise "Missing OpenAI API key"
      end
    end

    test "simple text completion" do
      messages = [
        %{"role" => "user", "content" => "What is 2+2? Answer with just the number."}
      ]

      assert {:ok, config} = OpenAI.init(model: "openai/gpt-4")
      assert {:ok, validated} = OpenAI.validate_messages(messages)
      assert {:ok, request} = OpenAI.format_request(config, validated)
      assert {:ok, response} = OpenAI.call(config, request)
      assert {:ok, result} = OpenAI.parse_response(response)

      assert result.role == "assistant"
      assert result.content == "4"
    end

    test "handles system messages" do
      messages = [
        %{
          "role" => "system",
          "content" => "You are a mathematician who only responds with numbers"
        },
        %{"role" => "user", "content" => "What is five plus five?"}
      ]

      assert {:ok, config} = OpenAI.init(model: "openai/gpt-4")
      assert {:ok, validated} = OpenAI.validate_messages(messages)
      assert {:ok, request} = OpenAI.format_request(config, validated)
      assert {:ok, response} = OpenAI.call(config, request)
      assert {:ok, result} = OpenAI.parse_response(response)

      assert result.role == "assistant"
      assert result.content == "10"
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

      assert {:ok, config} = OpenAI.init(model: "openai/gpt-4o-mini")
      assert {:ok, validated} = OpenAI.validate_messages(messages)
      assert {:ok, request} = OpenAI.format_request(config, validated)
      assert {:ok, response} = OpenAI.call(config, request)
      assert {:ok, result} = OpenAI.parse_response(response)

      assert result.role == "assistant"
      assert String.contains?(result.content, "image")
    end
  end
end
