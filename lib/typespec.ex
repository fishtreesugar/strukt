defmodule Strukt.Typespec do
  @moduledoc false

  defstruct [:caller, :info, :fields, :embeds]

  @type t :: %__MODULE__{
          # The module where the struct is being defined
          caller: module,
          # Metadata about all fields in the struct
          info: %{optional(atom) => map},
          # A list of all non-embed field names
          fields: [atom],
          # A list of all embed field names
          embeds: [atom]
        }

  @empty_meta %{type: nil, value_type: nil, required: false, default: nil}

  @doc """
  Given a description of a struct definition, this function produces AST which
  represents a typespec definition for that struct.

  For example, given a struct definition like so:

      defstruct Foo do
        field :uuid, Ecto.UUID, primary_key: true
        field :name, :string
        field :age, :integer
      end

  This function would produce a typespec definition equivalent to:

      @type t :: %Foo{
        uuid: Ecto.UUID.t,
        name: String.t,
        age: integer
      }

  ## Struct Description

  The description contains a few fields, whose values are sourced based on the following:


  * `info` - A map of every field for which we have validation metadata
  * `fields` - This is a list of all field names which are defined via `field/3`
  * `embeds` - This is a list of all field names which are defined via `embeds_one/3` or `embeds_many/3`
  """
  def generate(%__MODULE__{caller: caller, info: info, fields: fields, embeds: embeds}) do
    # Build up the AST for each field's type spec
    fields =
      fields
      |> Stream.map(fn name -> {name, Map.get(info, name, @empty_meta)} end)
      |> Enum.map(fn {name, meta} ->
        required? = Map.get(meta, :required) == true
        default_value = Map.get(meta, :default)
        type_name = type_to_type_name(meta.value_type)

        type_spec =
          if required? or not is_nil(default_value) do
            type_name
          else
            nilable(type_name)
          end

        {name, type_spec}
      end)

    # Do the same for embeds_one/embeds_many
    embeds =
      embeds
      |> Enum.map(fn name -> {name, Map.fetch!(info, name)} end)
      |> Enum.map(fn
        {name, %{type: :embeds_one, value_type: type} = meta} ->
          required? = Map.get(meta, :required) == true
          type_name = compose_call(type, :t, [])

          if required? do
            {name, type_name}
          else
            {name, nilable(type_name)}
          end

        {name, %{type: :embeds_many, value_type: type}} ->
          {name, List.wrap(compose_call(type, :t, []))}
      end)

    # Join all fields together
    struct_fields = fields ++ embeds

    quote(context: caller, do: @type(t :: %__MODULE__{unquote_splicing(struct_fields)}))
  end

  defp primitive(atom, args \\ []) when is_atom(atom) and is_list(args),
    do: {atom, [], args}

  defp map(elements) when is_list(elements),
    do: {:%{}, [], elements}

  defp map(elements) when is_map(elements),
    do: {:%{}, [], Map.to_list(elements)}

  defp compose_call(module, function, args) when is_atom(module) and is_list(args),
    do: {{:., [], [{:__aliases__, [alias: false], [module]}, function]}, [], args}

  defp compose_call({:__aliases__, _, _} = module, function, args) when is_list(args),
    do: {{:., [], [module, function]}, [], args}

  defp nilable(type_name), do: {:|, [], [type_name, nil]}

  defp type_to_type_name(:id), do: primitive(:non_neg_integer)
  defp type_to_type_name(:binary_id), do: primitive(:binary)
  defp type_to_type_name(:integer), do: primitive(:integer)
  defp type_to_type_name(:float), do: primitive(:float)
  defp type_to_type_name(:decimal), do: compose_call(Decimal, :t, [])
  defp type_to_type_name(:boolean), do: primitive(:boolean)
  defp type_to_type_name(:string), do: compose_call(String, :t, [])
  defp type_to_type_name(:binary), do: primitive(:binary)
  defp type_to_type_name(:uuid), do: compose_call(Ecto.UUID, :t, [])

  defp type_to_type_name({:array, type}), do: [type_to_type_name(type)]

  defp type_to_type_name(:map), do: primitive(:map)

  defp type_to_type_name({:map, type}) do
    element_type = type_to_type_name(type)
    map([{element_type, element_type}])
  end

  defp type_to_type_name(t) when t in [:utc_datetime_usec, :utc_datetime],
    do: compose_call(DateTime, :t, [])

  defp type_to_type_name(t) when t in [:naive_datetime_usec, :naive_datetime],
    do: compose_call(NaiveDateTime, :t, [])

  defp type_to_type_name(t) when t in [:time_usec, :time],
    do: compose_call(Time, :t, [])

  defp type_to_type_name(:date),
    do: compose_call(Date, :t, [])

  defp type_to_type_name(mod) when is_atom(mod) and not is_nil(mod) do
    case mod do
      Ecto.Enum ->
        primitive(:atom)

      Ecto.UUID ->
        compose_call(Ecto.UUID, :t, [])

      mod ->
        if defines_module_type?(mod) do
          compose_call(module_alias_ast(mod), :t, [])
        else
          # Fall back to the underlying Ecto type when available, rather than
          # relying on debug info being present in the BEAM to discover `t/0`.
          ecto_type_to_type_name(mod) || primitive(:any)
        end
    end
  end

  defp type_to_type_name(_), do: primitive(:any)

  defp defines_module_type?(mod) do
    module_defines_type?(mod) or docs_define_type?(mod) or beam_defines_type?(mod)
  end

  defp module_defines_type?(mod) do
    Module.defines_type?(mod, {:t, 0})
  rescue
    ArgumentError -> false
  end

  defp docs_define_type?(mod) do
    case Code.fetch_docs(mod) do
      {:docs_v1, _, _, _, _, _, docs} ->
        Enum.any?(docs, &match?({{:type, :t, 0}, _, _, _, _}, &1))

      _ ->
        false
    end
  end

  defp beam_defines_type?(mod) do
    case Code.Typespec.fetch_types(mod) do
      {:ok, mod_types} ->
        Enum.any?(
          mod_types,
          &match?({kind, {:t, _, args}} when kind in [:type, :opaque] and length(args) == 0, &1)
        )

      _ ->
        false
    end
  end

  defp ecto_type_to_type_name(mod) do
    with {:module, _} <- Code.ensure_loaded(mod),
         true <- function_exported?(mod, :type, 0) do
      mod.type()
      |> type_to_type_name()
    else
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp module_alias_ast(mod) do
    {:__aliases__, [alias: false], Enum.map(Module.split(mod), &String.to_atom/1)}
  end
end
