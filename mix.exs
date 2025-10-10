defmodule Nexlm.MixProject do
  use Mix.Project

  @version "0.1.15"
  @source_url "https://github.com/LiboShen/nexlm"
  @description "A unified interface for interacting with various Large Language Model (LLM) providers"

  def project do
    [
      app: :nexlm,
      version: @version,
      elixir: "~> 1.14",
      name: "Nexlm",
      description: @description,
      source_url: @source_url,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      # HTTP client
      {:req, "~> 0.5"},

      # Schema validation
      {:elixact, "~> 0.1.0"},

      # Development dependencies
      {:ex_doc, "~> 0.31.0", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_url: @source_url,
      source_ref: "v#{@version}",
      formatters: ["html"]
    ]
  end

  defp package do
    [
      name: :nexlm,
      maintainers: ["Libo Shen"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Docs" => "https://hexdocs.pm/nexlm"
      }
    ]
  end
end
