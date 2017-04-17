defmodule ElixirScript.Translator.Defmodule do
  @moduledoc false
  alias ESTree.Tools.Builder, as: JS
  alias ElixirScript.Translator
  alias ElixirScript.Translator.State
  alias ElixirScript.Translator.Utils
  alias ElixirScript.Translator.Group
  alias ElixirScript.Translator.Def
  alias ElixirScript.Translator.Identifier

  def make_module(ElixirScript.Temp, body, env) do
    { body, _ } = translate_body(body, env)
    %{
      name: ElixirScript.Temp,
      body: body |> Group.inflate_groups,
      exports: nil,
      app_name: ElixirScript.Translator.State.get(env.state).compiler_opts.app,
      env: env
    }
  end

  def make_module(module, nil, env) do
    %{
      name: module,
      body: [],
      exports: nil,
      app_name: ElixirScript.Translator.State.get(env.state).compiler_opts.app,
      env: env
    }
  end

  def make_module(module, body, env) do
    {body, exported_object} = process_module(module, body, env)
    app_name = State.get_module(env.state, module).app

    result = %{
        name: Utils.quoted_to_name({:__aliases__, [], module }),
        exports: exported_object,
        body: body,
        app_name: app_name,
        env: env
    }

    result
  end

  def process_module(module, body, env) do
    { body, functions } = extract_functions_from_module(body)

    { body, env } = translate_body(body, env)

    { exported_functions, private_functions } = process_functions(functions, env)

    struct_prop = if has_struct?(body) do
      [JS.property(Identifier.make_identifier("__struct__"), Identifier.make_identifier("__struct__"), :init, true)]
    else
      []
    end

    info_prop = [JS.property(Identifier.make_identifier("__info__"), Identifier.make_identifier("__info__"), :init, true)]

    body = Enum.map(body, fn(x) ->
      case x do
        %ESTree.CallExpression{} ->
          JS.expression_statement(x)
        _ ->
          x
      end
    end)

    body = Group.inflate_groups(body)

    exported_object = JS.object_expression(
      info_prop ++ struct_prop ++
      Enum.map(exported_functions, fn({key, _value}) ->
        JS.property(Identifier.make_identifier(key), Identifier.make_identifier(key), :init, true)
      end)
    )

    exported_functions = Enum.map(exported_functions, fn({_key, value}) -> value end)
    private_functions = Enum.map(private_functions, fn({_key, value}) -> value end)

    body = private_functions ++ exported_functions ++ [make_info_function(env)] ++ body
    {body, exported_object}
  end

  def translate_body(body, env) do
    { body, env } = Translator.translate(body, env)

    body = case body do
      [%ESTree.BlockStatement{ body: body }] ->
        body
      %ESTree.BlockStatement{ body: body } ->
        body
      _ ->
        List.wrap(body)
    end

    { body, env }
  end

  def extract_functions_from_module({:__block__, meta, body_list}) do
    { body_list, functions } = Enum.map_reduce(body_list,
      %{exported: Map.new(), private: Map.new(), exported_generators: Map.new(), private_generators: Map.new()}, fn
        ({:def, _, [{:when, _, [{name, _, _} | _guards] }, _] } = function, state) ->
          {
            nil,
            %{ state | exported: Map.put(state.exported, name, Map.get(state.exported, name, []) ++ [function]) }
          }
        ({:def, _, [{name, _, _}, _]} = function, state) ->
          {
            nil,
            %{ state | exported: Map.put(state.exported, name, Map.get(state.exported, name, []) ++ [function]) }
          }
        ({:defp, _, [{:when, _, [{name, _, _} | _guards] }, _] } = function, state) ->
          {
            nil,
            %{ state | private: Map.put(state.private, name, Map.get(state.private, name, []) ++ [function]) }
          }
        ({:defp, _, [{name, _, _}, _]} = function, state) ->
          {
            nil,
            %{ state | private: Map.put(state.private, name, Map.get(state.private, name, []) ++ [function]) }
          }
        ({:defgen, _, [{:when, _, [{name, _, _} | _guards] }, _] } = function, state) ->
          {
            nil,
            %{ state | exported_generators: Map.put(state.exported_generators, name, Map.get(state.exported_generators, name, []) ++ [function]) }
          }
        ({:defgen, _, [{name, _, _}, _]} = function, state) ->
          {
            nil,
            %{ state | exported_generators: Map.put(state.exported_generators, name, Map.get(state.exported_generators, name, []) ++ [function]) }
          }
        ({:defgenp, _, [{:when, _, [{name, _, _} | _guards] }, _] } = function, state) ->
          {
            nil,
            %{ state | private_generators: Map.put(state.private_generators, name, Map.get(state.private_generators, name, []) ++ [function]) }
          }
        ({:defgenp, _, [{name, _, _}, _]} = function, state) ->
          {
            nil,
            %{ state | private_generators: Map.put(state.private_generators, name, Map.get(state.private_generators, name, []) ++ [function]) }
          }
        (x, state) ->
          { x, state }
      end)

    body_list = Enum.filter(body_list, fn(x) -> !is_nil(x) end)
    body = {:__block__, meta, body_list}

    { body, functions }
  end

  def extract_functions_from_module(body) do
    extract_functions_from_module({:__block__, [], List.wrap(body)})
  end

  def extract_imports_from_body(body) do
    Enum.partition(body, fn(x) ->
      case x do
        %ESTree.ImportDeclaration{} ->
          true
        _ ->
          false
      end
    end)
  end

  def has_struct?(body) do
    val = Enum.find(body, fn(x) ->
      case x do
        %ESTree.VariableDeclaration{declarations: [%ESTree.VariableDeclarator{id: %ESTree.Identifier{name: "__struct__"} } ] } ->
          true
        _ ->
          false
      end
    end)

    val != nil
  end

  defp make_defstruct_property(_, []) do
    []
  end

  defp make_defstruct_property(module_name, [the_struct]) do
    module_js_name = Utils.name_to_js_name(module_name)

    case the_struct do
      %ESTree.VariableDeclaration{declarations: [%ESTree.VariableDeclarator{id: %ESTree.Identifier{name: ^module_js_name} } ] } ->
        [JS.property(JS.identifier(module_js_name), JS.identifier(module_js_name), :init, true)]
    end
  end

  def process_functions(%{ exported: exported, private: private, exported_generators: exported_generators, private_generators: private_generators }, env) do
    exported_functions = Enum.map(Map.keys(exported), fn(key) ->
      functions = Map.get(exported, key)

      { functions, _ } = Def.process_function(key, functions, env)
      { key, functions }
    end)

    exported_generators = Enum.map(Map.keys(exported_generators), fn(key) ->
      functions = Map.get(exported_generators, key)

      { functions, _ } = Def.process_function(key, functions, %{ env | context: :generator})
      { key, functions }
    end)

    private_functions = Enum.map(Map.keys(private), fn(key) ->
      functions = Map.get(private, key)
      { functions, _ } = Def.process_function(key, functions, env)
      { key, functions }
    end)

    private_generators = Enum.map(Map.keys(private_generators), fn(key) ->
      functions = Map.get(private_generators, key)
      { functions, _ } = Def.process_function(key, functions, %{ env | context: :generator})
      { key, functions }
    end)

    { exported_functions ++ exported_generators, private_functions ++ private_generators }
  end

  def make_attribute(name, value, env) do
    declarator = JS.variable_declarator(
      Identifier.make_identifier(name),
      ElixirScript.Translator.translate!(value, env)
    )

    JS.variable_declaration([declarator], :const)
  end

  def make_info_function(env) do
    functions = Keyword.get(env.functions, env.module, [])
    macros = Keyword.get(env.macros, env.module, [])

    info_case = quote do
      case kind do
        :functions ->
          unquote(functions)
        :macros ->
          unquote(macros)
        :module ->
          unquote(env.module)
      end
    end

    translated_case = ElixirScript.Translator.translate!(info_case, env)

    declarator = JS.variable_declarator(
      Identifier.make_identifier("__info__"),
      JS.function_expression(
        [JS.identifier("kind")],
        [],
        JS.block_statement([
          JS.return_statement(translated_case)
        ])
      )
    )

    JS.variable_declaration([declarator], :const)    
    
  end

end
