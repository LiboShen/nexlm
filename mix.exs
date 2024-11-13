defmodule Nexlm.MixProject do
  use Mix.Project

  def project do
    [
      app: :nexlm,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # HTTP client
      {:req, "~> 0.4.13"},

      # JSON handling
      {:jason, "~> 1.4"},
      {:ecto, "~> 3.12"},

      # Schema validation
      {:drops, git: "https://github.com/LiboShen/drops.git"}
    ]
  end
end
