defmodule MixPatina.MixProject do
  use Mix.Project

  def project do
    [
      app: :mix_patina,
      version: "0.1.0",
      elixir: "~> 1.18",
      description: "A Mix compiler for Patina packages"
    ]
  end
end
