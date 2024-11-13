defmodule Nexlm.MessageTest do
  use ExUnit.Case, async: true
  alias Nexlm.Message

  describe "validate_message/1" do
    test "validates simple text message with string keys" do
      message = %{
        "role" => "user",
        "content" => "Hello, world!"
      }

      assert {:ok, validated} = Message.validate_message(message)
      assert validated.role == "user"
      assert validated.content == "Hello, world!"
    end

    test "validates complex content message with string keys" do
      message = %{
        "role" => "user",
        "content" => [
          %{
            "type" => "text",
            "text" => "Check this image:"
          },
          %{
            "type" => "image",
            "mime_type" => "image/jpeg",
            "data" => "base64data",
            "cache" => true
          }
        ]
      }

      assert {:ok, validated} = Message.validate_message(message)
      assert length(validated.content) == 2
    end

    test "rejects invalid role" do
      message = %{
        "role" => "invalid",
        "content" => "test"
      }

      assert {:error, error} = Message.validate_message(message)
      assert error.type == :validation_error
    end

    test "rejects invalid content format" do
      message = %{
        "role" => "user",
        "content" => [%{"type" => "invalid"}]
      }

      assert {:error, error} = Message.validate_message(message)
      assert error.type == :validation_error
    end

    test "handles invalid message format" do
      assert {:error, error} = Message.validate_message("not a map")
      assert error.type == :validation_error
      assert error.message == "Message must be a map"
    end
  end

  describe "validate_messages/1" do
    test "validates list of valid messages with string keys" do
      messages = [
        %{"role" => "user", "content" => "Hello"},
        %{"role" => "assistant", "content" => "Hi there"}
      ]

      assert {:ok, validated} = Message.validate_messages(messages)
      assert length(validated) == 2
    end

    test "fails on first invalid message" do
      messages = [
        %{"role" => "user", "content" => "Hello"},
        %{"role" => "invalid", "content" => "Bad role"},
        %{"role" => "assistant", "content" => "Won't get here"}
      ]

      assert {:error, error} = Message.validate_messages(messages)
      assert error.type == :validation_error
    end

    test "rejects non-list input" do
      assert {:error, error} = Message.validate_messages("not a list")
      assert error.type == :validation_error
      assert error.message == "Messages must be a list"
    end
  end
end
