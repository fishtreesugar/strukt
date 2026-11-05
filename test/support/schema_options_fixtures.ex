# Modified from upstream by the maintainers of the fishtreesugar/strukt fork.

defmodule Strukt.Test.SchemaOptions.Child do
  use Strukt

  defstruct do
    field(:name, :string)
    field(:note, :string, default: "default")
  end
end

defmodule Strukt.Test.SchemaOptions.NoKey do
  use Strukt
  @primary_key false
  defstruct do
    field(:name, :string)
    field(:note, :string, default: "default")
  end
end

defmodule Strukt.Test.SchemaOptions.BinaryID do
  use Strukt
  @primary_key {:id, :binary_id, autogenerate: true}
  defstruct do
    field(:name, :string)
  end
end

defmodule Strukt.Test.SchemaOptions.CustomID do
  use Ecto.Type
  def type, do: :binary_id
  def cast(v), do: Ecto.UUID.cast(v)
  def load(v), do: Ecto.UUID.load(v)
  def dump(v), do: Ecto.UUID.dump(v)
  def autogenerate, do: Ecto.UUID.generate()
end

defmodule Strukt.Test.SchemaOptions.ParamID do
  use Ecto.ParameterizedType
  def type(_), do: :binary_id
  def init(opts), do: Map.new(opts)
  def cast(nil, _), do: {:ok, nil}
  def cast(v, _), do: Ecto.UUID.cast(v)
  def load(nil, _, _), do: {:ok, nil}
  def load(v, _, _), do: Ecto.UUID.load(v)
  def dump(nil, _, _), do: {:ok, nil}
  def dump(v, _, _), do: Ecto.UUID.dump(v)
  def autogenerate(_), do: Ecto.UUID.generate()
end

defmodule Strukt.Test.SchemaOptions.CustomChild do
  use Strukt
  @primary_key {:id, Strukt.Test.SchemaOptions.CustomID, autogenerate: true}
  defstruct do
    field(:name, :string)
  end
end

defmodule Strukt.Test.SchemaOptions.Parent do
  use Strukt

  defstruct do
    field(:kind, :string)
    embeds_many(:no_keys, Strukt.Test.SchemaOptions.NoKey, on_replace: :delete)

    polymorphic_embeds_one(:one,
      types: [child: Strukt.Test.SchemaOptions.Child],
      on_replace: :update
    )

    polymorphic_embeds_many(:many,
      types: [child: Strukt.Test.SchemaOptions.Child],
      on_replace: :delete
    )

    polymorphic_embeds_one(:custom,
      types: [child: Strukt.Test.SchemaOptions.CustomChild],
      on_replace: :update
    )

    polymorphic_embeds_one(:binary_one,
      types: [child: Strukt.Test.SchemaOptions.BinaryID],
      on_replace: :update
    )

    polymorphic_embeds_many(:binary_many,
      types: [child: Strukt.Test.SchemaOptions.BinaryID],
      on_replace: :delete
    )

    polymorphic_embeds_one(:parent_kind,
      types: [child: Strukt.Test.SchemaOptions.Child],
      use_parent_field_for_type: :kind,
      on_replace: :update
    )
  end
end

defmodule Strukt.Test.SchemaOptions.Counter do
  def next do
    n = Process.get(__MODULE__, 0)
    Process.put(__MODULE__, n + 1)
    DateTime.add(~U[2026-01-01 00:00:00Z], n, :second)
  end
end
