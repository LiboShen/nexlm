defmodule Nexlm.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/LiboShen/nexlm"
  @description "A unified interface for interacting with various Large Language Model (LLM) providers"

  def project do
    [
      app: :nexlm,
      version: @version,
      elixir: "~> 1.17",
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

      # JSON handling
      {:jason, "~> 1.4"},
      {:ecto, "~> 3.12"},

      # Schema validation with a fix haven't push to upstream.
      {:drops, git: "https://github.com/LiboShen/drops.git"},

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
