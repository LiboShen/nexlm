defmodule Nexlm.Behaviour do
  alias Nexlm.{Config, Error}

  @type message :: %{
          role: String.t(),
          content: String.t() | list(map())
        }

  @type tool_definition :: %{
          name: String.t(),
          description: String.t(),
          parameters: %{
            type: String.t(),
            properties: map(),
            required: [String.t()]
          }
        }

  @type tool_call :: %{
          id: String.t(),
          name: String.t(),
          arguments: map()
        }

  @type tool_result :: %{
          id: String.t(),
          result: any()
        }

  @callback init(Keyword.t()) :: {:ok, Config} | {:error, Error.t()}

  @callback validate_messages(list(message)) :: :ok | {:error, Error.t()}

  @callback format_request(Config, list(message)) ::
              {:ok, map()} | {:error, Error.t()}

  @callback call(Config, map()) ::
              {:ok, map()} | {:error, Error.t()}

  @callback parse_response(map()) ::
              {:ok, message} | {:error, Error.t()}
end
