defmodule Strukt.Autogenerate do
  @moduledoc false

  # Retain the field-oriented reflection used by parameter normalization.
  def get(module) when is_atom(module) do
    for {fields, mfa} <- groups(module), field <- fields, do: {field, mfa}
  end

  def generate(%module{} = entity) do
    Enum.reduce(groups(module), entity, fn {fields, {m, f, args}}, entity ->
      value = apply(m, f, args)
      Enum.reduce(fields, entity, &Map.put(&2, &1, value))
    end)
  end

  defp groups(module) do
    fields = module.__schema__(:autogenerate)

    case module.__schema__(:autogenerate_id) do
      {field, _source, type} ->
        case id_generator(type) do
          nil -> fields
          mfa -> [{[field], mfa} | fields]
        end

      nil ->
        fields
    end
  end

  defp id_generator(:binary_id), do: {Ecto.UUID, :generate, []}
  defp id_generator(:id), do: nil

  defp id_generator({:parameterized, {module, params}} = type) do
    Code.ensure_loaded!(module)

    if function_exported?(module, :autogenerate, 1),
      do: {module, :autogenerate, [params]},
      else: binary_id_generator(type)
  end

  defp id_generator(module) do
    Code.ensure_loaded!(module)

    if function_exported?(module, :autogenerate, 0),
      do: {module, :autogenerate, []},
      else: binary_id_generator(module)
  end

  defp binary_id_generator(type) do
    if Ecto.Type.type(type) == :binary_id, do: {__MODULE__, :generate_id, [type]}
  end

  @doc false
  def generate_id(type) do
    case Ecto.Type.cast(type, Ecto.UUID.generate()) do
      {:ok, value} -> value
      _ -> raise ArgumentError, "cannot generate an ID for #{inspect(type)}"
    end
  end
end
