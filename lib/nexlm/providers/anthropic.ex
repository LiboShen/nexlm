defmodule Nexlm.Providers.Anthropic do
  @moduledoc """
  Provider implementation for Anthropic's Claude API.

  ## Model Names
  Models should be prefixed with "anthropic/", for example:
  - "anthropic/claude-3-haiku-20240307"
  - "anthropic/claude-3-opus-20240229"

  ## Message Formats
  Supports the following message types:
  - Text messages: Simple string content
  - System messages: Special instructions for model behavior
  - Image messages: Base64 encoded images with mime type

  ## Configuration
  Required:
  - API key in runtime config (:nexlm, Nexlm.Providers.Anthropic, api_key: "key")
  - Model name in request

  ## Examples
      # Simple text completion
      config = Anthropic.init(model: "anthropic/claude-3-haiku-20240307")
      messages = [%{"role" => "user", "content" => "Hello"}]
      {:ok, response} = Anthropic.call(config, messages)

      # With system message
      messages = [
        %{"role" => "system", "content" => "You are a helpful assistant"},
        %{"role" => "user", "content" => "Hello"}
      ]

      # With image input
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
  """

  @behaviour Nexlm.Behaviour
  alias Nexlm.{Config, Debug, Error, Message}

  @receive_timeout 300_000
  @endpoint_url "https://api.anthropic.com/v1"

  @impl true
  def init(opts) do
    config_opts =
      opts
      |> Keyword.put_new(:receive_timeout, @receive_timeout)
      |> Keyword.put_new(:max_tokens, 4000)

    case Config.new(config_opts) do
      {:ok, config} ->
        if token(),
          do: {:ok, config},
          else: {:error, Error.new(:configuration_error, "Missing API key", :anthropic)}

      {:error, error} ->
        {:error,
         Error.new(
           :configuration_error,
           "Invalid configuration: #{inspect(error)}",
           :anthropic
         )}
    end
  end

  @impl true
  def validate_messages(messages) do
    case Message.validate_messages(messages) do
      {:ok, messages} -> {:ok, messages}
      {:error, error} -> {:error, %{error | provider: :anthropic}}
    end
  end

  @impl true
  @spec format_request(any(), any()) :: {:ok, map()}
  def format_request(config, messages) do
    Debug.log_transformation("Input messages", messages)

    {system_message, messages} =
      case messages do
        [%{role: "system", content: system} | rest] ->
          {system, rest}

        messages ->
          {nil, messages}
      end

    # Strip "anthropic/" prefix from model name
    model = String.replace_prefix(config.model, "anthropic/", "")

    formatted_messages = Enum.map(messages, &format_message/1)
    Debug.log_transformation("Formatted messages", formatted_messages)

    request =
      %{
        model: model,
        messages: formatted_messages,
        system: system_message,
        max_tokens: config.max_tokens
      }
      |> maybe_add_temperature(config)
      |> maybe_add_top_p(config)
      |> maybe_add_tools(config)
      |> Enum.filter(fn {_, v} -> v end)
      |> Map.new()

    Debug.log_transformation("Final request", request)
    {:ok, request}
  end

  @impl true
  def call(config, request) do
    url = @endpoint_url <> "/messages"

    headers = [
      {"x-api-key", token()},
      {"anthropic-version", "2023-06-01"},
      {"anthropic-beta", "prompt-caching-2024-07-31"}
    ]

    Debug.log_request(:anthropic, :post, url, headers, request)

    Debug.time_call("Anthropic API request", fn ->
      case Req.post(url,
             json: request,
             headers: headers,
             receive_timeout: config.receive_timeout
           ) do
        {:ok, %{status: 200, body: body} = response} ->
          Debug.log_response(200, response.headers, body)
          {:ok, body}

        {:ok, %{status: status, body: %{"error" => %{"message" => message}} = body} = response} ->
          Debug.log_response(status, response.headers, body)
          error_type = if status >= 500, do: :provider_error, else: :provider_error
          {:error, Error.new(error_type, message, :anthropic)}

        {:ok, %{status: status, body: body} = response} ->
          Debug.log_response(status, response.headers, body)

          {:error,
           Error.new(:provider_error, "Unexpected response: #{inspect(body)}", :anthropic)}

        {:error, %{reason: reason}} ->
          Debug.log_response("ERROR", %{}, %{reason: reason})
          {:error, Error.new(:network_error, "Request failed: #{inspect(reason)}", :anthropic)}
      end
    end)
  end

  @impl true
  def parse_response(%{"content" => [%{"text" => text}], "role" => role}) do
    {:ok, %{role: role, content: text}}
  end

  def parse_response(%{"content" => content, "role" => role}) do
    tool_uses =
      Enum.filter(content, fn item ->
        item["type"] == "tool_use"
      end)
      |> Enum.map(fn item ->
        %{id: item["id"], name: item["name"], arguments: item["input"]}
      end)

    text =
      Enum.filter(content, fn item ->
        item["type"] == "text"
      end)
      |> Enum.map(fn item ->
        item["text"]
      end)
      |> Enum.join("")

    case tool_uses do
      [] ->
        {:ok, %{role: role, content: text}}

      tool_uses ->
        {:ok, %{role: role, content: text, tool_calls: tool_uses}}
    end
  end

  # Private helpers

  defp format_message(%{role: "tool", tool_call_id: tool_call_id, content: content}) do
    %{
      role: "user",
      content: [build_tool_result(tool_call_id, content)]
    }
  end

  defp format_message(%{role: role, content: content} = message) when is_binary(content) do
    formatted_content = format_text_content(content)
    tool_calls = format_tool_calls(message)

    build_message(role, formatted_content ++ tool_calls)
  end

  defp format_message(%{role: role, content: content} = message) when is_list(content) do
    formatted_content = Enum.map(content, &format_content_item/1)
    tool_calls = format_tool_calls(message)

    build_message(role, formatted_content ++ tool_calls)
  end

  defp format_content_item(%{type: "text", text: text} = item) do
    base = %{type: "text", text: text}
    maybe_add_cache_control(base, item)
  end

  defp format_content_item(%{type: "image", mime_type: mime_type, data: data} = item) do
    base = %{
      type: "image",
      source: %{
        type: "base64",
        media_type: mime_type,
        data: data
      }
    }

    maybe_add_cache_control(base, item)
  end

  defp format_content_item(%{type: "tool_use", id: id, name: name, input: input}) do
    %{type: "tool_use", id: id, name: name, input: input}
  end

  defp format_tool_call(%{id: id, name: name, arguments: input}) do
    %{type: "tool_use", id: id, name: name, input: input}
  end

  defp build_tool_result(tool_call_id, content) when is_list(content) do
    text = Enum.map(content, & &1.text) |> Enum.join()
    %{type: "tool_result", tool_use_id: tool_call_id, content: text}
  end

  defp build_tool_result(tool_call_id, content) when is_binary(content) do
    %{type: "tool_result", tool_use_id: tool_call_id, content: content}
  end

  defp format_text_content(""), do: []
  defp format_text_content(content), do: [%{type: "text", text: content}]

  defp format_tool_calls(message) do
    Map.get(message, :tool_calls, [])
    |> Enum.map(&format_tool_call/1)
  end

  defp build_message(role, content) do
    %{role: role, content: content}
  end

  defp maybe_add_cache_control(base, item) do
    if Map.get(item, :cache),
      do: Map.put(base, :cache_control, %{type: "ephemeral"}),
      else: base
  end

  defp maybe_add_temperature(request, %{temperature: temp}) when not is_nil(temp) do
    Map.put(request, :temperature, temp)
  end

  defp maybe_add_temperature(request, _), do: request

  defp maybe_add_top_p(request, %{top_p: top_p}) when not is_nil(top_p) do
    Map.put(request, :top_p, top_p)
  end

  defp maybe_add_top_p(request, _), do: request

  defp maybe_add_tools(request, %{tools: tools}) when length(tools) > 0 do
    Map.put(request, :tools, Enum.map(tools, &format_tool/1))
  end

  defp maybe_add_tools(request, _), do: request

  defp format_tool(tool) do
    %{
      name: tool.name,
      description: tool.description,
      input_schema: tool.parameters
    }
  end

  defp token do
    Application.get_env(:nexlm, Nexlm.Providers.Anthropic, [])
    |> Keyword.get(:api_key)
  end
end
