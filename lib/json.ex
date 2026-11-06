# Modified from upstream by the maintainers of the fishtreesugar/strukt fork.

defmodule Strukt.JSON do
  @moduledoc false

  # Normalize `Jason.Encoder` and `{Jason.Encoder, only: fields}` / `except: fields`
  # entries from `@derives`. Returns nil when no encoder is requested.
  def derive_options(_module, []), do: nil

  def derive_options(module, entries) do
    Enum.reduce(entries, [], fn
      Jason.Encoder, acc ->
        acc

      {Jason.Encoder, opts}, acc ->
        with true <- Keyword.keyword?(opts),
             {selected, []} <- Keyword.split(Keyword.merge(acc, opts), [:only, :except]),
             true <- length(selected) <= 1,
             true <- Enum.all?(selected, fn {_, fields} -> field_list?(fields) end) do
          selected
        else
          _ -> invalid_derive!(module, opts)
        end
    end)
  end

  defp field_list?(fields), do: is_list(fields) and Enum.all?(fields, &is_atom/1)

  defp invalid_derive!(module, opts) do
    raise ArgumentError,
          "invalid Jason.Encoder options in @derives for #{inspect(module)}, expected " <>
            "`only: fields` or `except: fields` with a list of field names, got: #{inspect(opts)}"
  end

  def check_derive_fields!(module, opts, struct) do
    for {key, fields} <- opts,
        unknown = Enum.reject(fields, &Map.has_key?(struct, &1)),
        unknown != [] do
      raise ArgumentError,
            "`#{inspect(key)}` in @derives for #{inspect(module)} specifies fields " <>
              "that are not defined in the schema: #{inspect(unknown)}"
    end

    :ok
  end

  # Use Ecto's dump callbacks and schema source names, while retaining Strukt's
  # explicit-nil key semantics for polymorphic values at any nesting depth.
  # `only`/`except` apply to this struct; nested embeds are dumped in full.
  def dump(%module{} = entity, opts \\ []) do
    module.__schema__(:fields)
    |> select_fields(opts)
    |> Map.new(fn field ->
      type = module.__schema__(:type, field)
      value = Map.fetch!(entity, field)

      case dump_value(type, value) do
        {:ok, value} ->
          {module.__schema__(:field_source, field), value}

        :error ->
          raise ArgumentError,
                "cannot dump #{inspect(value)} for field #{inspect(field)} in #{inspect(module)}"
      end
    end)
  end

  defp select_fields(fields, only: only), do: Enum.filter(fields, &(&1 in only))
  defp select_fields(fields, except: except), do: Enum.reject(fields, &(&1 in except))
  defp select_fields(fields, _opts), do: fields

  defp dump_value(
         {:parameterized, {PolymorphicEmbed, _}} = type,
         %Ecto.Changeset{valid?: true} = cs
       ),
       do: dump_value(type, Ecto.Changeset.apply_changes(cs))

  defp dump_value({:parameterized, {PolymorphicEmbed, _}}, %Ecto.Changeset{valid?: false}),
    do: raise("cannot dump invalid changeset")

  defp dump_value({:parameterized, {PolymorphicEmbed, opts}}, %module{} = entity) do
    case Enum.find(opts.types_metadata, &(&1.module == module)) do
      %{type: type} -> {:ok, Map.put(dump(entity), opts.type_field_name, type)}
      nil -> :error
    end
  end

  defp dump_value(type, value) do
    case Ecto.Type.embed_as(type, :json) do
      :self -> {:ok, value}
      :dump -> Ecto.Type.dump(type, value, &dump_value/2)
    end
  end
end
