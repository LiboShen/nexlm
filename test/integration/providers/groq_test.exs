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
  end
end
