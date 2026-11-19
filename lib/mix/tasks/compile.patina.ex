defmodule Mix.Tasks.Compile.Patina do
  @moduledoc """
  Compiles the Patina packages of a Mix project.

  To use Patina compiler, add the following to your `mix.exs`:

      def project do
        [
          # Add `:patina` before `Mix.compilers()`
          compilers: [:patina] ++ Mix.compilers(),

          # Add `:patina_core` to your dependencies.
          # We recommend depending on version `">= 0.0.0"`.
          deps: [{:patina_core, ">= 0.0.0"}],
        ]
      end

  The compiler builds the package for the root-level `Patina.toml`, if it exists,
  and all packages in directories listed under `:patina_packages` configuration key.

  ## Command line options

    * `--force` - forces a clean rebuild.

  ## Configuration

    * `:patina_packages` - directories of the in-tree Patina packages to
        compile, relative to `mix.exs`.  Defaults to `[]`.

  """
  use Mix.Task.Compiler

  alias MixPatina.Package

  @recursive true
  @switches [force: :boolean]

  @impl Mix.Task.Compiler
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)

    if opts[:force] do
      clean()
    end

    package_dirs =
      case Keyword.get(Mix.Project.config(), :patina_packages, []) do
        dirs when is_list(dirs) -> dirs
        other -> Mix.raise(":patina_packages isn't a list: #{inspect(other)}")
      end

    package_dirs =
      if File.regular?("Patina.toml"), do: ["." | package_dirs], else: package_dirs

    with {:ok, packages} <- Package.resolve(package_dirs),
         :ok <- clean_removed(packages),
         do: build(packages)
  end

  @impl Mix.Task.Compiler
  def manifests,
    do: [incremental_dir()]

  @impl Mix.Task.Compiler
  def clean do
    Enum.each(built_package_names(), &clean_package/1)
  end

  defp build(chunks) do
    {status, diagnostics} =
      Enum.reduce_while(chunks, {:ok, []}, fn chunk, {:ok, diagnostics} ->
        opts = build_opts()

        {new_diags, status} =
          chunk
          |> Package.async_stream(&Package.build(&1, opts))
          |> Enum.map_reduce(:ok, fn {status, diags}, acc ->
            {diags, if(status == :ok, do: acc, else: status)}
          end)

        diagnostics = [diagnostics | new_diags]

        case status do
          :ok -> {:cont, {:ok, diagnostics}}
          :error -> {:halt, {:error, diagnostics}}
        end
      end)

    {status, List.flatten(diagnostics)}
  end

  defp build_opts do
    lib = Path.join(Mix.Project.build_path(), "lib")

    lib_dirs =
      lib
      |> Path.join("*/ebin/lib*.rmeta")
      |> Path.wildcard()
      |> Enum.map(&Path.dirname/1)
      |> Enum.uniq()

    [
      root: lib,
      lib_dir: lib_dirs,
      remap_path_prefix: {File.cwd!(), ""},
      out_dir: Mix.Project.compile_path(),
      incremental_dir: incremental_dir()
    ]
  end

  defp clean_removed(packages) do
    names = for chunk <- packages, package <- chunk, into: MapSet.new(), do: package.name

    for name <- built_package_names(), name not in names do
      Mix.shell().info("Cleaning the removed Patina package #{name}")
      clean_package(name)
    end

    :ok
  end

  defp clean_package(name) do
    dir = Path.join(incremental_dir(), name)

    with {:ok, files} <- dir |> Path.join("files") |> File.read() do
      for file <- String.split(files, "\n", trim: true),
          do: Mix.Project.compile_path() |> Path.join(file) |> File.rm()
    end

    File.rm_rf!(dir)
  end

  defp incremental_dir, do: Path.join(Mix.Project.manifest_path(), "compile.patina")

  defp built_package_names do
    case File.ls(incremental_dir()) do
      {:ok, names} -> names
      {:error, _reason} -> []
    end
  end
end
