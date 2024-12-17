defmodule Nexlm.Config do
  use Elixact

  schema do
    field(:model, :string)

    field :temperature, :float do
      gteq(0.0)
      default(0.0)
    end

    field :max_tokens, :integer do
      optional()
      gt(0)
    end

    field :top_p, :float do
      gteq(0.0)
      lteq(1.0)
      optional()
    end

    field :tools, {:array, Nexlm.Tool} do
      default([])
    end

    field :receive_timeout, :integer do
      default(300_000)
    end

    field :retry_count, :integer do
      default(3)
    end

    field :retry_delay, :integer do
      default(1000)
    end
  end

  def new(opts \\ [])

  def new(opts) when is_list(opts) do
    opts |> Map.new() |> new()
  end

  def new(opts) when is_map(opts) do
    opts |> validate()
  end
end
