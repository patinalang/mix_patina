defmodule MixPatina.MixProject do
  use Mix.Project

  @source_url "https://github.com/patinalang/mix_patina"

  def project do
    [
      app: :mix_patina,
      description: "A Mix compiler for Patina packages",
      version: "0.0.0",
      elixir: "~> 1.18",
      deps: deps(),
      aliases: aliases(),
      package: package(),
      dialyzer: dialyzer()
    ] ++ docs()
  end

  defp deps do
    [
      {:ex_doc, "~> 0.40", only: :dev, runtime: false, optional: true},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false, optional: true}
    ]
  end

  defp docs do
    [
      name: "mix_patina",
      source_url: @source_url,
      homepage_url: "https://github.com/patinalang/patina",
      docs: [
        main: "readme",
        extras: [
          "README.md": [title: "Overview"],
          "LICENSE-APACHE": [title: "License (Apache-2.0)"],
          "LICENSE-MIT": [title: "License (MIT)"]
        ]
      ]
    ]
  end

  defp package do
    [
      links: %{"GitHub" => @source_url},
      licenses: ["Apache-2.0", "MIT"],
      files: [
        ".formatter.exs",
        "lib",
        "LICENSE-APACHE",
        "LICENSE-MIT",
        "mix.exs",
        "README.md"
      ]
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:mix, :crypto]
    ]
  end

  defp aliases do
    [
      lint: ["dialyzer"]
    ]
  end
end
