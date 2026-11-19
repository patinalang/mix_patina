defmodule Mix.Tasks.Patina.Install do
  @shortdoc "Installs Patina"

  @releases_url "https://github.com/patinalang/patina/releases/download"
  @default_version "nightly"

  @moduledoc """
  Installs Patina into `~/.patina` (`%USERPROFILE%\\.patina` on Windows).

  It defaults to downloading the nightly build for this machine from Patina's
  GitHub releases, and checks it against its SHA-256 checksum. A path or URL
  of a release tarball can be given as an argument instead:

      $ mix patina.install path/to/patina-nightly-aarch64-apple-darwin.tar.gz

  Patina build tools automatically look for `patina` executable within
  `~/.patina`, as a default fallback, so it does not have to be added to `PATH`.

  ## Command line options

    * `PATH|URL` - specifies a path or URL to a release tarball.
      Disables automatic `sha256` verification; pass explicit `--sha256` for checks.

    * `--version VSN` - installs the given release instead of `#{@default_version}`.
      Can't be combined with `PATH|URL`.

    * `--sha256 SHA|PATH|URL` - checks the tarball matches the given SHA-256 checksum.
      Takes the checksum itself, or a path or URL of a `sha256sum`-style checksum file.

    * `--no-check` - skips fetching and checking the published SHA-256 checksum.
      Can't be combined with `--sha256`.

    * `--force` - replaces an existing install without a shell prompt.

    * `--if-missing` - installs only if Patina isn't installed yet.

    * `--install-path PATH` - installs into the given directory instead of `~/.patina`.

  ## Mirrors

  Set the `PATINA_RELEASES_URL` env variable to fetch the builds from a custom
  mirror. The tarball is fetched from
  `$PATINA_RELEASES_URL/VERSION/patina-VERSION-TARGET.tar.gz`.
  A separate `PATINA_RELEASES_SHA256_URL` governs the download of `.sha256` files
  used to verify archive integrity. The checksum file is fetched from
  `$PATINA_RELEASES_SHA256_URL/VERSION/patina-VERSION-TARGET.tar.gz.sha256`.

  Both environment variables default to `#{@releases_url}`.
  """

  use Mix.Task

  @switches [
    force: :boolean,
    version: :string,
    sha256: :string,
    check: :boolean,
    if_missing: :boolean,
    install_path: :string
  ]

  @impl Mix.Task
  def run(argv) do
    {opts, args} = OptionParser.parse!(argv, strict: @switches)

    opts =
      Keyword.validate!(opts,
        force: false,
        version: nil,
        sha256: nil,
        check: true,
        if_missing: false,
        install_path: default_install_root()
      )

    path =
      case args do
        [] -> nil
        [path] -> path
        _ -> Mix.raise("Expected at most one path or URL, got: #{inspect(args)}")
      end

    root =
      case opts[:install_path] do
        nil -> Mix.raise("Can't find the home directory to install into")
        path -> Path.expand(path)
      end

    version =
      case opts[:version] do
        nil -> @default_version
        vsn when args == [] -> vsn
        _ -> Mix.raise("--version can't be combined with a path or URL")
      end

    if not opts[:check] and opts[:sha256] != nil do
      Mix.raise("--no-check can't be combined with --sha256")
    end

    with false <- opts[:if_missing] and File.exists?(root),
         tarball_source = path || tarball_url(version, target_triple()),
         true <- opts[:force] or Mix.Generator.overwrite?(root) do
      sha256 = expected_sha256(args, version, opts)
      tarball = read_path!(tarball_source)
      if sha256, do: check_sha256!(tarball, tarball_source, sha256)
      extract!(tarball, tarball_source, root)
      Mix.shell().info([:green, "* installed ", :reset, "Patina into #{root}"])
    else
      _ -> :ok
    end

    if System.find_executable("patina") == nil do
      bin = Path.join([root, "patina", "bin"])
      Mix.shell().info("To run `patina` from the shell, add #{bin} to your PATH.")
    end
  end

  defp expected_sha256(args, version, opts) do
    cond do
      sha256 = opts[:sha256] ->
        case Base.decode16(sha256, case: :mixed) do
          {:ok, <<_::256>> = bytes} -> bytes
          _ -> read_sha256!(sha256)
        end

      args != [] ->
        nil

      opts[:check] ->
        version |> sha256_url(target_triple()) |> read_sha256!()

      true ->
        Mix.shell().info([:yellow, "* skipping ", :reset, "the SHA-256 check (--no-check)"])
        nil
    end
  end

  defp read_sha256!(path) do
    with [sha256 | _] <- path |> read_path!() |> String.split(),
         {:ok, <<_::256>> = bytes} <- Base.decode16(sha256, case: :mixed),
         do: bytes,
         else: (_ -> Mix.raise("Expected #{path} to start with a SHA-256 checksum"))
  end

  defp read_path!(path) do
    case Mix.Utils.read_path(path) do
      {:ok, binary} ->
        binary

      :badpath ->
        Mix.raise("Expected an existing file or a URL, got `#{inspect(path)}`")

      {kind, message} ->
        Mix.raise("Failed to read #{kind} path `#{path}`: #{message}")
    end
  end

  defp check_sha256!(tarball, path, expected) do
    Mix.ensure_application!(:crypto)

    case :crypto.hash(:sha256, tarball) do
      ^expected ->
        :ok

      actual ->
        Mix.raise("""
        The SHA-256 checksum of #{path} doesn't match.

          Expected: #{Base.encode16(expected, case: :lower)}
          Actual:   #{Base.encode16(actual, case: :lower)}
        """)
    end
  end

  defp extract!(tarball, path, root) do
    tmp = "#{root}.tmp-#{System.pid()}"
    File.rm_rf!(tmp)

    try do
      case :erl_tar.extract({:binary, tarball}, [:compressed, cwd: String.to_charlist(tmp)]) do
        :ok -> :ok
        {:error, e} -> Mix.raise("Could not extract #{path}: #{:erl_tar.format_error(e)}")
      end

      with [top] <- File.ls!(tmp),
           top = Path.join(tmp, top),
           true <- File.dir?(top) do
        File.rm_rf!(root)
        File.rename!(top, root)
        :ok
      else
        _ -> Mix.raise("Expected #{path} to hold a single directory")
      end
    after
      _ = File.rm_rf(tmp)
    end
  end

  # `~/.patina`, or `nil` without a home directory.
  defp default_install_root do
    home =
      case :os.type() do
        {:win32, _} -> System.get_env("USERPROFILE")
        _ -> System.get_env("HOME")
      end

    home && Path.join(home, ".patina")
  end

  defp tarball_url(version, target) do
    mirror_url("PATINA_RELEASES_URL", version, "patina-#{version}-#{target}.tar.gz")
  end

  defp sha256_url(version, target) do
    mirror_url("PATINA_RELEASES_SHA256_URL", version, "patina-#{version}-#{target}.tar.gz.sha256")
  end

  defp mirror_url(env, version, file) do
    base = System.get_env(env, @releases_url)

    case URI.new(base) do
      {:ok, uri} ->
        uri
        |> URI.append_path("/" <> URI.encode(version, &URI.char_unreserved?/1))
        |> URI.append_path("/" <> URI.encode(file, &URI.char_unreserved?/1))
        |> URI.to_string()

      {:error, part} ->
        Mix.raise(
          "Expected #{env} to be a URL, got #{inspect(base)} (invalid at #{inspect(part)})"
        )
    end
  end

  defp target_triple do
    arch = :erlang.system_info(:system_architecture) |> List.to_string()

    case String.split(arch, "-") do
      ["aarch64", "apple", "darwin" <> _ | _] ->
        "aarch64-apple-darwin"

      [cpu, _vendor, "linux", "gnu" | _] when cpu in ["x86_64", "aarch64"] ->
        "#{cpu}-unknown-linux-gnu"

      _ ->
        Mix.raise("There's no Patina build for #{arch}")
    end
  end
end
