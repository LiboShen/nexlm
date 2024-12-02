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
  end
end
