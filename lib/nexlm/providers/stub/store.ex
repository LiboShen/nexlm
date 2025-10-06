defmodule Nexlm.Providers.Stub.Store do
  @moduledoc """
  Per-owner response store backing the stub provider.

  Stubs are registered against the process that enqueues them, and any
  descendant process (via OTP's `:$ancestors` chain) automatically resolves the
  same owner entry. State lives in an ETS table keyed by owner pid so async
  tests stay isolated while still supporting multi-process flows.
  """

  alias Nexlm.Error

  @table __MODULE__

  @type model_name :: String.t()
  @type response_fun :: (Nexlm.Config.t(), map() -> any())

  @spec put(model_name, map() | tuple() | response_fun) :: :ok
  def put(model, response) when is_binary(model) do
    owner = resolve_owner()
    entry = normalize_entry(response)

    with_owner_lock(owner, fn ->
      state = get_state(owner)
      queue = Map.get(state, model, [])
      set_state(owner, Map.put(state, model, queue ++ [entry]))
    end)

    :ok
  end

  @spec put_sequence(model_name, list(map() | tuple() | response_fun)) :: :ok
  def put_sequence(model, responses) when is_binary(model) and is_list(responses) do
    owner = resolve_owner()
    entries = Enum.map(responses, &normalize_entry/1)

    with_owner_lock(owner, fn ->
      state = get_state(owner)
      queue = Map.get(state, model, [])
      set_state(owner, Map.put(state, model, queue ++ entries))
    end)

    :ok
  end

  @spec next_response(model_name, Nexlm.Config.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def next_response(model, config, request) when is_binary(model) do
    owner = resolve_owner()

    with_owner_lock(owner, fn ->
      state = get_state(owner)

      case Map.get(state, model, []) do
        [] ->
          {:error,
           Error.new(
             :provider_error,
             "No stubbed response queued for #{model}",
             :stub,
             %{model: model}
           )}

        [next | rest] ->
          new_state =
            if rest == [],
              do: Map.delete(state, model),
              else: Map.put(state, model, rest)

          set_state(owner, new_state)

          next
          |> handle_entry(config, request)
          |> normalize_result()
      end
    end)
  end

  @spec clear() :: :ok
  def clear do
    owner = resolve_owner()

    with_owner_lock(owner, fn ->
      ensure_table()
      :ets.delete(@table, owner)
    end)

    :ok
  end

  @spec with_stub(model_name, map() | tuple() | response_fun, (-> result)) :: result
        when result: var
  def with_stub(model, response, fun) when is_function(fun, 0) and is_binary(model) do
    owner = resolve_owner()
    entry = normalize_entry(response)

    previous_queue =
      with_owner_lock(owner, fn ->
        state = get_state(owner)
        queue = Map.get(state, model, [])
        set_state(owner, Map.put(state, model, [entry | queue]))
        queue
      end)

    try do
      fun.()
    after
      with_owner_lock(owner, fn ->
        state = get_state(owner)

        restored_state =
          case previous_queue do
            [] -> Map.delete(state, model)
            queue -> Map.put(state, model, queue)
          end

        set_state(owner, restored_state)
      end)
    end
  end

  defp handle_entry({:fun, fun}, config, request) do
    safe_invoke(fun, config, request)
  end

  defp handle_entry(other, _config, _request), do: other

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

  defp resolve_owner do
    ensure_table()

    Process.get(:"$ancestors", [])
    |> Enum.find(fn
      pid when is_pid(pid) ->
        case :ets.lookup(@table, pid) do
          [{^pid, _}] -> true
          _ -> false
        end

      _ ->
        false
    end)
    |> case do
      nil -> self()
      pid -> pid
    end
    |> tap(&ensure_owner_entry/1)
  end

  defp ensure_owner_entry(owner) do
    with_owner_lock(owner, fn ->
      ensure_table()

      case :ets.lookup(@table, owner) do
        [] -> set_state(owner, %{})
        _ -> :ok
      end
    end)
  end

  defp get_state(owner) do
    ensure_table()

    case :ets.lookup(@table, owner) do
      [{^owner, state}] -> state
      [] -> %{}
    end
  end

  defp set_state(owner, state) when map_size(state) == 0 do
    ensure_table()
    :ets.delete(@table, owner)
  end

  defp set_state(owner, state) when is_map(state) do
    ensure_table()
    :ets.insert(@table, {owner, state})
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :public, read_concurrency: true, write_concurrency: true])
        :ok

      _ ->
        :ok
    end
  end

  defp with_owner_lock(owner, fun) do
    :global.trans({@table, owner}, fun)
  end
end
