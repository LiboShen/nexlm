defmodule Nexlm.Behaviour do
  alias Nexlm.{Config, Error}

  @type message :: %{
          role: String.t(),
          content: String.t() | list(map())
        }

  @callback init(Keyword.t()) :: {:ok, Config.t()} | {:error, Error.t()}

  @callback validate_messages(list(message)) :: :ok | {:error, Error.t()}

  @callback format_request(Config.t(), list(message)) ::
              {:ok, map()} | {:error, Error.t()}

  @callback call(Config.t(), map()) ::
              {:ok, map()} | {:error, Error.t()}

  @callback parse_response(map()) ::
              {:ok, message} | {:error, Error.t()}
end
