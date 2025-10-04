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
  alias Nexlm.{Config, Error, HTTP, Message}

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
    model = String.replace_prefix(config.model, "groq/", "")

    request =
      %{
        model: model,
        messages: Enum.map(messages, &format_message/1),
        max_tokens: config.max_tokens,
        temperature: config.temperature
      }
      |> maybe_add_top_p(config)
      |> maybe_add_tools(config)
      |> Enum.filter(fn {_, v} -> v end)
      |> Map.new()

    {:ok, request}
  end

  @impl true
  def call(config, request) do
    case HTTP.post(@endpoint_url <> "/completions",
           json: request,
           headers: [
             {"Authorization", "Bearer #{token()}"}
           ],
           receive_timeout: config.receive_timeout
         ) do
      {:ok, %{status: 200, body: %{"choices" => [%{"message" => message}]}}} ->
        {:ok, message}

      {:ok, %{status: 401, body: %{"error" => %{"message" => message}}}} ->
        {:error, Error.new(:authentication_error, message, :groq, %{status: 401})}

      {:ok, %{status: 400, body: %{"error" => %{"message" => message}}}} ->
        {:error, Error.new(:provider_error, message, :groq, %{status: 400})}

      {:ok, %{status: 500, body: %{"error" => %{"message" => message}}}} ->
        {:error, Error.new(:provider_error, message, :groq, %{status: 500})}

      {:ok, %{status: status, body: body}} ->
        {:error,
         Error.new(:provider_error, "Unexpected response: (#{status}) #{inspect(body)}", :groq, %{
           status: status
         })}

      {:error, %{reason: reason}} ->
        {:error, Error.new(:network_error, "Request failed: #{inspect(reason)}", :groq)}
    end
  end

  @impl true
  def parse_response(%{"role" => role} = message)
      when role in ["assistant", "user", "tool", "system"] do
    tool_calls =
      case message do
        %{"tool_calls" => [%{"function" => %{}} | _] = calls} ->
          Enum.map(calls, fn %{"function" => %{"name" => name, "arguments" => args}, "id" => id} ->
            case Jason.decode(args) do
              {:ok, parsed_args} -> %{id: id, name: name, arguments: parsed_args}
            end
          end)

        _ ->
          []
      end

    text =
      case message do
        %{"content" => text} when is_binary(text) ->
          text

        %{"content" => text_items} when is_list(text_items) ->
          text_items
          |> Enum.filter(&match?(%{type: "text", text: _}, &1))
          |> Enum.map(& &1.text)
          |> Enum.join("")

        %{"content" => nil} ->
          ""

        _ ->
          ""
      end

    case tool_calls do
      [] -> {:ok, %{role: role, content: text}}
      tool_calls -> {:ok, %{role: role, content: text, tool_calls: tool_calls}}
    end
  end

  def parse_response(response) do
    {:error, Error.new(:provider_error, "Invalid response format: #{inspect(response)}", :groq)}
  end

  # Private helpers

  defp format_message(%{role: "tool", tool_call_id: tool_call_id, content: content}) do
    %{role: "tool", tool_call_id: tool_call_id, content: extract_text(content)}
  end

  defp format_message(%{role: "system", content: content}) do
    text = extract_text(content)

    %{role: "system", content: text}
  end

  defp format_message(%{role: "assistant", content: content} = message) do
    text = extract_text(content)
    tool_calls = format_tool_calls(message)

    %{role: "assistant", content: text, tool_calls: tool_calls}
  end

  defp format_message(%{role: "user", content: content}) do
    %{role: "user", content: content}
  end

  defp extract_text(content) when is_binary(content) do
    content
  end

  defp extract_text(content) when is_list(content) do
    content
    |> Enum.filter(&match?(%{type: "text", text: _}, &1))
    |> Enum.map(& &1.text)
    |> Enum.join("")
  end

  defp format_tool_calls(%{tool_calls: tool_calls}) when is_list(tool_calls) do
    Enum.map(tool_calls, &format_tool_call/1)
  end

  defp format_tool_calls(_), do: []

  defp format_tool_call(%{id: id, name: name, arguments: arguments}) do
    %{
      id: id,
      type: "function",
      function: %{
        name: name,
        arguments: Jason.encode!(arguments)
      }
    }
  end

  defp maybe_add_tools(request, %{tools: tools}) when length(tools) > 0 do
    Map.merge(request, %{
      tools: Enum.map(tools, &format_tool/1),
      tool_choice: "auto"
    })
  end

  defp maybe_add_tools(request, _), do: request

  defp format_tool(tool) do
    %{
      type: "function",
      function: %{
        name: tool.name,
        description: tool.description,
        parameters: tool.parameters
      }
    }
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
