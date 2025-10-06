defmodule Nexlm.Providers.Stub do
  @moduledoc """
  Fake provider used in tests to bypass real LLM HTTP calls.

  Configure Nexlm to use models prefixed with `stub/` and preload responses via
  `Nexlm.Providers.Stub.Store`. Each call dequeues the next stubbed reply,
  keeping async ExUnit tests isolated by storing state in the process dictionary.
  """

  @behaviour Nexlm.Behaviour

  alias Nexlm.{Config, Error, Message}
  alias Nexlm.Providers.Stub.Store

  @impl true
  def init(opts) do
    case Config.new(opts) do
      {:ok, config} ->
        {:ok, config}

      {:error, reason} ->
        {:error,
         Error.new(
           :configuration_error,
           "Invalid configuration: #{inspect(reason)}",
           :stub
         )}
    end
  end

  @impl true
  def validate_messages(messages) do
    case Message.validate_messages(messages) do
      {:ok, validated} -> {:ok, validated}
      {:error, %Error{} = error} -> {:error, %{error | provider: :stub}}
    end
  end

  @impl true
  def format_request(config, messages) do
    {:ok, %{model: config.model, messages: messages}}
  end

  @impl true
  def call(config, request) do
    Store.next_response(config.model, config, request)
  end

  @impl true
  def parse_response(%{role: role} = response) when is_binary(role) do
    {:ok, normalize_response_map(response, role)}
  end

  def parse_response(%{"role" => role} = response) when is_binary(role) do
    {:ok, normalize_response_map(response, role)}
  end

  def parse_response(response) do
    {:error,
     Error.new(
       :provider_error,
       "Stub response must include a role, got: #{inspect(response)}",
       :stub
     )}
  end

  defp normalize_response_map(response, role) do
    %{
      role: role,
      content: Map.get(response, :content) || Map.get(response, "content") || "",
      tool_calls: Map.get(response, :tool_calls) || Map.get(response, "tool_calls")
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
