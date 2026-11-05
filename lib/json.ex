# Modified from upstream by the maintainers of the fishtreesugar/strukt fork.

defmodule Strukt.JSON do
  @moduledoc false

  # Use Ecto's dump callbacks and schema source names, while retaining Strukt's
  # explicit-nil key semantics for polymorphic values at any nesting depth.
  def dump(%module{} = entity) do
    Map.new(module.__schema__(:fields), fn field ->
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
