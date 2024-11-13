defmodule Nexlm.Error do
  @type error_type ::
          :validation_error
          | :provider_error
          | :rate_limit_error
          | :timeout_error
          | :configuration_error

  @type t :: %__MODULE__{
          type: error_type,
          message: String.t(),
          provider: atom(),
          details: map()
        }

  defexception [:type, :message, :provider, :details]

  def new(type, message, provider, details \\ %{}) do
    %__MODULE__{
      type: type,
      message: message,
      provider: provider,
      details: details
    }
  end

  def message(%__MODULE__{} = error) do
    "#{error.provider}: #{error.message}"
  end
end
