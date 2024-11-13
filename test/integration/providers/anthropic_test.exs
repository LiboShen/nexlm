defmodule Integration.Providers.AnthropicTest do
  use ExUnit.Case, async: true
  alias Nexlm.Providers.Anthropic

  @moduletag :integration

  describe "complete flow" do
    setup do
      key = System.get_env("ANTHROPIC_API_KEY")
      if is_binary(key) do
        Application.put_env(:nexlm, Anthropic, api_key: key)
        :ok
      else
        raise "Missing ANTHROPIC_API_KEY environment variable"
      end
    end

    test "simple text completion" do
      messages = [
        %{"role" => "user", "content" => "What is 2+2? Answer with just the number."}
      ]

      assert {:ok, config} = Anthropic.init(model: "anthropic/claude-3-haiku-20240307")
      assert {:ok, validated} = Anthropic.validate_messages(messages)
      assert {:ok, request} = Anthropic.format_request(config, validated)
      assert {:ok, response} = Anthropic.call(config, request)
      assert {:ok, result} = Anthropic.parse_response(response)

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

      assert {:ok, config} = Anthropic.init(model: "anthropic/claude-3-haiku-20240307")
      assert {:ok, validated} = Anthropic.validate_messages(messages)
      assert {:ok, request} = Anthropic.format_request(config, validated)
      assert {:ok, response} = Anthropic.call(config, request)
      assert {:ok, result} = Anthropic.parse_response(response)

      assert result.role == "assistant"
      assert result.content == "10"
    end

    @tag :skip_in_ci
    test "handles image input" do
      # Base64 encoded small test image
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

      assert {:ok, config} = Anthropic.init(model: "anthropic/claude-3-haiku-20240307")
      assert {:ok, validated} = Anthropic.validate_messages(messages)
      assert {:ok, request} = Anthropic.format_request(config, validated)
      assert {:ok, response} = Anthropic.call(config, request)
      assert {:ok, result} = Anthropic.parse_response(response)

      assert result.role == "assistant"
      assert String.contains?(result.content, "image")
    end
  end
end
