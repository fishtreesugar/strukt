# Modified from upstream by the maintainers of the fishtreesugar/strukt fork.

defmodule Strukt.Test.EmbedUpdates.IDChild do
  use Strukt
  @primary_key {:id, :binary_id, autogenerate: true}
  defstruct do
    field(:name, :string)
  end
end

defmodule Strukt.Test.EmbedUpdates.IDParent do
  use Strukt

  defstruct do
    polymorphic_embeds_many(:items,
      types: [child: Strukt.Test.EmbedUpdates.IDChild],
      on_replace: :delete
    )
  end
end

defmodule Strukt.Test.EmbedUpdates.InferredParent do
  use Strukt

  defstruct do
    polymorphic_embeds_one(:channel,
      types: [
        email: [
          module: Strukt.Test.Fixtures.PolymorphicEmail,
          identify_by_fields: [:emailAddress]
        ]
      ],
      on_replace: :update
    )
  end
end
