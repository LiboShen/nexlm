defmodule Nexlm.Providers.OpenAI do
  @moduledoc """
  Provider implementation for OpenAI's Chat Completion API.

  ## Model Names
  Models should be prefixed with "openai/", for example:
  - "openai/gpt-4"
  - "openai/gpt-4-vision-preview"
  - "openai/gpt-3.5-turbo"

  ## Message Formats
  Supports the following message types:
  - Text messages: Simple string content
  - System messages: Special instructions for model behavior
  - Image messages: Base64 encoded images or URLs (converted to data URLs)

  ## Configuration
  Required:
  - API key in runtime config (:nexlm, Nexlm.Providers.OpenAI, api_key: "key")
  - Model name in request

  Optional:
  - temperature: Float between 0 and 1 (default: 0.0)
  - max_tokens: Integer for response length limit
  - top_p: Float between 0 and 1 for nucleus sampling

  ## Examples
    # Simple text completion
    config = OpenAI.init(model: "openai/gpt-4")
    messages = [%{"role" => "user", "content" => "Hello"}]
    {:ok, response} = OpenAI.call(config, messages)

    # Vision API with image
    messages = [
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
    ]
    config = OpenAI.init(model: "openai/gpt-4o-mini")
  """

  @behaviour Nexlm.Behaviour
  alias Nexlm.{Config, Error, Message}

  @receive_timeout 300_000
  @endpoint_url "https://api.openai.com/v1/chat"

  @impl true
  def init(opts) do
    config_opts =
      opts
      |> Keyword.put_new(:receive_timeout, @receive_timeout)
      |> Keyword.put_new(:max_tokens, 4000)
      |> Keyword.put_new(:temperature, 0.0)

    case Config.new(config_opts) do
      {:ok, config} ->
        if token(),
          do: {:ok, config},
          else: {:error, Error.new(:configuration_error, "Missing API key", :openai)}

      {:error, changeset} ->
        {:error,
         Error.new(
           :configuration_error,
           "Invalid configuration: #{inspect(changeset.errors)}",
           :openai
         )}
    end
  end

  @impl true
  def validate_messages(messages) do
    case Message.validate_messages(messages) do
      {:ok, messages} -> {:ok, messages}
      {:error, error} -> {:error, %{error | provider: :openai}}
    end
  end

  @impl true
  def format_request(config, messages) do
    # Strip "openai/" prefix from model name
    model = String.replace(config.model, "openai/", "")

    request =
      %{
        model: model,
        messages: Enum.map(messages, &format_message/1),
        max_tokens: config.max_tokens,
        temperature: config.temperature
      }
      |> maybe_add_top_p(config)
      |> Enum.filter(fn {_, v} -> v end)
      |> Map.new()

    {:ok, request}
  end

  @impl true
  def call(config, request) do
    case Req.post(@endpoint_url <> "/completions",
           json: request,
           headers: [
             {"Authorization", "Bearer #{token()}"}
           ],
           receive_timeout: config.receive_timeout
         ) do
      {:ok, %{status: 200, body: %{"choices" => [%{"message" => message}]}}} ->
        {:ok, message}

      {:ok, %{status: 400, body: %{"error" => %{"message" => message}}}} ->
        {:error, Error.new(:provider_error, message, :openai)}

      {:ok, %{status: 500, body: %{"error" => %{"message" => message}}}} ->
        {:error, Error.new(:provider_error, message, :openai)}

      {:error, %{reason: reason}} ->
        {:error, Error.new(:network_error, "Request failed: #{inspect(reason)}", :openai)}
    end
  end

  @impl true
  def parse_response(%{"role" => role, "content" => content}) do
    {:ok, %{role: role, content: content}}
  end

  # Private helpers

  defp format_message(%{role: role, content: content}) when is_binary(content) do
    %{
      role: role,
      content: content
    }
  end

  defp format_message(%{role: role, content: content}) when is_list(content) do
    %{
      role: role,
      content: Enum.map(content, &format_content_item/1)
    }
  end

  defp format_content_item(%{type: "text", text: text}) do
    %{type: "text", text: text}
  end

  defp format_content_item(%{type: "image", mime_type: mime_type, data: data}) do
    %{
      type: "image_url",
      image_url: %{
        url: "data:#{mime_type};base64,#{data}"
      }
    }
  end

  defp maybe_add_top_p(request, %{top_p: top_p}) when not is_nil(top_p) do
    Map.put(request, :top_p, top_p)
  end

  defp maybe_add_top_p(request, _), do: request

  defp token do
    Application.get_env(:nexlm, Nexlm.Providers.OpenAI, [])
    |> Keyword.get(:api_key)
  end
end
