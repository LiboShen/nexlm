defmodule Nexlm.Providers.Google do
  @moduledoc """
  Provider implementation for Google's Gemini API.

  ## Model Names
  Models should be prefixed with "google/", for example:
  - "google/gemini-1.5-flash-latest"
  - "google/gemini-1.5-pro-latest"

  ## Message Formats
  Supports the following message types:
  - Text messages: Simple string content
  - System messages: Special instructions using systemInstruction format
  - Image messages: Base64 encoded images with mime type

  ## Configuration
  Required:
  - API key in runtime config (:nexlm, Nexlm.Providers.Google, api_key: "key")
  - Model name in request

  Optional:
  - temperature: Float between 0 and 1 (default: 0.0)
  - max_tokens: Integer for response length limit
  - top_p: Float between 0 and 1 (default: 0.95)

  ## Examples
      # Simple text completion
      config = Google.init(model: "google/gemini-1.5-flash-latest")
      messages = [%{"role" => "user", "content" => "Hello"}]
      {:ok, response} = Google.call(config, messages)

      # With system instruction
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

  ## Safety Settings
  Default safety settings are applied to prevent harmful content:
  - HARM_CATEGORY_HATE_SPEECH
  - HARM_CATEGORY_DANGEROUS_CONTENT
  - HARM_CATEGORY_SEXUALLY_EXPLICIT
  - HARM_CATEGORY_HARASSMENT
  """

  @behaviour Nexlm.Behaviour
  alias Nexlm.{Config, Debug, Error, Message}

  @receive_timeout 300_000
  @endpoint_url "https://generativelanguage.googleapis.com/v1beta"

  @impl true
  def init(opts) do
    config_opts =
      opts
      |> Keyword.put_new(:receive_timeout, @receive_timeout)
      |> Keyword.put_new(:max_tokens, 8192)
      |> Keyword.put_new(:temperature, 0.0)
      |> Keyword.put_new(:top_p, 0.95)

    case Config.new(config_opts) do
      {:ok, config} ->
        if token(),
          do: {:ok, config},
          else: {:error, Error.new(:configuration_error, "Missing API key", :google)}

      {:error, error} ->
        {:error,
         Error.new(
           :configuration_error,
           "Invalid configuration: #{inspect(error)}",
           :google
         )}
    end
  end

  @impl true
  def validate_messages(messages) do
    case Message.validate_messages(messages) do
      {:ok, messages} -> {:ok, messages}
      {:error, error} -> {:error, %{error | provider: :google}}
    end
  end

  @impl true
  def format_request(config, messages) do
    Debug.log_transformation("Input messages", messages)

    {system_message, messages} =
      case messages do
        [%{role: "system", content: system} | rest] ->
          {system, rest}

        messages ->
          {nil, messages}
      end

    request = %{
      contents: Enum.map(messages, &format_message/1),
      generationConfig: %{
        maxOutputTokens: config.max_tokens,
        temperature: config.temperature,
        topP: config.top_p
      },
      safetySettings: default_safety_settings()
    }

    # Add system instruction in the correct format
    request =
      if system_message do
        Map.put(request, :systemInstruction, %{
          parts: [%{text: system_message}]
        })
      else
        request
      end

    # Add tools if configured
    request = maybe_add_tools(request, config)

    Debug.log_transformation("Final request", request)
    {:ok, request}
  end

  @impl true
  def call(config, request) do
    # Strip "google/" prefix from model name
    model = String.replace(config.model, "google/", "")
    url = "#{@endpoint_url}/models/#{model}:generateContent?key=#{token()}"

    Debug.log_request(:google, :post, url, [], request)

    Debug.time_call("Google API request", fn ->
      case Req.post(url,
             json: request,
             receive_timeout: config.receive_timeout
           ) do
        {:ok,
         %{status: 200, body: %{"candidates" => [%{"content" => content} | _]} = body} = response} ->
          Debug.log_response(200, response.headers, body)
          {:ok, content}

        {:ok, %{status: status, body: %{"error" => %{"message" => message}} = body} = response} ->
          Debug.log_response(status, response.headers, body)
          {:error, Error.new(:provider_error, message, :google)}

        {:ok, %{status: status, body: body} = response} ->
          Debug.log_response(status, response.headers, body)
          {:error, Error.new(:provider_error, "Unexpected response: #{inspect(body)}", :google)}

        {:error, %{reason: reason}} ->
          Debug.log_response("ERROR", %{}, %{reason: reason})
          {:error, Error.new(:network_error, "Request failed: #{inspect(reason)}", :google)}
      end
    end)
  end

  @impl true
  def parse_response(%{"parts" => parts, "role" => "model"}) do
    # Extract function calls
    function_calls =
      Enum.filter(parts, fn part ->
        Map.has_key?(part, "functionCall")
      end)
      |> Enum.map(fn part ->
        call = part["functionCall"]
        function_name = call["name"]

        %{
          id: generate_tool_id(function_name),
          name: function_name,
          arguments: call["args"] || %{}
        }
      end)

    # Extract text content
    text_content =
      Enum.filter(parts, fn part ->
        Map.has_key?(part, "text")
      end)
      |> Enum.map_join("\n", & &1["text"])

    case function_calls do
      [] ->
        {:ok, %{role: "assistant", content: text_content}}

      calls ->
        {:ok, %{role: "assistant", content: text_content, tool_calls: calls}}
    end
  end

  # Private helpers

  defp format_message(%{role: "tool", tool_call_id: tool_call_id, content: content}) do
    %{
      role: "function",
      parts: [build_function_result(tool_call_id, content)]
    }
  end

  defp format_message(%{role: role, content: content} = message) when is_binary(content) do
    formatted_content = [%{text: content}]
    function_calls = format_function_calls(message)

    %{
      role: convert_role(role),
      parts: formatted_content ++ function_calls
    }
  end

  defp format_message(%{role: role, content: content} = message) when is_list(content) do
    formatted_content = Enum.map(content, &format_content_item/1)
    function_calls = format_function_calls(message)

    %{
      role: convert_role(role),
      parts: formatted_content ++ function_calls
    }
  end

  defp format_content_item(%{type: "text", text: text}) do
    %{text: text}
  end

  defp format_content_item(%{type: "image", mime_type: mime_type, data: data}) do
    %{
      inlineData: %{
        mimeType: mime_type,
        data: data
      }
    }
  end

  defp convert_role("user"), do: "user"
  defp convert_role("assistant"), do: "model"
  # Handle system role specially
  defp convert_role("system"), do: "user"

  defp default_safety_settings do
    [
      %{
        category: "HARM_CATEGORY_HATE_SPEECH",
        threshold: "BLOCK_ONLY_HIGH"
      },
      %{
        category: "HARM_CATEGORY_DANGEROUS_CONTENT",
        threshold: "BLOCK_ONLY_HIGH"
      },
      %{
        category: "HARM_CATEGORY_SEXUALLY_EXPLICIT",
        threshold: "BLOCK_ONLY_HIGH"
      },
      %{
        category: "HARM_CATEGORY_HARASSMENT",
        threshold: "BLOCK_ONLY_HIGH"
      }
    ]
  end

  defp token do
    Application.get_env(:nexlm, Nexlm.Providers.Google, [])
    |> Keyword.get(:api_key)
  end

  defp maybe_add_tools(request, %{tools: tools}) when length(tools) > 0 do
    formatted_tools = Enum.map(tools, &format_tool/1)
    Map.put(request, :tools, %{functionDeclarations: formatted_tools})
  end

  defp maybe_add_tools(request, _), do: request

  defp format_tool(tool) do
    %{
      name: tool.name,
      description: tool.description,
      parameters: tool.parameters
    }
  end

  defp format_function_calls(message) do
    Map.get(message, :tool_calls, [])
    |> Enum.map(&format_function_call/1)
  end

  defp format_function_call(%{id: _id, name: name, arguments: args}) do
    %{
      functionCall: %{
        name: name,
        args: args
      }
    }
  end

  defp build_function_result(tool_call_id, content) when is_binary(content) do
    # Extract function name from the tool_call_id. In our implementation,
    # we'll store the function name in the tool_call_id for Google
    function_name = extract_function_name_from_id(tool_call_id)

    %{
      functionResponse: %{
        name: function_name,
        response: %{result: content}
      }
    }
  end

  defp build_function_result(tool_call_id, content) when is_list(content) do
    text = Enum.map(content, & &1.text) |> Enum.join()
    build_function_result(tool_call_id, text)
  end

  defp extract_function_name_from_id(tool_call_id) do
    # For Google, we'll embed the function name in the tool_call_id
    # Format: "call_<function_name>_<8_char_random>"
    case Regex.run(~r/^call_(.+)_[a-f0-9]{8}$/, tool_call_id) do
      [_full, function_name] -> function_name
      _ -> "unknown_function"
    end
  end

  defp generate_tool_id(function_name) do
    "call_#{function_name}_#{:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)}"
  end
end
