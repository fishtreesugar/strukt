defmodule Strukt.Params do
  @moduledoc """
    use Ecto.Schema's reflection to map the params.
  """

  def transform(_module, nil = _params, nil = _struct), do: nil
  # def transform(_module = nil, )

  def transform(_module, params, _struct)
      when is_map(params) and map_size(params) == 0,
      do: params

  # Scalar params have no fields to map. Preserve them so Ecto can report the type mismatch
  # instead of treating them as field maps.
  def transform(_module, params, _struct)
      when not is_map(params) and not is_list(params) and not is_nil(params),
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
    params = if is_list(params), do: Map.new(params), else: params

    Map.new(Map.from_struct(struct), fn {field, current} ->
      source = module.__schema__(:field_source, field) || field
      # Struct inputs historically expose source keys; ordinary params also accept schema keys.
      case fetch_param(params, source) do
        {:ok, value} ->
          map_value_to_field(module, field, value, struct)

        :error when is_struct(params) ->
          {field, Map.get(struct, source)}

        :error ->
          case fetch_param(params, field) do
            {:ok, value} -> map_value_to_field(module, field, value, struct)
            :error -> {field, current}
          end
      end
    end)
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
        type = Map.get(params, type_field_name, Map.get(params, to_string(type_field_name)))
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

  @doc false
  def cast_polymorphic_embed(field, changeset) do
    value = changeset.params[to_string(field)]

    case {changeset.types[field], value} do
      {_, nil} ->
        changeset

      {{:array, {:parameterized, {PolymorphicEmbed, opts}}}, values} when is_list(values) ->
        cond do
          not Enum.all?(values, &valid_embed_input?(&1, opts)) ->
            Ecto.Changeset.add_error(changeset, field, "is invalid")

          Enum.any?(values, &is_struct/1) ->
            cast_mixed_embeds(changeset, field, values)

          true ->
            PolymorphicEmbed.cast_polymorphic_embed(changeset, field)
        end

      {{:parameterized, {PolymorphicEmbed, opts}}, %_{} = entity} ->
        if valid_embed_input?(entity, opts) do
          Ecto.Changeset.put_change(changeset, field, entity)
        else
          Ecto.Changeset.add_error(changeset, field, "is invalid")
        end

      {_, params} when is_map(params) and not is_struct(params) ->
        PolymorphicEmbed.cast_polymorphic_embed(changeset, field)

      _ ->
        Ecto.Changeset.add_error(changeset, field, "is invalid")
    end
  end

  defp valid_embed_input?(%module{}, opts),
    do: Enum.any?(opts.types_metadata, &(&1.module == module))

  defp valid_embed_input?(value, _opts), do: is_map(value)

  defp cast_mixed_embeds(changeset, field, values) do
    key = to_string(field)

    result =
      Enum.reduce_while(values, {[], changeset.valid?}, fn
        %_{} = entity, {acc, valid?} ->
          {:cont, {[entity | acc], valid?}}

        params, {acc, valid?} ->
          single = %{changeset | params: Map.put(changeset.params, key, [params])}
          cast = PolymorphicEmbed.cast_polymorphic_embed(single, field)

          if cast.errors != changeset.errors do
            {:halt, {:error, cast.errors}}
          else
            embeds = Ecto.Changeset.get_field(cast, field)
            {:cont, {Enum.reverse(embeds, acc), valid? and cast.valid?}}
          end
      end)

    case result do
      {:error, errors} ->
        %{changeset | errors: errors, valid?: false}

      {reversed, valid?} ->
        Ecto.Changeset.put_change(%{changeset | valid?: valid?}, field, Enum.reverse(reversed))
    end
  end

  defp fetch_param(nil, _field), do: :error

  defp fetch_param(params, field) do
    with :error <- Map.fetch(params, field), do: Map.fetch(params, to_string(field))
  end

  defp get_struct_field_value(struct, field) do
    case struct do
      nil -> nil
      struct -> Map.get(struct, field)
    end
  end
end
