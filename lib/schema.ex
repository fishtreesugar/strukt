# Modified from upstream by the maintainers of the fishtreesugar/strukt fork.

defmodule Strukt.Schema do
  @moduledoc false

  @field_context [:schema_redact, :field_source_mapper, :timestamps_opts, :foreign_key_type]

  def register(module) do
    Module.register_attribute(module, :strukt_definitions, accumulate: true)
  end

  # Functions may construct their own struct, which does not exist until Ecto has
  # built the schema. Capture their lexical environment and attribute values now.
  def defer(module, ast, env) do
    Module.put_attribute(module, :strukt_definitions, {capture_attributes(ast, env), env})
  end

  def defer_attribute(module, name, value, meta, env) do
    ast = {:@, meta, [{name, meta, [Macro.escape(value)]}]}
    Module.put_attribute(module, :strukt_definitions, {ast, env})
  end

  def emit_definitions(module) do
    module
    |> Module.get_attribute(:strukt_definitions)
    |> Enum.reverse()
    |> Enum.each(fn {ast, env} -> Code.eval_quoted(ast, [], env) end)

    Module.delete_attribute(module, :strukt_definitions)
  end

  def capture_attributes(ast, env), do: capture(ast, env, [])

  defp capture({:@, _, [{name, _, context}]}, env, []) when is_atom(context) do
    env.module |> Module.get_attribute(name) |> Macro.escape()
  end

  defp capture({:__aliases__, _, _} = ast, env, []), do: Macro.expand(ast, env)

  defp capture({:quote, meta, args}, env, nesting) do
    args =
      Enum.map(args, fn opts ->
        Enum.map(opts, fn
          {:do, body} -> {:do, body}
          {key, value} -> {key, capture(value, env, nesting)}
        end)
      end)

    opts = List.flatten(args)
    enabled? = Keyword.get(opts, :unquote, not Keyword.has_key?(opts, :bind_quoted))

    args =
      Enum.map(args, fn opts ->
        Enum.map(opts, fn
          {:do, body} -> {:do, capture(body, env, [enabled? | nesting])}
          other -> other
        end)
      end)

    {:quote, meta, args}
  end

  defp capture({unquote, meta, args}, env, [true | nesting])
       when unquote in [:unquote, :unquote_splicing],
       do: {unquote, meta, Enum.map(args, &capture(&1, env, nesting))}

  defp capture({name, meta, args}, env, nesting) when is_list(args),
    do: {capture(name, env, nesting), meta, Enum.map(args, &capture(&1, env, nesting))}

  defp capture({left, right}, env, nesting),
    do: {capture(left, env, nesting), capture(right, env, nesting)}

  defp capture(list, env, nesting) when is_list(list),
    do: Enum.map(list, &capture(&1, env, nesting))

  defp capture(other, _env, _nesting), do: other

  def field(module, name, value_type, type, options) do
    options = if type == :timestamps, do: List.first(options) || [], else: options
    {validations, options} = Strukt.Field.split_options(options)

    field = %{name: name, value_type: value_type, options: options, context: context(module)}

    if type != :timestamps do
      metadata =
        Map.merge(
          %{
            type: type,
            value_type: value_type,
            default: options[:default],
            types: options[:types]
          },
          Map.new(validations)
        )

      Module.put_attribute(
        module,
        :validated_fields,
        Map.put(Module.get_attribute(module, :validated_fields), name, metadata)
      )
    end

    field
  end

  def context(module) do
    for key <- @field_context do
      {key, Module.has_attribute?(module, key), Module.get_attribute(module, key)}
    end
  end

  def restore_context(module, context) do
    for {key, present?, value} <- context do
      if present?,
        do: Module.put_attribute(module, key, value),
        else: Module.delete_attribute(module, key)
    end
  end
end
