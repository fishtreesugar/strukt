# Modified from upstream by the maintainers of the fishtreesugar/strukt fork.

defmodule Strukt.Test.ParameterCasting.Child do
  use Strukt

  defstruct do
    field(:name, :string, source: :NAME)
    field(:note, :string, default: "default")
  end
end

defmodule Strukt.Test.ParameterCasting.RequiredChild do
  use Strukt

  defstruct do
    field(:name, :string, required: true)
  end
end

defmodule Strukt.Test.ParameterCasting.Parent do
  use Strukt

  defstruct do
    field(:title, :string)
    embeds_one(:child, Strukt.Test.ParameterCasting.Child, on_replace: :update)
    embeds_many(:children, Strukt.Test.ParameterCasting.Child, on_replace: :delete)

    embeds_many(:required_children, Strukt.Test.ParameterCasting.RequiredChild,
      on_replace: :delete
    )

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

defmodule Strukt.Test.ParameterCasting.CollisionParent do
  use Strukt

  defstruct do
    embeds_one(:child, Strukt.Test.ParameterCasting.Collision, on_replace: :update)
  end
end

defmodule Strukt.Test.ParameterCasting.Collision do
  use Strukt

  defstruct do
    field(:a, :string, source: :b)
    field(:b, :string, source: :c)
  end
end

defmodule Strukt.Test.ParameterCasting.Foreign do
  defstruct [:name]
end

defmodule Strukt.Test.ParameterCasting.Email do
  use Strukt
  @primary_key false
  defstruct do
    field(:address, :string, required: true)
  end
end

defmodule Strukt.Test.ParameterCasting.SMS do
  use Strukt
  @primary_key false
  defstruct do
    field(:number, :string, required: true)
  end
end

defmodule Strukt.Test.ParameterCasting.ParentType do
  use Strukt

  defstruct do
    field(:kind, :string)

    polymorphic_embeds_one(:payload,
      types: [email: Strukt.Test.ParameterCasting.Email, sms: Strukt.Test.ParameterCasting.SMS],
      use_parent_field_for_type: :kind,
      on_replace: :update
    )
  end
end
