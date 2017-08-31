defmodule ElixirScript.Output do
  @moduledoc false

  alias ElixirScript.State, as: ModuleState
  alias ESTree.Tools.{Builder, Generator}
  @generated_name "elixirscript.build.js"

  @doc """
  Takes outputs the JavaScript code in the specified output
  """
  @spec execute([atom], pid) :: nil
  def execute(modules, pid) do
    modules = modules
    |> Enum.filter(fn {_, info} -> Map.has_key?(info, :js_ast) end)
    |> Enum.map(fn {_module, info} ->
        info.js_ast
      end
    )

    opts = ModuleState.get_compiler_opts(pid)

    js_modules = ModuleState.js_modules(pid)
    |> Enum.filter(fn
      {_module, _name, nil} -> false
      _ -> true
    end)
    |> Enum.map(fn
      {module, name, path} ->
        import_path = Path.join(opts.root, path)
        {module, name, path, import_path}
    end)

    bundle(modules, opts, js_modules)
    |> output(Map.get(opts, :output), js_modules)
  end

  defp bundle(modules, opts, js_modules) do
    modules
    |> ElixirScript.Output.JSModule.compile(opts, js_modules)
    |> List.wrap
    |> Builder.program
    |> prepare_js_ast
    |> Generator.generate
    |> concat
  end

  defp concat(code) do
    bootstrap_code = get_bootstrap_js()
    "'use strict';\nexport #{bootstrap_code}\n#{code}"
  end

  defp get_bootstrap_js() do
    operating_path = Path.join([Mix.Project.build_path, "lib", "elixir_script", "priv"])
    path = Path.join([operating_path, "build", "iife", "ElixirScript.Core.js"])
    File.read!(path)
  end

  defp prepare_js_ast(js_ast) do
    case js_ast do
      modules when is_list(modules) ->
        modules
        |> Enum.reduce([], &(&2 ++ &1.body))
        |> Builder.program
      _ ->
        js_ast
    end
  end

  defp output(code, nil, _) do
     code
  end

  defp output(code, :stdout, _) do
    IO.puts(code)
  end

  defp output(code, path, js_modules) do
    file_name = get_output_file_name(path)

    if !File.exists?(Path.dirname(file_name)) do
      File.mkdir_p!(Path.dirname(file_name))
    end

    apps = get_app_names()
    output_dir = Path.dirname(file_name)
    Enum.each(js_modules, fn({_, _, path, _}) ->
      copy_javascript_module(apps, output_dir, path)
    end)

    File.write!(file_name, code)
  end

  def get_output_file_name(path) do
    case Path.extname(path) do
      ".js" ->
        path
      ".mjs" ->
        path
      _ ->
        Path.join([path, @generated_name])
    end
  end

  defp get_app_names() do
    Mix.Project.config()[:app]
    deps = Mix.Project.deps_paths()
    |> Map.keys

    [Mix.Project.config()[:app]] ++ deps
  end

  defp copy_javascript_module(apps, output_dir, js_module_path) do
    Enum.each(apps, fn(app) ->
      base_path = Path.join([:code.priv_dir(app), "elixir_script"])

      js_input_path = cond do
        File.exists?(Path.join([base_path, js_module_path])) ->
          Path.join([base_path, js_module_path])
        File.exists?(Path.join([base_path, slashes_to_dots(js_module_path)])) ->
          Path.join([base_path, slashes_to_dots(js_module_path)])
        true ->
          nil
      end

      if js_input_path != nil do
        js_output_path = Path.join(output_dir, js_module_path)
        js_output_dir = Path.dirname(js_output_path)
        if !File.exists?(js_output_dir) do
          File.mkdir_p!(js_output_dir)
        end

        File.cp(js_input_path, js_output_path)
      end
    end)
  end

  defp slashes_to_dots(js_module_path) do
    js_module_path
    |> String.replace("/", ".")
  end
end
