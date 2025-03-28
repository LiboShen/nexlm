# Nexlm

A unified interface (Nexus) for interacting with various Large Language Model (LLM) providers in Elixir.
Nexlm abstracts away provider-specific implementations while offering a clean, consistent API for developers.

## Features

- Single, unified API for multiple LLM providers
- Support for text and multimodal (image) inputs
- Built-in validation and error handling
- Configurable request parameters
- Provider-agnostic message format
- Caching support for reduced costs

## Supported Providers

- OpenAI (GPT-4, GPT-3.5)
- Anthropic (Claude)
- Google (Gemini)
- Groq

## Installation

Add `nexlm` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:nexlm, "~> 0.1.0"}
  ]
end
```

## Configuration

Configure your API keys in `config/runtime.exs`:

```elixir
import Config

config :nexlm, Nexlm.Providers.OpenAI,
  api_key: System.get_env("OPENAI_API_KEY")

config :nexlm, Nexlm.Providers.Anthropic,
  api_key: System.get_env("ANTHROPIC_API_KEY")

config :nexlm, Nexlm.Providers.Google,
  api_key: System.get_env("GOOGLE_API_KEY")
```

## Basic Usage

### Simple Text Completion

```elixir
messages = [
  %{"role" => "user", "content" => "What is the capital of France?"}
]

{:ok, response} = Nexlm.complete("anthropic/claude-3-haiku-20240307", messages)
# => {:ok, %{role: "assistant", content: "The capital of France is Paris."}}
```

### With System Message

```elixir
messages = [
  %{
    "role" => "system",
    "content" => "You are a helpful assistant who always responds in JSON format"
  },
  %{
    "role" => "user",
    "content" => "List 3 European capitals"
  }
]

{:ok, response} = Nexlm.complete("openai/gpt-4", messages, temperature: 0.7)
```

### Image Analysis

```elixir
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
```

### Tool Usage

(Currently, only supported by the Anthropic provider)

```elixir
# Define available tools
tools = [
  %{
    name: "get_weather",
    description: "Get the weather for a location",
    parameters: %{
      type: "object",
      properties: %{
        location: %{
          type: "string",
          description: "The city and state, e.g. San Francisco, CA"
        }
      },
      required: ["location"]
    }
  }
]

# Initial message
messages = [
  %{"role" => "user", "content" => "What's the weather in London?"}
]

# First call - model will request weather data
{:ok, response} = Nexlm.complete(
  "anthropic/claude-3-haiku-20240307",
  messages,
  tools: tools
)

# Handle tool call
[%{id: tool_call_id, name: "get_weather", arguments: %{"location" => "London"}}] =
  response.tool_calls

# Add tool response to messages
messages = messages ++ [
  response,
  %{
    "role" => "tool",
    "tool_call_id" => tool_call_id,
    "content" => "sunny"
  }
]

# Final call - model will incorporate tool response
{:ok, response} = Nexlm.complete(
  "anthropic/claude-3-haiku-20240307",
  messages,
  tools: tools
)
# => {:ok, %{role: "assistant", content: "The weather in London is sunny."}}
```

## Error Handling

```elixir
case Nexlm.complete(model, messages, opts) do
  {:ok, response} ->
    handle_success(response)

  {:error, %Nexlm.Error{type: :rate_limit_error}} ->
    apply_rate_limit_backoff()

  {:error, %Nexlm.Error{type: :provider_error, message: msg}} ->
    Logger.error("Provider error: #{msg}")
    handle_provider_error()

  {:error, error} ->
    Logger.error("Unexpected error: #{inspect(error)}")
    handle_generic_error()
end
```

## Model Names

Model names must be prefixed with the provider name:

- `"anthropic/claude-3-haiku-20240307"`
- `"openai/gpt-4"`
- `"google/gemini-pro"`

## Configuration Options

Available options for `Nexlm.complete/3`:

- `:temperature` - Float between 0 and 1 (default: 0.0)
- `:max_tokens` - Maximum tokens in response
- `:top_p` - Float between 0 and 1 for nucleus sampling
- `:receive_timeout` - Timeout in milliseconds (default: 300_000)
- `:retry_count` - Number of retry attempts (default: 3)
- `:retry_delay` - Delay between retries in milliseconds (default: 1000)

## Message Format

### Simple Text Message
```elixir
%{
  "role" => "user",
  "content" => "Hello, world!"
}
```

### Message with Image
```elixir
%{
  "role" => "user",
  "content" => [
    %{"type" => "text", "text" => "What's in this image?"},
    %{
      "type" => "image",
      "mime_type" => "image/jpeg",
      "data" => "base64_encoded_data"
    }
  ]
}
```

### System Message
```elixir
%{
  "role" => "system",
  "content" => "You are a helpful assistant"
}
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/my-feature`)
3. Run tests (`mix test`)
4. Commit your changes
5. Push to your branch
6. Create a Pull Request

## Testing

Run the test suite:

```bash
# Run unit tests only
make test

# Run integration tests (requires API keys in .env.local)
make test.integration
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.
