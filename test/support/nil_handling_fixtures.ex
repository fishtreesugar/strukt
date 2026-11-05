# Modified from upstream by the maintainers of the fishtreesugar/strukt fork.

defmodule Strukt.Test.NilChild do
  use Strukt

  defstruct do
    field(:name, :string, source: :NAME)
    field(:note, :string, default: "default")
  end
end

defmodule Strukt.Test.NilParent do
  use Strukt

  defstruct do
    field(:name, :string, default: "default")
    field(:optional, :string, default: "optional", required: false)
    field(:label, :string, source: :LABEL)
    embeds_one(:one, Strukt.Test.NilChild, on_replace: :delete)
    embeds_many(:many, Strukt.Test.NilChild, on_replace: :delete)
    polymorphic_embeds_one(:poly, types: [child: Strukt.Test.NilChild], on_replace: :update)
    polymorphic_embeds_many(:polys, types: [child: Strukt.Test.NilChild], on_replace: :delete)
  end
end

defmodule Strukt.Test.NilRequired do
  use Strukt

  defstruct do
    field(:name, :string, required: [message: "required name"])

    embeds_one(:one, Strukt.Test.NilChild,
      required: [message: "required one"],
      on_replace: :delete
    )

    polymorphic_embeds_one(:poly,
      types: [child: Strukt.Test.NilChild],
      required: [message: "required poly"],
      on_replace: :update
    )
  end
end
