defmodule Nexlm.Tool do
  use Elixact

  schema do
    field(:name, :string)

    field :description, :string do
      optional()
    end

    field :parameters, :any do
      optional()
    end
  end
end
