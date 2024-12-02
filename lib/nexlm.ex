defmodule Nexlm do
  @moduledoc """
  A unified interface for interacting with various Large Language Model (LLM) providers.

  Nexlm abstracts away provider-specific implementations while offering a clean,
  consistent API for developers. This enables easy integration with different LLM
  services like OpenAI's GPT, Anthropic's Claude, and Google's Gemini.

  ## Features

  * Single, unified API for multiple LLM providers
  * Support for text and multimodal (image) inputs
  * Built-in validation and error handling
  * Configurable request parameters
  * Provider-agnostic message format
  * Caching support for reduced costs

  ## Provider Support

  Currently supported providers:
  - OpenAI (GPT-4, GPT-3.5)
  - Anthropic (Claude)
  - Google (Gemini)

  ## Model Names

  Model names must be prefixed with the provider name:

  - `"anthropic/claude-3-haiku-20240307"`
  - `"openai/gpt-4"`
  - `"google/gemini-pro"`

  ## Basic Usage

  ### Simple Text Completion

      messages = [%{
        "role" => "user",
        "content" => "What is the capital of France?"
      }]

      {:ok, response} = Nexlm.complete("anthropic/claude-3-haiku-20240307", messages)
      # => {:ok, %{role: "assistant", content: "The capital of France is Paris."}}

  ### With System Message

      messages = [
        %{
          "role" => "system",
          "content" => "You are a mathematician who only responds with numbers"
        },
        %{
          "role" => "user",
          "content" => "What is five plus five?"
        }
      ]

      {:ok, response} = Nexlm.complete("openai/gpt-4", messages, temperature: 0.7)
      # => {:ok, %{role: "assistant", content: "10"}}

  ### Image Analysis

      image_data = File.read!("image.jpg") |> Base.encode64()

      messages = [
        %{
          "role" => "user",
          "content" => [
            %{"type" => "text", "text" => "What's in this image?"},
            %{
              "type" => "image",
              "mime_type" => "image/jpeg",
              "data" => image_data,
              "cache" => true  # Enable caching for this content
            }
          ]
        }
      ]

      {:ok, response} = Nexlm.complete(
        "google/gemini-pro-vision",
        messages,
        max_tokens: 100
      )

  ## Configuration

  Configure provider API keys in your application's runtime configuration:

      # config/runtime.exs
      config :nexlm, Nexlm.Providers.OpenAI,
        api_key: System.get_env("OPENAI_API_KEY")

      config :nexlm, Nexlm.Providers.Anthropic,
        api_key: System.get_env("ANTHROPIC_API_KEY")

      config :nexlm, Nexlm.Providers.Google,
        api_key: System.get_env("GOOGLE_API_KEY")

  ## Error Handling

  The library provides structured error handling:

      case Nexlm.complete(model, messages, opts) do
        {:ok, response} ->
          handle_success(response)

        {:error, %Nexlm.Error{type: :rate_limit_error}} ->
          apply_rate_limit_backoff()

        {:error, %Nexlm.Error{type: :provider_error, message: msg}} ->
          Logger.error("Provider error: \#{msg}")
          handle_provider_error()

        {:error, error} ->
          Logger.error("Unexpected error: \#{inspect(error)}")
          handle_generic_error()
      end

  ## Message Format

  ### Simple Text Message
      %{
        "role" => "user",  # "user", "assistant", or "system"
        "content" => "Hello, world!"
      }

  ### Message with Image
      %{
        "role" => "user",
        "content" => [
          %{"type" => "text", "text" => "What's in this image?"},
          %{
            "type" => "image",
            "mime_type" => "image/jpeg",
            "data" => "base64_encoded_data",
            "cache" => true  # Optional caching flag
          }
        ]
      }

  ### System Message
      %{
        "role" => "system",
        "content" => "You are a helpful assistant"
      }

  ## Content Caching

  Nexlm supports provider-level message caching through content item configuration:

      # Image with caching enabled
      %{
        "type" => "image",
        "mime_type" => "image/jpeg",
        "data" => "base64_data",
        "cache" => true  # Enable caching
      }

  Currently supported by:
  - Anthropic (via `cache_control` in content items)
  - Other providers may add support in future updates
  """

  alias Nexlm.Service
  alias Nexlm.Error

  @typedoc """
  A message that can be sent to an LLM provider.

  Fields:
  - role: The role of the message sender ("user", "assistant", or "system")
  - content: The content of the message, either a string or a list of content items
  """
  @type message ::
          %{
            role: String.t(),
            content: String.t() | [content_item]
          }
          | %{
              # "tool"
              role: String.t(),
              tool_call_id: String.t(),
              content: map()
            }

  @typedoc """
  A content item in a message, used for multimodal inputs.

  Fields:
  - type: The type of content ("text" or "image")
  - text: The text content for text type items
  - mime_type: The MIME type for image content (e.g., "image/jpeg")
  - data: Base64 encoded image data
  - cache: Whether this content should be cached by the provider
  """
  @type content_item :: %{
          type: String.t(),
          text: String.t() | nil,
          mime_type: String.t() | nil,
          data: String.t() | nil,
          cache: boolean() | nil
        }

  @doc """
  Sends a request to an LLM provider and returns the response.

  This is the main entry point for interacting with LLM providers. It handles:
  - Message validation
  - Provider selection and configuration
  - Request formatting
  - Error handling
  - Response parsing

  ## Arguments

    * `model` - String in the format "provider/model-name" (e.g., "anthropic/claude-3")
    * `messages` - List of message maps with :role and :content keys
    * `opts` - Optional keyword list of settings

  ## Options

    * `:temperature` - Float between 0 and 1 (default: 0.0)
    * `:max_tokens` - Maximum tokens in response
    * `:top_p` - Float between 0 and 1
    * `:receive_timeout` - Timeout in milliseconds (default: 300_000)
    * `:retry_count` - Number of retry attempts (default: 3)
    * `:retry_delay` - Delay between retries in milliseconds (default: 1000)

  ## Examples

  ### Simple text completion:

      messages = [%{"role" => "user", "content" => "What's 2+2?"}]
      {:ok, response} = Nexlm.complete("anthropic/claude-3-haiku-20240307", messages)
      # => {:ok, %{role: "assistant", content: "4"}}

  ### With system message and temperature:

      messages = [
        %{"role" => "system", "content" => "Respond like a pirate"},
        %{"role" => "user", "content" => "Hello"}
      ]
      {:ok, response} = Nexlm.complete("openai/gpt-4", messages, temperature: 0.7)
      # => {:ok, %{role: "assistant", content: "Arr, ahoy there matey!"}}

  ### With image analysis:

      messages = [
        %{
          "role" => "user",
          "content" => [
            %{"type" => "text", "text" => "Describe this image:"},
            %{
              "type" => "image",
              "mime_type" => "image/jpeg",
              "data" => "base64_data",
              "cache" => true
            }
          ]
        }
      ]
      {:ok, response} = Nexlm.complete(
        "google/gemini-pro-vision",
        messages,
        max_tokens: 200
      )

  ## Returns

  Returns either:
  - `{:ok, message}` - Success response with assistant's message
  - `{:error, error}` - Error tuple with Nexlm.Error struct

  ## Error Handling

  Possible error types:
  - `:validation_error` - Invalid message format or content
  - `:provider_error` - Provider-specific API errors
  - `:rate_limit_error` - Rate limit exceeded
  - `:timeout_error` - Request timeout
  - `:configuration_error` - Invalid configuration
  """
  @spec complete(String.t(), [message], keyword()) ::
          {:ok, message} | {:error, Error.t()}
  def complete(model, messages, opts \\ [])
      when is_binary(model) and is_list(messages) and is_list(opts) do
    Service.call(model, messages, opts)
  end
end
