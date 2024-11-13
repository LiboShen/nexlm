defmodule Nexlm do
  @moduledoc """
  A unified interface for interacting with various Large Language Model (LLM) providers.

  This module provides a consistent API for making requests to different LLM services
  like OpenAI, Anthropic, and Google, handling all the provider-specific implementation
  details internally.

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

      # Configure test provider for example
      Application.put_env(:nexlm, :registry_module, NexlmTest.TestRegistry)

      iex> messages = [%{"role" => "user", "content" => "Say hello"}]
      iex> {:ok, response} = Nexlm.complete("test/model", messages)
      iex> response.role
      "assistant"
      iex> response.content
      "mock response"

  ## System Messages

      messages = [
        %{
          "role" => "system",
          "content" => "You are a mathematician who only responds with numbers"
        },
        %{"role" => "user", "content" => "What is five plus five?"}
      ]
      
      {:ok, response} = Nexlm.complete("openai/gpt-4", messages, temperature: 0.7)

  ## Image Analysis

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
              "cache" => true
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

  Provider API keys should be configured in your application's configuration:

      # config/runtime.exs
      config :nexlm, Nexlm.Providers.OpenAI,
        api_key: System.get_env("OPENAI_API_KEY")

      config :nexlm, Nexlm.Providers.Anthropic,
        api_key: System.get_env("ANTHROPIC_API_KEY")

      config :nexlm, Nexlm.Providers.Google,
        api_key: System.get_env("GOOGLE_API_KEY")

  ## Error Handling

      case Nexlm.complete(model, messages, opts) do
        {:ok, response} ->
          handle_success(response)

        {:error, %Nexlm.Error{type: :rate_limit_error}} ->
          apply_rate_limit_backoff()

        {:error, %Nexlm.Error{type: :provider_error, message: msg}} ->
          Logger.error("Provider error: \#{msg}")
          handle_provider_error()
      end
  """

  alias Nexlm.Service
  alias Nexlm.Error

  @type message :: %{
    role: String.t(),
    content: String.t() | [content_item]
  }

  @type content_item :: %{
    type: String.t(),
    text: String.t() | nil,
    mime_type: String.t() | nil,
    data: String.t() | nil,
    cache: boolean() | nil
  }

  @doc """
  Sends a request to an LLM provider and returns the response.

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

      iex> messages = [%{"role" => "user", "content" => "Say something"}]
      iex> {:ok, response} = Nexlm.complete("test/model", messages)
      iex> response.role == "assistant" and is_binary(response.content)
      true

  ## Returns

    * `{:ok, response}` where response is a message map with :role and :content
    * `{:error, error}` where error is a Nexlm.Error struct
  """
  @spec complete(String.t(), [message], keyword()) ::
          {:ok, message} | {:error, Error.t()}
  def complete(model, messages, opts \\ [])
      when is_binary(model) and is_list(messages) and is_list(opts) do
    Service.call(model, messages, opts)
  end
end