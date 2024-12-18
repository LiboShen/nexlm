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

      assert {:ok, config} = Google.init(model: "gemini-1.5-flash-latest")
      assert {:ok, validated} = Google.validate_messages(messages)
      assert {:ok, request} = Google.format_request(config, validated)
      assert {:ok, response} = Google.call(config, request)
      assert {:ok, result} = Google.parse_response(response)

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

      assert {:ok, config} = Google.init(model: "gemini-1.5-flash-latest")
      assert {:ok, validated} = Google.validate_messages(messages)
      assert {:ok, request} = Google.format_request(config, validated)
      assert {:ok, response} = Google.call(config, request)
      assert {:ok, result} = Google.parse_response(response)

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

      assert {:ok, config} = Google.init(model: "gemini-1.5-pro-latest")
      assert {:ok, validated} = Google.validate_messages(messages)
      assert {:ok, request} = Google.format_request(config, validated)
      assert {:ok, response} = Google.call(config, request)
      assert {:ok, result} = Google.parse_response(response)

      assert result.role == "assistant"
      assert String.contains?(result.content, "image")
    end
  end
end
