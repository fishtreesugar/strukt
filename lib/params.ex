# Modified from upstream by the maintainers of the fishtreesugar/strukt fork.

defmodule Strukt.Params do
  @moduledoc """
    use Ecto.Schema's reflection to map the params.
  """

  def transform(_module, nil = _params, nil = _struct), do: nil

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

    generated = Map.take(struct, Enum.map(Strukt.Autogenerate.get(module), &elem(&1, 0)))
    Map.merge(generated, transform_from_struct(module, params, struct))
  end

  def transform(module, params, struct) when is_struct(struct) do
    transform_from_struct(module, params, struct)
  end

  # Preserve explicit nil, including invalid nil elements inside embed lists.
  defp transform(_module, nil, _struct, cardinality: :one), do: nil

  defp transform(module, params, struct, cardinality: :one) do
    formed = transform(module, params, struct)

    # Keep the existing embed identity without submitting its other fields for recasting.
    if is_map(formed) and is_struct(struct) do
      Map.merge(Map.take(struct, module.__schema__(:primary_key)), formed)
    else
      formed
    end
  end

  defp transform(module, params, struct, cardinality: :many) when is_list(params) do
    current = List.wrap(struct)

    params
    |> Enum.with_index()
    |> Enum.map(fn {param, index} ->
      transform(module, param, Enum.at(current, index), cardinality: :one)
    end)
  end

  # Delay invalid shapes until casting can return a field error.
  defp transform(_module, params, _struct, cardinality: :many), do: params

  defp transform_from_struct(module, params, struct) do
    params = if is_list(params), do: Map.new(params), else: params

    Enum.reduce(Map.from_struct(struct), %{}, fn {field, _current}, acc ->
      source = module.__schema__(:field_source, field) || field

      value =
        case fetch_param(params, source) do
          :error -> fetch_param(params, field)
          found -> found
        end

      case value do
        {:ok, value} ->
          {field, value} = map_value_to_field(module, field, value, struct)
          Map.put(acc, field, value)

        :error ->
          acc
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
  def cast_embed(changeset, field) do
    # Ecto casts relations against changeset.data. Reuse pending embedded values when
    # updating an existing changeset so a second partial update does not discard them.
    if Map.has_key?(changeset.changes, field) do
      current = Ecto.Changeset.get_field(changeset, field)
      {:embed, %{cardinality: cardinality}} = changeset.types[field]

      with_callback =
        case cardinality do
          :one ->
            fn fresh, params -> cast_pending_embed(fresh, params, current) end

          :many ->
            fn fresh, params, index ->
              cast_pending_embed(fresh, params, Enum.at(List.wrap(current), index))
            end
        end

      Ecto.Changeset.cast_embed(changeset, field, with: with_callback)
    else
      Ecto.Changeset.cast_embed(changeset, field)
    end
  end

  defp cast_pending_embed(%module{} = fresh, params, current) do
    same_identity? =
      is_struct(current, module) and
        Enum.all?(Ecto.primary_key(current), fn {key, value} ->
          case fetch_param(params, key) do
            {:ok, param} -> Ecto.Type.cast(module.__schema__(:type, key), param) == {:ok, value}
            :error -> is_nil(value)
          end
        end)

    module.changeset(if(same_identity?, do: current, else: fresh), params)
  end

  @doc false
  def clear_embed(changeset, field) do
    {:embed, %{cardinality: cardinality}} = changeset.types[field]
    empty = if cardinality == :many, do: [], else: nil
    Ecto.Changeset.put_embed(changeset, field, empty)
  end

  @doc false
  def cast_polymorphic_embed(field, changeset) do
    case Map.fetch(changeset.params || %{}, to_string(field)) do
      :error -> changeset
      {:ok, value} -> cast_polymorphic_value(changeset, field, value)
    end
  end

  defp cast_polymorphic_value(changeset, field, value) do
    case {changeset.types[field], value} do
      {{:array, _}, nil} ->
        Ecto.Changeset.put_change(changeset, field, [])

      {_, nil} ->
        Ecto.Changeset.put_change(changeset, field, nil)

      {{:array, {:parameterized, {PolymorphicEmbed, opts}}}, values} when is_list(values) ->
        cond do
          not Enum.all?(values, &valid_embed_input?(&1, opts)) ->
            Ecto.Changeset.add_error(changeset, field, "is invalid")

          Enum.any?(values, &is_struct/1) or
              Ecto.Changeset.get_field(changeset, field) not in [nil, []] ->
            cast_mixed_embeds(changeset, field, values, opts)

          true ->
            PolymorphicEmbed.cast_polymorphic_embed(changeset, field)
        end

      {{:parameterized, {PolymorphicEmbed, opts}}, %_{} = entity} ->
        if valid_embed_input?(entity, opts) do
          Ecto.Changeset.put_change(changeset, field, entity)
        else
          Ecto.Changeset.add_error(changeset, field, "is invalid")
        end

      {{:parameterized, {PolymorphicEmbed, opts}}, params}
      when is_map(params) and not is_struct(params) ->
        current = Ecto.Changeset.get_field(changeset, field)
        callbacks = polymorphic_callbacks(opts, current)
        PolymorphicEmbed.cast_polymorphic_embed(changeset, field, with: callbacks)

      {_, params} when is_map(params) and not is_struct(params) ->
        PolymorphicEmbed.cast_polymorphic_embed(changeset, field)

      _ ->
        Ecto.Changeset.add_error(changeset, field, "is invalid")
    end
  end

  defp valid_embed_input?(%module{}, opts),
    do: Enum.any?(opts.types_metadata, &(&1.module == module))

  defp valid_embed_input?(value, _opts), do: is_map(value)

  defp cast_mixed_embeds(changeset, field, values, opts) do
    key = to_string(field)
    current = List.wrap(Ecto.Changeset.get_field(changeset, field))

    result =
      values
      |> Enum.with_index()
      |> Enum.reduce_while({[], changeset.valid?}, fn
        {%_{} = entity, _index}, {acc, valid?} ->
          {:cont, {[entity | acc], valid?}}

        {params, index}, {acc, valid?} ->
          single = %{changeset | params: Map.put(changeset.params, key, [params])}

          # Params are matched by position during transformation. Supply that same data
          # to casting instead of filling omitted params with values that would be recast.
          callbacks = polymorphic_callbacks(opts, Enum.at(current, index))
          cast = PolymorphicEmbed.cast_polymorphic_embed(single, field, with: callbacks)

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

  defp polymorphic_callbacks(opts, current) do
    Enum.map(opts.types_metadata, fn %{type: type, module: module} ->
      {type,
       fn fresh, params ->
         data = polymorphic_struct_for_module(current, module) || fresh
         module.changeset(data, params)
       end}
    end)
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
