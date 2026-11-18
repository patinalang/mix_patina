# mix_patina

Mix utilities to work with Patina code.

To use Patina compiler, add the following to your `mix.exs`:

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

The package can be installed by through `mix archive.install hex mix_patina`,
or adding `mix_patina` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:mix_patina, "~> 0.1.0"}
  ]
end
```
