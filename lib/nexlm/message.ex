defmodule Nexlm.Message.Content do
  @moduledoc """
  Message validation and formatting for LLM providers.

  Provides a common structure for messages that can be sent to any LLM provider,
  with validation and conversion utilities.

  ## Message Structure
  ```elixir
  %{
    role: "user" | "assistant" | "system",
    content: String.t() | [ContentItem.t()]
  }
  ```

  ## Content Types
  - Text: Simple string content
  - Image: Base64 encoded image with mime type

  ## Examples
      # Text message
      %{
        "role" => "user",
        "content" => "Hello, how are you?"
      }

      # Message with image
      %{
        "role" => "user",
        "content" => [
          %{"type" => "text", "text" => "What's in this image?"},
          %{
            "type" => "image",
            "mime_type" => "image/jpeg",
            "data" => "base64_data"
          }
        ]
      }
  """

  use Drops.Type, %{
    required(:type) => string(in?: ["text", "image"]),
    optional(:text) => string(),
    # Image
    optional(:mime_type) => string(),
    optional(:data) => string(),
    # Cache
    optional(:cache) => boolean()
  }
end

defmodule Nexlm.Message.ToolCall do
  use Drops.Type, %{
    optional(:id) => string(),
    optional(:name) => string(),
    optional(:arguments) => map()
  }
end

defmodule Nexlm.Message do
  use Drops.Contract
  alias Nexlm.Error

  schema(atomize: true) do
    %{
      required(:role) => string(in?: ["assistant", "user", "system", "tool"]),
      required(:content) =>
        union([
          list(Nexlm.Message.Content),
          string(),
          map()
        ]),
      optional(:tool_call_id) => string(),
      optional(:tool_calls) => list(Nexlm.Message.ToolCall)
    }
  end

  def validate_message(message) when is_map(message) do
    case conform(message) do
      {:ok, validated} ->
        {:ok, validated}

      {:error, reason} ->
        {:error,
         Error.new(
           :validation_error,
           "Invalid message format: #{inspect(reason)}",
           :message_validator
         )}
    end
  end

  def validate_message(_),
    do: {:error, Error.new(:validation_error, "Message must be a map", :message_validator)}

  def validate_messages(messages) when is_list(messages) do
    messages
    |> convert_atom_keys_to_strings()
    |> Enum.reduce_while({:ok, []}, fn message, {:ok, acc} ->
      case validate_message(message) do
        {:ok, validated} -> {:cont, {:ok, [validated | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, validated} -> {:ok, Enum.reverse(validated)}
      error -> error
    end
  end

  def validate_messages(_),
    do: {:error, Error.new(:validation_error, "Messages must be a list", :message_validator)}

  defp convert_atom_keys_to_strings(messages) when is_list(messages) do
    Enum.map(messages, &convert_atom_keys_to_strings/1)
  end

  defp convert_atom_keys_to_strings(%{} = map) do
    Map.new(map, fn {k, v} ->
      {
        if(is_atom(k), do: Atom.to_string(k), else: k),
        convert_atom_keys_to_strings(v)
      }
    end)
  end

  defp convert_atom_keys_to_strings(value), do: value
end
