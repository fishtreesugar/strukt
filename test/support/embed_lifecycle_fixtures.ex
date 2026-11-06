defmodule Strukt.Test.Lifecycle.Child do
  use Strukt

  defstruct do
    field(:name, :string, required: true)
    timestamps()
  end
end

defmodule Strukt.Test.Lifecycle.Plain do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  embedded_schema do
    field(:name, :string)
    timestamps()
  end

  def changeset(plain, params), do: cast(plain, params, [:name])
end

defmodule Strukt.Test.Lifecycle.Parent do
  use Strukt

  defstruct do
    field(:email, :string, format: ~r/@/)
    field(:count, :integer)
    embeds_one(:child, Strukt.Test.Lifecycle.Child, on_replace: :update)
    embeds_one(:strict, Strukt.Test.Lifecycle.Child)
    embeds_one(:replaceable, Strukt.Test.Lifecycle.Child, on_replace: :delete)
    embeds_one(:plain, Strukt.Test.Lifecycle.Plain)
    embeds_many(:kids, Strukt.Test.Lifecycle.Child, on_replace: :delete)

    polymorphic_embeds_one(:poly,
      types: [child: Strukt.Test.Lifecycle.Child],
      on_replace: :update,
      on_type_not_found: :ignore
    )

    polymorphic_embeds_many(:polys,
      types: [child: Strukt.Test.Lifecycle.Child],
      on_replace: :delete
    )

    timestamps()
  end
end

defmodule Strukt.Test.Lifecycle.RequiredLists do
  use Strukt

  defstruct do
    embeds_many(:items, Strukt.Test.Lifecycle.Child, required: true, on_replace: :delete)

    polymorphic_embeds_many(:variants,
      types: [child: Strukt.Test.Lifecycle.Child],
      required: [message: "needs a variant"],
      on_replace: :delete
    )
  end
end

defmodule Strukt.Test.Lifecycle.DerivesOnly do
  use Strukt

  @derives [{Jason.Encoder, only: [:name]}, {Inspect, only: [:name]}]
  defstruct do
    field(:name, :string, source: :NAME)
    field(:secret, :string)
  end
end

defmodule Strukt.Test.Lifecycle.DerivesExcept do
  use Strukt

  @derives [{Jason.Encoder, except: [:secret]}]
  defstruct do
    field(:name, :string)
    field(:secret, :string)
  end
end

defmodule Strukt.Test.Lifecycle.DeriveBefore do
  use Strukt

  @derive {Inspect, only: [:name]}
  defstruct do
    field(:name, :string)
    field(:secret, :string)
  end
end

defmodule Strukt.Test.Lifecycle.DerivesBare do
  use Strukt

  @derives Jason.Encoder
  defstruct do
    field(:name, :string)
  end
end
