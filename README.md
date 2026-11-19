# mix_patina

[![Hex.pm](https://img.shields.io/hexpm/v/mix_patina.svg)](https://hex.pm/packages/mix_patina)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/mix_patina)

Mix utilities to work with Patina code.

To use the Patina compiler, add the following to your `mix.exs`:

```elixir
def project do
  [
    ## Add `:patina` before `Mix.compilers()`
    compilers: [:patina] ++ Mix.compilers(),

    ## Add `:patina_core` to your dependencies.
    ## We recommend depending on version `">= 0.0.0"`.
    deps: [{:patina_core, ">= 0.0.0"}],

    ## A `Patina.toml` beside `mix.exs` is always compiled. `:patina_packages`
    ## names the directories of other in-tree Patina packages. Default: `[]`.
    # patina_packages: ["lib/my_package", "lib/my_helpers"]
  ]
end
```

For multiple Patina packages in the source tree, each is built after its dependencies.
Make sure the dependencies are listed in each `Patina.toml`!
The relationships between the packages of `patina_packages` should be specified as `path` deps:

```toml
[dependencies]
my_helpers = { path = "../my_helpers" }
```

Any other dependency will be resolved from `mix.exs`.

## Installation

The package can be installed as a Mix archive with
`mix archive.install hex mix_patina`, or by adding `mix_patina` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:mix_patina, "~> 0.0.0"}
  ]
end
```

## Installing Patina

After installing `mix_patina`, Patina itself can be installed via a Mix task:

```console
$ mix patina.install
```

It will install Patina into `~/.patina`, which is the default path where it's
expected by Patina build tools. See `mix help patina.install` for details.

## License

Licensed under either of [Apache License, Version 2.0](LICENSE-APACHE) or
[MIT license](LICENSE-MIT).
