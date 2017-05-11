defmodule ElixirScript.Mixfile do
  use Mix.Project

  def project do
    [
      app: :elixir_script,
      version: "0.28.0-dev",
      elixir: "~> 1.0",
      elixirc_paths: elixirc_paths(),
      escript: escript_config(),
      deps: deps(),
      description: description(),
      package: package(),
      source_url: "https://github.com/elixirscript/elixirscript",
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls],
      docs: [
        extras: ["GettingStarted.md", "FAQ.md", "Supported.md", "JavaScriptInterop.md"]
      ]
    ]
  end

  def application do
    [
      applications: [:logger, :estree]
    ]
  end

  defp deps do
    [
      {:estree, "~> 2.6"},
      {:fs, "~> 2.12"},
      {:ex_doc, "~> 0.15", only: :dev},
      {:excoveralls, "~> 0.6", only: :test},
      {:credo, "~> 0.7", only: [:dev, :test]},
      {:blueprint, github: "elixirscript/blueprint", only: :test}
    ]
  end

  defp elixirc_paths(), do: ["lib", "priv/std_lib"]

  defp escript_config do
    [main_module: ElixirScript.CLI, name: "elixirscript"]
  end

  defp description do
    """
    ElixirScript: compiles Elixir code to JavaScript
    """
  end

  defp package do
    [
      files: ["lib", "priv/**/*.*", "mix.exs", "README.md", "LICENSE", "CHANGELOG.md"],
      maintainers: ["Bryan Joseph"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/elixirscript/elixirscript"
      },
      build_tools: ["mix"]
    ]
  end

  defp aliases do
    [dist: &dist/1,
     install: &install/1,
     supported: &supported/1]
  end

  def dist(_) do
    Mix.Task.run "app.start"

    dist_folder = "dist"
    folder_name = "#{dist_folder}/elixirscript"
    archive_file_name = "#{dist_folder}/elixirscript.tar.gz"

    Mix.Tasks.Escript.Build.run([])

    if File.exists?(dist_folder) do
      File.rm_rf(dist_folder)
    end

    System.cmd("npm", ["run", "build"])

    File.mkdir_p(folder_name <> "/bin")
    File.cp!("elixirscript", "#{folder_name}/bin/elixirscript")
    if File.exists?("priv/.DS_Store") do
      File.rm!("priv/.DS_Store")
    end
    File.cp_r!("priv/", "#{folder_name}")
    File.cp!("LICENSE", "#{folder_name}/LICENSE")

    System.cmd("tar", ["czf", archive_file_name, folder_name])

    File.rm_rf(folder_name)
  end

  def install(_) do
    Mix.Task.run "app.start"

    System.cmd("tar", ["-zxvf", "dist/elixirscript.tar.gz"])

    File.rm_rf!("/usr/local/elixirscript")

    System.cmd("mv", ["dist/elixirscript", "/usr/local/elixirscript"])

    IO.puts("installed at /usr/local/elixirscript")
  end

  def supported(_) do
    Mix.Task.run "app.start"

    ElixirScript.Gen.Supported.generate()
  end

end
