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
  alias Nexlm.{Config, Error, Message}

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

      {:error, changeset} ->
        {:error,
         Error.new(
           :configuration_error,
           "Invalid configuration: #{inspect(changeset.errors)}",
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

    {:ok, request}
  end

  @impl true
  def call(config, request) do
    # Strip "google/" prefix from model name
    model = String.replace(config.model, "google/", "")
    url = "#{@endpoint_url}/models/#{model}:generateContent?key=#{token()}"

    case Req.post(url,
           json: request,
           receive_timeout: config.receive_timeout
         ) do
      {:ok, %{status: 200, body: %{"candidates" => [%{"content" => content} | _]}}} ->
        {:ok, content}

      {:ok, %{status: _, body: %{"error" => %{"message" => message}}}} ->
        {:error, Error.new(:provider_error, message, :google)}

      {:error, %{reason: reason}} ->
        {:error, Error.new(:network_error, "Request failed: #{inspect(reason)}", :google)}
    end
  end

  @impl true
  def parse_response(%{"parts" => parts, "role" => "model"}) do
    {:ok,
     %{
       role: "assistant",
       content: parts |> Enum.map_join("\n", & &1["text"])
     }}
  end

  # Private helpers

  defp format_message(%{role: role, content: content}) when is_binary(content) do
    %{
      role: convert_role(role),
      parts: [%{text: content}]
    }
  end

  defp format_message(%{role: role, content: content}) when is_list(content) do
    %{
      role: convert_role(role),
      parts: Enum.map(content, &format_content_item/1)
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
end
