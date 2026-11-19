defmodule MixPatina.Package do
  @moduledoc false

  alias Mix.Task.Compiler

  @manifest "Patina.toml"

  @enforce_keys [:name, :dir]
  defstruct [:name, :dir, deps: []]

  @type t :: %__MODULE__{name: String.t(), dir: Path.t(), deps: [String.t()]}

  @spec resolve([Path.t()]) :: {:ok, [[t()]]} | {:error, [Compiler.Diagnostic.t()]}
  def resolve(dirs) do
    dirs
    |> Enum.map(&Path.expand/1)
    |> Enum.uniq()
    |> async_stream(&read_manifest/1)
    |> Enum.reduce({:ok, []}, fn
      _, {:error, reason} -> {:error, reason}
      {:error, reason}, _ -> {:error, reason}
      {:ok, package}, {:ok, packages} -> {:ok, [package | packages]}
    end)
    |> case do
      {:ok, packages} -> {:ok, order_dep_chunks(packages)}
      {:error, reason} -> {:error, reason}
    end
  end

  def async_stream(enumerable, fun) do
    enumerable
    |> Task.async_stream(
      fn element ->
        try do
          {:ok, fun.(element)}
        rescue
          exception -> {:raise, exception, __STACKTRACE__}
        end
      end,
      timeout: :infinity
    )
    |> Stream.map(fn
      {:ok, {:ok, result}} -> result
      {:ok, {:raise, exception, stacktrace}} -> reraise exception, stacktrace
    end)
  end

  def build(%__MODULE__{} = package, opts) do
    patina(:build, opts, dir: package.dir, emit: [:meta, :beam])
  end

  defp read_manifest(dir) do
    case patina(:print, [[:package, :dependencies]], [], dir: dir) do
      {:ok, %{package: %{name: name}, dependencies: deps}} ->
        {:ok, %__MODULE__{name: name, dir: dir, deps: Enum.map(deps, & &1.name)}}

      {:error, _diagnostics} = error ->
        Mix.shell().error(
          "== Error reading #{Path.relative_to_cwd(Path.join(dir, @manifest))} =="
        )

        error
    end
  end

  # Returns chunks of packages. Each chunk depends only on the previous ones,
  # so it can be built in parallel.
  defp order_dep_chunks(packages) do
    by_name = Map.new(packages, &{&1.name, &1})

    with_digraph(fn graph ->
      Enum.each(packages, &:digraph.add_vertex(graph, &1.name))

      for package <- packages, dep <- package.deps, Map.has_key?(by_name, dep) do
        # An edge goes from a package to one it depends on.
        :digraph.add_edge(graph, package.name, dep)
      end

      with [[package | _] | _] <- :digraph_utils.cyclic_strong_components(graph) do
        cycle = graph |> :digraph.get_short_cycle(package) |> Enum.join(" -> ")
        Mix.raise("Patina packages depend on each other in a cycle: #{cycle}")
      end

      graph |> topsort_chunks() |> Enum.map(fn chunk -> Enum.map(chunk, &by_name[&1]) end)
    end)
  end

  defp topsort_chunks(graph, acc \\ []) do
    case :digraph.sink_vertices(graph) do
      [] ->
        Enum.reverse(acc)

      sinks ->
        :digraph.del_vertices(graph, sinks)
        topsort_chunks(graph, [sinks | acc])
    end
  end

  defp with_digraph(fun) do
    graph = :digraph.new()

    try do
      fun.(graph)
    after
      :digraph.delete(graph)
    end
  end

  defp patina(command, args \\ [], opts, extra_opts)
       when command in [:build, :print] do
    opts = opts ++ extra_opts
    args = args ++ [opts]

    with {status, [_ | _] = diagnostics} <- apply(:patina, command, args) do
      for %{rendered: rendered} when is_binary(rendered) <- diagnostics,
          do: IO.write(:stderr, rendered)

      dir = Keyword.get_lazy(opts, :dir, &File.cwd!/0)
      mixed_diagnostics = Enum.map(diagnostics, &to_mix_diagnostic(&1, dir))

      {status, mixed_diagnostics}
    end
  catch
    :error, %{__struct__: :patina_error} = error ->
      error |> Exception.message() |> String.trim_trailing() |> Mix.raise()
  end

  defp to_mix_diagnostic(diag, package_dir) do
    message =
      Enum.join([diag.message | Enum.map(diag.children, &"#{&1.level}: #{&1.message}")], "\n")

    {file, position, span} =
      case Enum.find(diag.spans, & &1.is_primary) do
        nil ->
          {Path.join(package_dir, "Patina.toml"), 0, nil}

        span ->
          {Path.expand(span.file_name), {span.line_start, span.column_start},
           {span.line_end, span.column_end}}
      end

    severity =
      case diag.level do
        :error -> :error
        :internal_compiler_error -> :error
        :warning -> :warning
        _ -> :information
      end

    %Compiler.Diagnostic{
      file: file,
      source: file,
      severity: severity,
      message: message,
      position: position,
      span: span,
      compiler_name: "Patina",
      details: diag
    }
  end
end
