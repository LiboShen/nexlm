defmodule Nexlm.Providers.Groq do
  @moduledoc """
  Provider implementation for Groq's Chat Completion API.
  Groq API is OpenAI-compatible with some limitations.

  ## Model Names
  Models should be prefixed with "groq/", for example:
  - "groq/mixtral-8x7b-32768"
  - "groq/llama2-70b-4096"

  ## Message Formats
  Supports the following message types:
  - Text messages: Simple string content
  - System messages: Special instructions for model behavior

  Note: Image messages are not supported.

  ## Configuration
  Required:
  - API key in runtime config (:nexlm, Nexlm.Providers.Groq, api_key: "key")
  - Model name in request

  Optional:
  - temperature: Float between 0 and 2 (default: 0.0, will be converted to 1e-8 if 0)
  - max_tokens: Integer for response length limit
  - top_p: Float between 0 and 1 for nucleus sampling

  ## Limitations
  The following OpenAI features are not supported:
  - logprobs
  - logit_bias
  - top_logprobs
  - messages[].name
  - N > 1 (only single completions supported)
  """

  @behaviour Nexlm.Behaviour
  alias Nexlm.{Config, Error, Message}

  @receive_timeout 300_000
  @endpoint_url "https://api.groq.com/openai/v1/chat"

  @impl true
  def init(opts) do
    config_opts =
      opts
      |> Keyword.put_new(:receive_timeout, @receive_timeout)
      |> Keyword.put_new(:max_tokens, 4000)
      |> adjust_temperature(Keyword.get(opts, :temperature, 0.0))

    case Config.new(config_opts) do
      {:ok, config} ->
        if token(),
          do: {:ok, config},
          else: {:error, Error.new(:configuration_error, "Missing API key", :groq)}

      {:error, error} ->
        {:error,
         Error.new(
           :configuration_error,
           "Invalid configuration: #{inspect(error)}",
           :groq
         )}
    end
  end

  @impl true
  def validate_messages(messages) do
    case Message.validate_messages(messages) do
      {:ok, messages} -> {:ok, messages}
      {:error, error} -> {:error, %{error | provider: :groq}}
    end
  end

  @impl true
  def format_request(config, messages) do
    # Strip "groq/" prefix from model name
    model = String.replace(config.model, "groq/", "")

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

      {:ok, %{status: 401, body: %{"error" => %{"message" => message}}}} ->
        {:error, Error.new(:authentication_error, message, :groq)}

      {:ok, %{status: 400, body: %{"error" => %{"message" => message}}}} ->
        {:error, Error.new(:provider_error, message, :groq)}

      {:ok, %{status: 500, body: %{"error" => %{"message" => message}}}} ->
        {:error, Error.new(:provider_error, message, :groq)}

      {:ok, %{status: status, body: body}} ->
        {:error, Error.new(:provider_error, "Unexpected response: (#{status}) #{inspect(body)}", :groq)}

      {:error, %{reason: reason}} ->
        {:error, Error.new(:network_error, "Request failed: #{inspect(reason)}", :groq)}
    end
  end

  @impl true
  def parse_response(%{"role" => role, "content" => content}) do
    {:ok,
     %{
       role: role,
       content: content
     }}
  end

  # Private helpers

  defp format_message(%{role: role, content: content}) when is_binary(content) do
    %{
      role: role,
      content: content
    }
  end

  defp format_message(%{role: role, content: content}) when is_list(content) do
    # Groq doesn't support image messages, so we filter them out
    text_content = Enum.filter(content, fn item ->
      case item do
        %{type: "text"} -> true
        _ -> false
      end
    end)

    %{
      role: role,
      content: Enum.map(text_content, &format_content_item/1)
    }
  end

  defp format_content_item(%{type: "text", text: text}) do
    %{type: "text", text: text}
  end

  defp maybe_add_top_p(request, %{top_p: top_p}) when not is_nil(top_p) do
    Map.put(request, :top_p, top_p)
  end

  defp maybe_add_top_p(request, _), do: request

  defp adjust_temperature(opts, temp) when temp == 0.0 do
    Keyword.put(opts, :temperature, 1.0e-8)
  end

  defp adjust_temperature(opts, temp) when temp > 0.0 and temp <= 2.0 do
    Keyword.put(opts, :temperature, temp)
  end

  defp adjust_temperature(opts, _temp) do
    Keyword.put(opts, :temperature, 1.0)
  end

  defp token do
    Application.get_env(:nexlm, Nexlm.Providers.Groq, [])
    |> Keyword.get(:api_key)
  end
end
