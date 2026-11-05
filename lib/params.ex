# Modified from upstream by the maintainers of the fishtreesugar/strukt fork.

defmodule Strukt.Params do
  @moduledoc """
    use Ecto.Schema's reflection to map the params.
  """

  def transform(_module, nil = _params, nil = _struct), do: nil

  # Scalar params have no fields to map. Preserve them so Ecto can report the type mismatch
  # instead of treating them as field maps.
  def transform(_module, params, _struct)
      when not is_map(params) and not is_list(params) and not is_nil(params),
      do: params

  def transform(module, params, struct) when is_list(params) do
    if Keyword.keyword?(params), do: transform(module, Map.new(params), struct), else: params
  end

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
      selected = current_embed(module, param, current, index, :source)
      transform(module, param, selected, cardinality: :one)
    end)
  end

  defp transform(module, params, struct, cardinality: :many)
       when is_map(params) and not is_struct(params) do
    transform(module, indexed_values(params), struct, cardinality: :many)
  end

  # Delay invalid shapes until casting can return a field error.
  defp transform(_module, params, _struct, cardinality: :many), do: params

  defp transform_from_struct(module, params, struct) do
    Enum.reduce(Map.from_struct(struct), %{}, fn {field, _current}, acc ->
      value = fetch_field_param(module, params, field, :source)

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

  defp transform_polymorphic(module, field, params, struct, cardinality: :many)
       when is_map(params) do
    transform_polymorphic(module, field, indexed_values(params), struct, cardinality: :many)
  end

  # Select each map's current data by primary key, or by position when no key is supplied.
  # Already-cast structs in the list are preserved.
  defp transform_polymorphic(module, field, params, struct, cardinality: :many)
       when is_list(params) do
    current = List.wrap(struct)

    params
    |> Enum.with_index()
    |> Enum.map(fn
      {%_{} = param, _index} ->
        param

      {param, index} ->
        selected =
          if is_map(param) do
            case PolymorphicEmbed.get_polymorphic_module(module, field, param) do
              nil -> nil
              embedded_module -> current_embed(embedded_module, param, current, index, :source)
            end
          end

        transform_polymorphic(module, field, param, selected)
    end)
  end

  # Normalize maps using their inferred variant, or the current single embed for partial updates.
  # Without either context, leave type-not-found handling to PolymorphicEmbed.
  defp transform_polymorphic(module, field, params, struct, _opts) when is_map(params) do
    inferred = PolymorphicEmbed.get_polymorphic_module(module, field, params)
    struct = embedded_data(struct)
    current_module = if is_struct(struct), do: struct.__struct__

    case inferred || current_module do
      nil ->
        params

      embedded_module ->
        type_field_name = polymorphic_type_field_name(module, field)

        type =
          Map.get(params, type_field_name, Map.get(params, to_string(type_field_name))) ||
            if(inferred, do: PolymorphicEmbed.get_polymorphic_type(module, field, inferred))

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
    {:embed, relation} = changeset.types[field]
    values = Map.get(changeset.params, to_string(field))

    if relation.cardinality == :many do
      values =
        if is_map(values) and not is_struct(values), do: indexed_values(values), else: values

      values = if is_list(values), do: Enum.map(values, &keyword_params/1), else: values

      if is_list(values) and Enum.any?(values, &is_list/1) do
        Ecto.Changeset.add_error(changeset, field, "is invalid",
          validation: :embed,
          type: {:array, :map}
        )
      else
        %{changeset | params: Map.put(changeset.params, to_string(field), values)}
        |> do_cast_embed(field, relation, values)
        |> Map.put(:params, changeset.params)
      end
    else
      do_cast_embed(changeset, field, relation, values)
    end
  end

  defp do_cast_embed(changeset, field, relation, values) do
    struct_inputs? =
      relation.cardinality == :many and is_list(values) and Enum.any?(values, &is_struct/1)

    pending? = Map.has_key?(changeset.changes, field)

    # Ecto casts relations against changeset.data. Reuse pending embedded values when
    # updating an existing changeset so a second partial update does not discard them.
    if pending? or struct_inputs? do
      current = Ecto.Changeset.get_field(changeset, field)

      with_callback =
        case relation.cardinality do
          :one ->
            fn fresh, params ->
              cast_pending_embed(fresh, params, current, relation.on_replace == :update)
            end

          :many ->
            fn fresh, params, index ->
              case Enum.at(values, index) do
                %_{} = entity ->
                  Ecto.Changeset.change(entity)

                _ when pending? ->
                  selected = current_embed(fresh.__struct__, params, List.wrap(current), index)
                  cast_pending_embed(fresh, params, selected)

                _ ->
                  fresh.__struct__.changeset(fresh, params)
              end
            end
        end

      if struct_inputs? do
        if Enum.all?(values, &(not is_struct(&1) or is_struct(&1, relation.related))) do
          params =
            Enum.map(values, fn
              %_{} = entity -> Map.from_struct(entity)
              params -> params
            end)

          %{changeset | params: Map.put(changeset.params, to_string(field), params)}
          |> Ecto.Changeset.cast_embed(field, with: with_callback)
          |> Map.put(:params, changeset.params)
        else
          Ecto.Changeset.add_error(changeset, field, "is invalid",
            validation: :embed,
            type: {:array, :map}
          )
        end
      else
        Ecto.Changeset.cast_embed(changeset, field, with: with_callback)
      end
    else
      Ecto.Changeset.cast_embed(changeset, field)
    end
  end

  defp keyword_params(params) when is_list(params) do
    if Keyword.keyword?(params), do: Map.new(params), else: params
  end

  defp keyword_params(params), do: params

  defp cast_pending_embed(%module{}, params, current, update? \\ false) do
    same_identity? =
      is_struct(current, module) and
        (update? or
           Enum.all?(Ecto.primary_key(current), fn {key, value} ->
             case fetch_param(params, key) do
               {:ok, param} ->
                 Ecto.Type.cast(module.__schema__(:type, key), param) == {:ok, value}

               :error ->
                 is_nil(value)
             end
           end))

    module.changeset(if(same_identity?, do: current, else: struct(module)), params)
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
      {{:array, _}, values} when is_map(values) and not is_struct(values) ->
        cast_polymorphic_value(changeset, field, indexed_values(values))

      {{:array, _}, nil} ->
        Ecto.Changeset.put_change(changeset, field, [])

      {_, nil} ->
        Ecto.Changeset.put_change(changeset, field, nil)

      {{:array, {:parameterized, {PolymorphicEmbed, opts}}}, values} when is_list(values) ->
        if Enum.all?(values, &valid_embed_input?(&1, opts)) do
          cast_polymorphic_many(changeset, field, values, opts)
        else
          Ecto.Changeset.add_error(changeset, field, "is invalid")
        end

      {{:parameterized, {PolymorphicEmbed, opts}}, %_{} = entity} ->
        if valid_embed_input?(entity, opts) do
          Ecto.Changeset.put_change(changeset, field, entity)
        else
          Ecto.Changeset.add_error(changeset, field, "is invalid")
        end

      {{:parameterized, {PolymorphicEmbed, _opts}}, params}
      when is_map(params) and not is_struct(params) ->
        cast_polymorphic_one(changeset, field)

      _ ->
        Ecto.Changeset.add_error(changeset, field, "is invalid")
    end
  end

  defp valid_embed_input?(%module{}, opts),
    do: Enum.any?(opts.types_metadata, &(&1.module == module))

  defp valid_embed_input?(value, _opts), do: is_map(value)

  defp cast_polymorphic_one(changeset, field) do
    # The dependency selects a single embed's type and data from changeset.data.
    # Cast against the effective value, then record the result against the original data.
    current = changeset |> Ecto.Changeset.get_field(field) |> embedded_data()

    working = %{
      changeset
      | data: Map.put(changeset.data, field, current),
        changes: Map.delete(changeset.changes, field)
    }

    cast = PolymorphicEmbed.cast_polymorphic_embed(working, field)
    value = Ecto.Changeset.get_field(cast, field)
    Ecto.Changeset.put_change(%{cast | data: changeset.data}, field, value)
  end

  defp cast_polymorphic_many(changeset, field, values, opts) do
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

          # Use the same identity matching as transformation, without recasting omitted fields.
          callbacks = polymorphic_callbacks(opts, current, index)
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

  defp polymorphic_callbacks(opts, current, index) do
    Enum.map(opts.types_metadata, fn %{type: type, module: module} ->
      {type,
       fn _fresh, params ->
         data = current_embed(module, params, current, index) || struct(module)
         module.changeset(data, params)
       end}
    end)
  end

  # Explicit keys must never fall back to another entry's position, even if the key
  # is nil, invalid, incomplete, or does not match any current entry.
  defp current_embed(module, params, current, index, key_mode \\ :field) do
    params = if is_list(params) and Keyword.keyword?(params), do: Map.new(params), else: params
    keys = module.__schema__(:primary_key)
    supplied = Enum.map(keys, &{&1, fetch_field_param(module, params, &1, key_mode)})
    current = Enum.map(current, &embedded_data/1)

    if Enum.any?(supplied, fn {_key, result} -> result != :error end) do
      identity =
        Enum.map(supplied, fn {key, result} ->
          value =
            case result do
              {:ok, value} -> Ecto.Type.cast(module.__schema__(:type, key), value)
              :error -> :error
            end

          {key, value}
        end)

      Enum.find(current, fn candidate ->
        is_struct(candidate, module) and
          Enum.all?(identity, fn
            {key, {:ok, value}} when not is_nil(value) -> Map.get(candidate, key) == value
            _ -> false
          end)
      end)
    else
      polymorphic_struct_for_module(Enum.at(current, index), module)
    end
  end

  defp fetch_field_param(_module, %_{} = params, field, :source),
    do: fetch_param(params, field)

  defp fetch_field_param(module, params, field, :source) do
    source = module.__schema__(:field_source, field) || field

    case fetch_param(params, source) do
      :error -> fetch_param(params, field)
      found -> found
    end
  end

  defp fetch_field_param(_module, params, field, :field), do: fetch_param(params, field)

  defp embedded_data(%Ecto.Changeset{} = changeset), do: Ecto.Changeset.apply_changes(changeset)
  defp embedded_data(value), do: value

  # Match Ecto's indexed-map ordering, including numeric strings such as "2" and "10".
  defp indexed_values(params) do
    params
    |> Enum.map(fn
      {key, value} when is_binary(key) and byte_size(key) < 32 ->
        case Integer.parse(key) do
          {index, ""} -> {index, value}
          _ -> {key, value}
        end

      entry ->
        entry
    end)
    |> Enum.sort()
    |> Enum.map(&elem(&1, 1))
  end

  defp fetch_param(params, _field) when not is_map(params), do: :error

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
