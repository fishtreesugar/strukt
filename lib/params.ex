defmodule Strukt.Params do
  @moduledoc """
    use Ecto.Schema's reflection to map the params.
  """

  def transform(_module, nil = _params, nil = _struct), do: nil
  # def transform(_module = nil, )

  def transform(_module, params, _struct)
      when is_map(params) and map_size(params) == 0,
      do: params

  def transform(module, params, nil = _struct) when is_struct(params) do
    transform_from_struct(module, params, params)
  end

  def transform(module, params, nil = _struct) do
    struct =
      struct(module)
      |> Strukt.Autogenerate.generate()

    transform_from_struct(module, params, struct)
  end

  def transform(module, params, struct) when is_struct(struct) do
    transform_from_struct(module, params, struct)
  end

  defp transform(module, params, struct, cardinality: :one) do
    transform(module, params, struct)
  end

  defp transform(module, params, nil = struct, cardinality: :many) when is_list(params) do
    Enum.map(params, fn param ->
      transform(module, param, struct)
    end)
  end

  defp transform(module, params, struct, cardinality: :many) when is_list(params) do
    params
    |> Enum.with_index()
    |> Enum.map(fn {param, index} ->
      transform(module, param, Enum.at(struct, index))
    end)
  end

  # for delay the type error to casting
  defp transform(_module, params, _struct, cardinality: :many), do: params

  defp transform_from_struct(module, params, struct) do
    struct
    |> Map.from_struct()
    |> Enum.map(fn {key, _value} ->
      case module.__schema__(:field_source, key) do
        nil ->
          {key, get_params_field_value(params, key, struct)}

        source_field_name ->
          value = get_params_field_value(params, source_field_name, struct)
          map_value_to_field(module, key, value, struct)
      end
    end)
    |> Map.new()
  end

  defp map_value_to_field(module, field, value, struct) do
    case module.__schema__(:type, field) do
      # since ecto 3.12.0, parameterized type represent as a tuple instead of a triple
      # see https://github.com/elixir-ecto/ecto/commit/21c6068
      {:parameterized,
       {Ecto.Embedded,
        %Ecto.Embedded{
          cardinality: cardinality,
          related: embedded_module
        }}} ->
        {field,
         transform(embedded_module, value, get_struct_field_value(struct, field),
           cardinality: cardinality
         )}

      {:parameterized, {PolymorphicEmbed, _opts}} ->
        {field,
         transform_polymorphic(module, field, value, get_struct_field_value(struct, field))}

      {:array, {:parameterized, {PolymorphicEmbed, _opts}}} ->
        {field,
         transform_polymorphic(module, field, value, get_struct_field_value(struct, field),
           cardinality: :many
         )}

      _type ->
        {field, value}
    end
  end

  defp transform_polymorphic(module, field, params, struct, opts \\ [])

  # Keep nil as-is so required validation and PolymorphicEmbed's own handling can run later.
  defp transform_polymorphic(_module, _field, nil, _struct, _opts), do: nil

  # Struct params have already been cast by the caller, so leave them untouched.
  defp transform_polymorphic(_module, _field, %_{} = params, _struct, _opts), do: params

  # For polymorphic_embeds_many, transform each map using the matching current embed by index.
  # Non-map structs in the list are preserved by the clause above.
  defp transform_polymorphic(module, field, params, struct, cardinality: :many)
       when is_list(params) do
    current = List.wrap(struct)

    params
    |> Enum.with_index()
    |> Enum.map(fn
      {%_{} = param, _index} ->
        param

      {param, index} ->
        transform_polymorphic(module, field, param, Enum.at(current, index))
    end)
  end

  # Map params need the selected polymorphic module before source-field mapping can be applied.
  # If the type cannot be inferred, keep the params unchanged and let cast_polymorphic_embed/3
  # produce the configured error/raise/nilify behavior.
  defp transform_polymorphic(module, field, params, struct, _opts) when is_map(params) do
    case PolymorphicEmbed.get_polymorphic_module(module, field, params) do
      nil ->
        params

      embedded_module ->
        type_field_name = polymorphic_type_field_name(module, field)
        type = get_params_field_value(params, type_field_name, nil)
        struct = polymorphic_struct_for_module(struct, embedded_module)

        embedded_module
        |> transform(params, struct)
        |> maybe_put_polymorphic_type(type_field_name, type)
    end
  rescue
    _ -> params
  end

  # Leave invalid shapes alone so the eventual cast can report the type error.
  defp transform_polymorphic(_module, _field, params, _struct, _opts), do: params

  defp polymorphic_struct_for_module(struct, module) when is_struct(struct, module), do: struct
  defp polymorphic_struct_for_module(_struct, _module), do: nil

  # The type marker must be restored after source-field mapping, otherwise PolymorphicEmbed
  # cannot infer which embedded schema to cast.
  defp polymorphic_type_field_name(module, field) do
    case module.__schema__(:type, field) do
      {:parameterized, {PolymorphicEmbed, opts}} ->
        opts.type_field_name

      {:array, {:parameterized, {PolymorphicEmbed, opts}}} ->
        opts.type_field_name
    end
  end

  defp maybe_put_polymorphic_type(params, _type_field_name, nil), do: params

  defp maybe_put_polymorphic_type(params, type_field_name, type),
    do: Map.put(params, type_field_name, type)

  defp get_params_field_value(nil, _field, _struct), do: nil

  defp get_params_field_value(params, field, struct) when is_list(params) do
    case params[field] do
      nil -> get_struct_field_value(struct, field)
      value -> value
    end
  end

  defp get_params_field_value(params, field, struct) when is_map(params) do
    atom_key_value = Map.get(params, field)
    string_key_value = Map.get(params, field |> to_string())

    case {atom_key_value, string_key_value} do
      {nil, nil} -> get_struct_field_value(struct, field)
      {atom_key_value, nil} -> atom_key_value
      {nil, string_key_value} -> string_key_value
    end
  end

  defp get_struct_field_value(struct, field) do
    case struct do
      nil -> nil
      struct -> Map.get(struct, field)
    end
  end
end
