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
  end
end
