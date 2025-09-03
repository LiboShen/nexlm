defmodule Nexlm.Service do
  alias Nexlm.{Debug, Registry, Message}

  def call(model, messages, opts \\ []) do
    Debug.log("Starting request for model: #{model}")
    Debug.log_transformation("Input messages", messages)
    Debug.log("Options: #{inspect(opts)}")

    registry = Application.get_env(:nexlm, :registry_module, Registry)

    Debug.time_call("Complete request", fn ->
      with {:ok, provider} <- registry.get_provider(model),
           {:ok, config} <- provider.init([{:model, model} | opts]),
           {:ok, validated_messages} <- Message.validate_messages(messages),
           {:ok, request} <- provider.format_request(config, validated_messages),
           {:ok, response} <- provider.call(config, request),
           {:ok, result} <- provider.parse_response(response) do
        Debug.log_transformation("Final result", result)
        {:ok, result}
      else
        {:error, error} = err ->
          Debug.log("Request failed with error: #{inspect(error)}")
          err
      end
    end)
  end
end
