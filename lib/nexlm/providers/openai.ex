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
  alias Nexlm.{Config, Debug, Error, Message}

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

      {:error, error} ->
        {:error,
         Error.new(
           :configuration_error,
           "Invalid configuration: #{inspect(error)}",
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
    Debug.log_transformation("Input messages", messages)

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
      |> maybe_add_tools(config)
      |> Enum.filter(fn {_, v} -> v end)
      |> Map.new()

    Debug.log_transformation("Final request", request)
    {:ok, request}
  end

  @impl true
  def call(config, request) do
    headers = [{"Authorization", "Bearer #{token()}"}]

    Debug.log_request(:openai, :post, @endpoint_url <> "/completions", headers, request)

    Debug.time_call("OpenAI API request", fn ->
      case Req.post(@endpoint_url <> "/completions",
             json: request,
             headers: headers,
             receive_timeout: config.receive_timeout
           ) do
        {:ok, %{status: 200, body: %{"choices" => [%{"message" => message}]} = body} = response} ->
          Debug.log_response(200, response.headers, body)
          {:ok, message}

        {:ok, %{status: status, body: %{"error" => %{"message" => message}} = body} = response} ->
          Debug.log_response(status, response.headers, body)
          error_type = if status >= 500, do: :provider_error, else: :provider_error
          {:error, Error.new(error_type, message, :openai)}

        {:ok, %{status: status, body: body} = response} ->
          Debug.log_response(status, response.headers, body)
          {:error, Error.new(:provider_error, "Unexpected response: #{inspect(body)}", :openai)}

        {:error, %{reason: reason}} ->
          Debug.log_response("ERROR", %{}, %{reason: reason})
          {:error, Error.new(:network_error, "Request failed: #{inspect(reason)}", :openai)}
      end
    end)
  end

  @impl true
  def parse_response(%{"role" => role, "content" => content} = message) do
    # Check for tool calls
    case Map.get(message, "tool_calls") do
      nil ->
        {:ok, %{role: role, content: content || ""}}

      tool_calls ->
        parsed_tool_calls =
          Enum.map(tool_calls, fn tool_call ->
            %{
              id: tool_call["id"],
              name: tool_call["function"]["name"],
              arguments: Jason.decode!(tool_call["function"]["arguments"])
            }
          end)

        {:ok, %{role: role, content: content || "", tool_calls: parsed_tool_calls}}
    end
  end

  # Private helpers

  defp format_message(%{role: "tool", tool_call_id: tool_call_id, content: content}) do
    %{
      role: "tool",
      tool_call_id: tool_call_id,
      content: extract_text_content(content)
    }
  end

  defp format_message(%{role: role, content: content} = message) when is_binary(content) do
    base = %{role: role, content: content}
    maybe_add_tool_calls(base, message)
  end

  defp format_message(%{role: role, content: content} = message) when is_list(content) do
    base = %{
      role: role,
      content: Enum.map(content, &format_content_item/1)
    }

    maybe_add_tool_calls(base, message)
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

  defp maybe_add_tools(request, %{tools: tools}) when length(tools) > 0 do
    formatted_tools = Enum.map(tools, &format_tool/1)
    Map.put(request, :tools, formatted_tools)
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

  defp maybe_add_tool_calls(message, %{tool_calls: tool_calls}) when length(tool_calls) > 0 do
    formatted_tool_calls = Enum.map(tool_calls, &format_tool_call/1)
    Map.put(message, :tool_calls, formatted_tool_calls)
  end

  defp maybe_add_tool_calls(message, _), do: message

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

  defp extract_text_content(content) when is_binary(content), do: content

  defp extract_text_content(content) when is_list(content) do
    content
    |> Enum.filter(&Map.has_key?(&1, :text))
    |> Enum.map(& &1.text)
    |> Enum.join("")
  end

  defp extract_text_content(_), do: ""

  defp token do
    Application.get_env(:nexlm, Nexlm.Providers.OpenAI, [])
    |> Keyword.get(:api_key)
  end
end
