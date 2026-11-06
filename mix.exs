# Modified from upstream by the maintainers of the fishtreesugar/strukt fork.

defmodule Strukt.MixProject do
  use Mix.Project

  @source_url "https://github.com/fishtreesugar/strukt"
  @version "0.4.3"

  def project do
    [
      app: :strukt,
      version: @version,
      elixir: "~> 1.17",
      description: description(),
      package: package(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      name: "Strukt",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: [
        main: "readme",
        source_ref: @version,
        api_reference: false,
        extra_section: "Extras",
        extras: [
          "guides/usage.md",
          "guides/schemas.md",
          "guides/polymorphic-embeds.md",
          "guides/json.md",
          {:"README.md", [title: "About"]},
          {:"LICENSE.md", [title: "License"]}
        ]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: []
    ]
  end

  def cli do
    [
      preferred_envs: [
        docs: :docs,
        "hex.publish": :docs
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto, "~> 3.12"},
      {:polymorphic_embed, "~> 5.0"},
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.40.4", only: [:docs], runtime: false}
    ]
  end

  defp description do
    "Extends defstruct with schemas, changeset validation, and more"
  end

  defp package do
    [
      name: "strukt_fork",
      files: ["lib", "guides", "mix.exs", "README.md", "CHANGELOG.md", "LICENSE.md"],
      maintainers: ["fishtreesugar"],
      licenses: ["Apache-2.0"],
      links: %{
        GitHub: @source_url
      }
    ]
  end
end
