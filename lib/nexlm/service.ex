defmodule Nexlm.Service do
  alias Nexlm.{Registry, Message}

  def call(model, messages, opts \\ []) do
    registry = Application.get_env(:nexlm, :registry_module, Registry)

    with {:ok, provider} <- registry.get_provider(model),
         {:ok, config} <- provider.init([{:model, model} | opts]),
         {:ok, validated_messages} <- Message.validate_messages(messages),
         {:ok, request} <- provider.format_request(config, validated_messages),
         {:ok, response} <- provider.call(config, request),
         {:ok, result} <- provider.parse_response(response) do
      {:ok, result}
    end
  end
end
