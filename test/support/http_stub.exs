defmodule Test.Support.HTTPStub do
  @moduledoc false
  @behaviour Nexlm.HTTPClient

  @impl true
  def post(url, opts) do
    case Process.get(key()) do
      nil -> raise "No HTTP stub configured for #{inspect(url)}"
      fun -> fun.(url, opts)
    end
  end

  def put(fun) when is_function(fun, 2) do
    Process.put(key(), fun)
    :ok
  end

  def put(response) do
    put(fn _, _ -> response end)
  end

  def reset do
    Process.delete(key())
  end

  defp key do
    {__MODULE__, self()}
  end
end
