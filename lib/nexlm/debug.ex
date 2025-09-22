defmodule Nexlm.Debug do
  @moduledoc """
  Debug logging utilities for Nexlm requests and responses.

  Enables detailed logging of HTTP requests and responses to help with debugging
  provider integrations, caching behavior, and other issues.

  ## Configuration

  Enable debug logging in your runtime configuration:

      config :nexlm, :debug, true

  Or set the environment variable:

      NEXLM_DEBUG=true

  ## Log Output

  When enabled, logs will include:
  - Provider being called
  - Full HTTP request (method, URL, headers, body)
  - Full HTTP response (status, headers, body)
  - Request/response timing
  - Any transformations applied to messages

  ## Examples

      # Enable debug logging
      Application.put_env(:nexlm, :debug, true)
      
      # Make a request - will now show detailed logs
      Nexlm.complete("anthropic/claude-3-haiku-20240307", messages)
      
      # Logs will show:
      # [debug] [Nexlm] Provider: anthropic, Model: claude-3-haiku-20240307
      # [debug] [Nexlm] Request: POST https://api.anthropic.com/v1/messages
      # [debug] [Nexlm] Headers: %{"x-api-key" => "[REDACTED]", ...}
      # [debug] [Nexlm] Body: %{model: "claude-3-haiku-20240307", messages: [...]}
      # [debug] [Nexlm] Response: 200 OK (342ms)
      # [debug] [Nexlm] Response Headers: %{"content-type" => "application/json", ...}
      # [debug] [Nexlm] Response Body: %{content: [...], role: "assistant"}
  """

  require Logger

  @doc """
  Check if debug logging is enabled.

  Checks both application configuration and environment variables.
  """
  def enabled? do
    Application.get_env(:nexlm, :debug, false) or
      System.get_env("NEXLM_DEBUG") in ["true", "1", "yes"]
  end

  @doc """
  Log a debug message if debug logging is enabled.
  """
  def log(message) do
    if enabled?() do
      Logger.debug("[Nexlm] #{message}")
    end
  end

  @doc """
  Log request details if debug logging is enabled.
  """
  def log_request(provider, method, url, headers, body) when is_atom(provider) do
    log_request(Atom.to_string(provider), method, url, headers, body)
  end

  def log_request(provider, method, url, headers, body) do
    if enabled?() do
      log("Provider: #{provider}")
      log("Request: #{String.upcase(to_string(method))} #{url}")
      log("Headers: #{inspect(sanitize_headers(headers))}")
      log("Body: #{inspect(body, limit: :infinity, pretty: true)}")
    end
  end

  @doc """
  Log response details if debug logging is enabled.
  """
  def log_response(status, headers, body, duration_ms \\ nil) do
    if enabled?() do
      duration_text = if duration_ms, do: " (#{duration_ms}ms)", else: ""
      log("Response: #{status}#{duration_text}")
      log("Response Headers: #{inspect(sanitize_headers(headers))}")
      log("Response Body: #{inspect(body, limit: :infinity, pretty: true)}")
    end
  end

  @doc """
  Log message transformation if debug logging is enabled.
  """
  def log_transformation(stage, data) do
    if enabled?() do
      log("#{stage}: #{inspect(data, limit: :infinity, pretty: true)}")
    end
  end

  @doc """
  Time a function call and log the duration if debug logging is enabled.
  """
  def time_call(description, fun) do
    if enabled?() do
      start_time = System.monotonic_time(:millisecond)
      result = fun.()
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time
      log("#{description} completed in #{duration}ms")
      result
    else
      fun.()
    end
  end

  # Private helpers

  defp sanitize_headers(headers) when is_list(headers) do
    Enum.map(headers, &sanitize_header/1)
  end

  defp sanitize_headers(headers) when is_map(headers) do
    Map.new(headers, fn {k, v} -> {k, sanitize_header_value(k, v)} end)
  end

  defp sanitize_headers(headers), do: headers

  defp sanitize_header({key, value}) do
    {key, sanitize_header_value(key, value)}
  end

  defp sanitize_header_value(key, value) when is_binary(key) do
    key_lower = String.downcase(key)

    if String.contains?(key_lower, "key") or String.contains?(key_lower, "auth") do
      "[REDACTED]"
    else
      value
    end
  end

  defp sanitize_header_value(_key, value), do: value
end
