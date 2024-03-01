defmodule Pepper.HTTP.MixProject do
  use Mix.Project

  def project do
    [
      app: :pepper_http,
      version: "0.7.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      elixirc_options: [
        warnings_as_errors: true,
      ],
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      package: package(),
      source_url: "https://github.com/Tychron/pepper_http",
      homepage_url: "https://github.com/Tychron/pepper_http",
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def elixirc_paths(:test), do: ["lib", "test/support"]
  def elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Parse accept headers
      {:accept, "~> 0.3.5"},
      # Needed for some utility functions
      {:plug, "~> 1.6"},
      # JSON Parser
      {:jason, "~> 1.2"},
      # XML Decoder / Encoder
      {:saxy, "~> 1.5"},
      # CSV
      {:csv, "~> 2.0 or ~> 3.0"},
      # HTTP Library
      {:mint, "~> 1.0"},
      # Certificate Store
      {:castore, "~> 0.1 or ~> 1.0"},
      {:bypass, "~> 1.0 or ~> 2.1", [only: :test]},
    ]
  end

  defp package do
    [
      maintainers: ["Tychron Developers <developers@tychron.co>"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/Tychron/pepper_http"
      },
    ]
  end
end
