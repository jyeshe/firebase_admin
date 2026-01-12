defmodule FirebaseAdmin.MixProject do
  use Mix.Project

  def project do
    [
      app: :firebase_admin,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Firebase Admin SDK for Elixir",
      package: package(),
      elixirc_paths: elixirc_paths(Mix.env()),
      docs: docs()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:integration_test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger, :inets, :ssl, :crypto]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.4"},
      {:joken, "~> 2.6"},
      {:goth, "~> 1.4"},
      {:jason, "~> 1.4"},
      {:plug, ">= 0.0.0"},
      {:mox, "~> 1.0", only: :test},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/yourusername/firebase_admin"}
    ]
  end

  defp docs do
    [
      main: "FirebaseAdmin",
      extras: ["README.md"]
    ]
  end
end
