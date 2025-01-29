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
      assert config.temperature == 1.0e-8  # 0.0 gets converted to 1e-8
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

    test "filters out image content", %{config: config} do
      messages = [
        %{
          role: "user",
          content: [
            %{type: "text", text: "Check this:"},
            %{type: "image", mime_type: "image/jpeg", data: "base64"}
          ]
        }
      ]

      assert {:ok, request} = Groq.format_request(config, messages)
      assert [message] = request.messages
      assert [text_content] = message.content
      assert text_content.type == "text"
      assert text_content.text == "Check this:"
    end
  end
end
