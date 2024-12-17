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

  use Elixact

  schema do
    field :type, :string do
      choices(["text", "image"])
    end

    field :text, :string do
      optional()
    end

    # Image
    field :mime_type, :string do
      optional()
    end

    field :data, :string do
      optional()
    end

    # Cache
    field :cache, :boolean do
      optional()
    end
  end
end

defmodule Nexlm.Message.ToolCall do
  use Elixact

  schema do
    field(:id, :string)
    field(:name, :string)
    field(:arguments, :any)
  end
end

defmodule Nexlm.Message do
  use Elixact
  alias Nexlm.Error

  schema do
    field :role, :string do
      choices(["assistant", "user", "system", "tool"])
    end

    field :content, {:union, [:string, {:array, Nexlm.Message.Content}]} do
    end

    field :tool_call_id, :string do
      optional()
    end

    field :tool_calls, {:array, Nexlm.Message.ToolCall} do
      optional()
      default([])
    end
  end

  def validate_message(message) when is_map(message) do
    case validate(message) do
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
