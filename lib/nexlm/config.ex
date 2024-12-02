defmodule Nexlm.Config do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  embedded_schema do
    field(:model, :string)
    field(:temperature, :float, default: 0.0)
    field(:max_tokens, :integer)
    field(:top_p, :float)
    field(:tools, {:array, :map}, default: [])
    field(:receive_timeout, :integer, default: 300_000)
    field(:retry_count, :integer, default: 3)
    field(:retry_delay, :integer, default: 1000)
  end

  def new(opts \\ []) do
    %__MODULE__{}
    |> cast(Map.new(opts), __schema__(:fields))
    |> validate_required([:model])
    |> validate_number(:temperature, greater_than_or_equal_to: 0)
    |> validate_number(:max_tokens, greater_than: 0)
    |> validate_number(:top_p, greater_than: 0, less_than_or_equal_to: 1)
    |> apply_action(:insert)
  end
end
