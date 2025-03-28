defmodule Nexlm.Registry do
  @providers %{
    "anthropic" => Nexlm.Providers.Anthropic,
    "openai" => Nexlm.Providers.OpenAI,
    "google" => Nexlm.Providers.Google,
    "groq" => Nexlm.Providers.Groq
  }

  def get_provider(model) when is_binary(model) do
    case String.split(model, "/", parts: 2) do
      [provider, _model] ->
        case Map.get(@providers, provider) do
          nil -> {:error, :unknown_provider}
          module -> {:ok, module}
        end

      _ ->
        {:error, :invalid_model_format}
    end
  end

  def list_providers, do: Map.keys(@providers)
end
