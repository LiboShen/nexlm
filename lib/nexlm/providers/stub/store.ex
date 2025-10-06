defmodule Nexlm.Providers.Stub.Store do
  @moduledoc """
  Per-process response store supporting the stub provider.

  Each async test process maintains its own queue of scripted responses per
  model. Responses can be literal maps, `{:ok, map}`, `{:error, term}`, or
  functions that receive the provider config and request payload.
  """

  alias Nexlm.Error

  @type model_name :: String.t()
  @type response_fun :: (Nexlm.Config.t(), map() -> any())

  @spec put(model_name, map() | tuple() | response_fun) :: :ok
  def put(model, response) when is_binary(model) do
    enqueue(model, normalize_entry(response))
  end

  @spec put_sequence(model_name, list(map() | tuple() | response_fun)) :: :ok
  def put_sequence(model, responses) when is_binary(model) and is_list(responses) do
    normalized = Enum.map(responses, &normalize_entry/1)
    enqueue_many(model, normalized)
  end

  @spec next_response(model_name, Nexlm.Config.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def next_response(model, config, request) when is_binary(model) do
    case pop(model) do
      {:ok, {:fun, fun}} ->
        fun
        |> safe_invoke(config, request)
        |> normalize_result()

      {:ok, tuple} ->
        normalize_result(tuple)

      :empty ->
        {:error,
         Error.new(
           :provider_error,
           "No stubbed response queued for #{model}",
           :stub,
           %{model: model}
         )}
    end
  end

  @spec clear() :: :ok
  def clear do
    Process.delete(key())
    :ok
  end

  @spec with_stub(model_name, map() | tuple() | response_fun, (() -> result)) :: result when result: var
  def with_stub(model, response, fun) when is_function(fun, 0) and is_binary(model) do
    snapshot = Process.get(key(), %{})
    entry = normalize_entry(response)

    override_store = Map.update(snapshot, model, [entry], fn queue -> [entry | queue] end)
    Process.put(key(), override_store)

    try do
      fun.()
    after
      Process.put(key(), snapshot)
    end
  end

  defp enqueue(model, entry) do
    update_store(fn store ->
      Map.update(store, model, [entry], fn queue -> queue ++ [entry] end)
    end)
  end

  defp enqueue_many(model, entries) do
    update_store(fn store ->
      Map.update(store, model, entries, fn queue -> queue ++ entries end)
    end)
  end

  defp pop(model) do
    update_store(fn store ->
      case Map.get(store, model) do
        nil ->
          {:empty, store}

        [] ->
          {:empty, Map.delete(store, model)}

        [next | rest] ->
          new_store = if rest == [], do: Map.delete(store, model), else: Map.put(store, model, rest)
          {{:ok, next}, new_store}
      end
    end)
  end

  defp update_store(fun) do
    key = key()
    store = Process.get(key, %{})

    case fun.(store) do
      {:empty, new_store} ->
        Process.put(key, new_store)
        :empty

      {{:ok, value}, new_store} ->
        Process.put(key, new_store)
        {:ok, value}

      new_store when is_map(new_store) ->
        Process.put(key, new_store)
        :ok
    end
  end

  defp normalize_entry(fun) when is_function(fun, 2), do: {:fun, fun}
  defp normalize_entry({:ok, response}) when is_map(response), do: {:ok, response}
  defp normalize_entry({:error, %Error{} = error}), do: {:error, error}
  defp normalize_entry({:error, reason}), do: {:error, wrap_error(reason)}
  defp normalize_entry(response) when is_map(response), do: {:ok, response}
  defp normalize_entry(other), do: {:error, wrap_error(other)}

  defp normalize_result({:ok, %{role: role} = response}) when is_binary(role), do: {:ok, response}
  defp normalize_result({:ok, response}) when is_map(response), do: {:ok, response}
  defp normalize_result({:error, %Error{} = error}), do: {:error, error}
  defp normalize_result({:error, reason}), do: {:error, wrap_error(reason)}
  defp normalize_result(response) when is_map(response), do: {:ok, response}
  defp normalize_result(other), do: {:error, wrap_error(other)}

  defp safe_invoke(fun, config, request) do
    try do
      fun.(config, request)
    rescue
      error -> {:error, wrap_error(error)}
    catch
      kind, value ->
        {:error, wrap_error({kind, value})}
    end
  end

  defp wrap_error(reason) do
    message = "Stub response error: #{inspect(reason)}"
    Error.new(:provider_error, message, :stub, %{reason: reason})
  end

  defp key do
    {__MODULE__, self()}
  end
end
