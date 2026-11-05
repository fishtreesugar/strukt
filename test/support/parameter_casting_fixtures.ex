# Modified from upstream by the maintainers of the fishtreesugar/strukt fork.

defmodule Strukt.Test.ParameterCasting.Child do
  use Strukt

  defstruct do
    field(:name, :string, source: :NAME)
    field(:note, :string, default: "default")
  end
end

defmodule Strukt.Test.ParameterCasting.Parent do
  use Strukt

  defstruct do
    embeds_one(:child, Strukt.Test.ParameterCasting.Child, on_replace: :update)
    embeds_many(:children, Strukt.Test.ParameterCasting.Child, on_replace: :delete)

    polymorphic_embeds_one(:poly,
      types: [child: Strukt.Test.ParameterCasting.Child],
      on_replace: :update
    )

    polymorphic_embeds_many(:polys,
      types: [child: Strukt.Test.ParameterCasting.Child],
      on_replace: :delete
    )
  end
end

defmodule Strukt.Test.ParameterCasting.Collision do
  use Strukt

  defstruct do
    field(:a, :string, source: :b)
    field(:b, :string, source: :c)
  end
end
