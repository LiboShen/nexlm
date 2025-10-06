# Nexlm

A unified interface (Nexus) for interacting with various Large Language Model (LLM) providers in Elixir.
Nexlm abstracts away provider-specific implementations while offering a clean, consistent API for developers.

## Features

- Single, unified API for multiple LLM providers
- Support for text and multimodal (image) inputs
- Function/tool calling support (all providers)
- Built-in validation and error handling
- Configurable request parameters
- Provider-agnostic message format
- Caching support for reduced costs
- Comprehensive debug logging

## Supported Providers

- OpenAI (GPT-5, GPT-4, GPT-3.5, o1)
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

# Optional: Enable debug logging
config :nexlm, :debug, true
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

(Supported by all providers: OpenAI, Anthropic, Google, and Groq)

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

  {:error, %Nexlm.Error{type: :network_error}} ->
    retry_request()

  {:error, %Nexlm.Error{type: :provider_error, message: msg, details: details}} ->
    status = Map.get(details, :status, "n/a")
    Logger.error("Provider error (status #{status}): #{msg}")
    handle_provider_error(status)

  {:error, %Nexlm.Error{type: :authentication_error}} ->
    refresh_credentials()

  {:error, error} ->
    Logger.error("Unexpected error: #{inspect(error)}")
    handle_generic_error()
end
```

`%Nexlm.Error{details: %{status: status}}` captures the provider's HTTP status
code whenever the failure comes directly from the upstream API, making it easy
to decide whether to retry.

## Model Names

Model names must be prefixed with the provider name:

- `"anthropic/claude-3-haiku-20240307"`
- `"openai/gpt-4"`
- `"google/gemini-pro"`

## Configuration Options

Available options for `Nexlm.complete/3`:

- `:temperature` - Float between 0 and 1 (default: 0.0) *Note: Not supported by reasoning models (GPT-5, o1)*
- `:max_tokens` - Maximum tokens in response (default: 4000)
- `:top_p` - Float between 0 and 1 for nucleus sampling
- `:receive_timeout` - Timeout in milliseconds (default: 300_000)
- `:retry_count` - Number of retry attempts (default: 3)
- `:retry_delay` - Delay between retries in milliseconds (default: 1000)

### Reasoning Models (GPT-5, o1)

Reasoning models have special parameter requirements:
- **Temperature**: Not supported - these models use a fixed temperature internally
- **Token limits**: Use `max_completion_tokens` parameter internally (handled automatically)
- **Reasoning tokens**: Models use hidden reasoning tokens that don't appear in output but count toward usage

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

## Debug Logging

Enable detailed debug logging to see exactly what requests are sent and what responses are received:

```elixir
# Enable in configuration
config :nexlm, :debug, true
```

Or set environment variable:
```bash
export NEXLM_DEBUG=true
```

When enabled, debug logs will show:
- Complete HTTP requests (with sensitive headers redacted)
- Complete HTTP responses
- Message validation and transformation steps
- Request timing information
- Cache control headers (useful for debugging caching issues)

Example debug output:
```
[debug] [Nexlm] Starting request for model: anthropic/claude-3-haiku-20240307
[debug] [Nexlm] Input messages: [%{role: "user", content: [%{type: "image", cache: true, ...}]}]
[debug] [Nexlm] Formatted messages: [%{role: "user", content: [%{type: "image", cache_control: %{type: "ephemeral"}, ...}]}]
[debug] [Nexlm] Provider: anthropic
[debug] [Nexlm] Request: POST https://api.anthropic.com/v1/messages
[debug] [Nexlm] Headers: %{"x-api-key" => "[REDACTED]", "anthropic-beta" => "prompt-caching-2024-07-31"}
[debug] [Nexlm] Response: 200 OK (342ms)
[debug] [Nexlm] Complete request completed in 350ms
```

This is particularly useful for:
- Debugging caching behavior
- Understanding request/response transformations
- Troubleshooting API issues
- Performance monitoring

## Testing Without Live HTTP Calls

Nexlm ships with a dedicated stub provider (`Nexlm.Providers.Stub`) so you can exercise your application without touching real LLM endpoints. Any model starting with `"stub/"` is routed to the in-memory store rather than performing HTTP requests.

### Queue Responses

Use `Nexlm.Providers.Stub.Store` to script the responses you need:

```elixir
alias Nexlm.Providers.Stub.Store

setup do
  Store.put("stub/echo", fn _config, %{messages: [%{content: content} | _]} ->
    {:ok, %{role: "assistant", content: "stubbed: #{content}"}}
  end)

  on_exit(&Store.clear/0)
end

test "responds with stubbed data" do
  assert {:ok, %{content: "stubbed: ping"}} =
           Nexlm.complete("stub/echo", [%{"role" => "user", "content" => "ping"}])
end
```

Each call dequeues the next scripted response, keeping async tests isolated by storing state in the process dictionary.

### Deterministic Sequences

Queue multiple steps for tool flows or retries with `put_sequence/2`:

```elixir
Store.put_sequence("stub/tool-flow", [
  {:ok,
   %{
     role: "assistant",
     tool_calls: [%{id: "call-1", name: "lookup", arguments: %{id: 42}}]
   }},
  {:ok, %{role: "assistant", content: "lookup:42"}}
])
```

### Scoped Helpers

Wrap short-lived stubs with `with_stub/3` to avoid manual cleanup:

```elixir
Store.with_stub("stub/error", {:error, :service_unavailable}, fn ->
  {:error, error} = Nexlm.complete("stub/error", messages)
  assert error.type == :provider_error
end)
```

Returning `{:error, term}` or raising inside the function automatically produces a `%Nexlm.Error{provider: :stub}` so your application can exercise failure paths without reaching the network.

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
