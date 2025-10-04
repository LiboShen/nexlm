defmodule Nexlm.HTTPClient do
  @moduledoc """
  Behaviour describing the contract used by Nexlm provider HTTP clients.

  Custom implementations should mimic the tuple return shape produced by
  `Req.post/2`, returning either `{:ok, response}` or `{:error, reason}`.
  """

  @callback post(String.t(), keyword()) :: {:ok, map()} | {:error, map()}
end

defmodule Nexlm.HTTPClient.Req do
  @moduledoc """
  Default client that delegates to `Req.post/2`.
  """
  @behaviour Nexlm.HTTPClient

  @impl true
  def post(url, opts), do: Req.post(url, opts)
end

defmodule Nexlm.HTTP do
  @moduledoc """
  Thin wrapper that dispatches HTTP calls through the configured client.

  Override `:nexlm, :http_client` to plug in a custom implementation (for
  example in tests).
  """

  @spec post(String.t(), keyword()) :: {:ok, map()} | {:error, map()}
  def post(url, opts \\ []) do
    client().post(url, opts)
  end

  defp client do
    Application.get_env(:nexlm, :http_client, Nexlm.HTTPClient.Req)
  end
end
