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

    polymorphic_embeds_many(:channels,
      types: [
        email: [
          module: Strukt.Test.Fixtures.PolymorphicEmail,
          identify_by_fields: [:emailAddress]
        ]
      ],
      type_field_name: :kind,
      on_replace: :delete
    )
  end
end

defmodule Strukt.Test.EmbedUpdates.CompositeChild do
  use Strukt
  @primary_key false
  defstruct do
    field(:account_id, :integer, primary_key: true, source: :accountId)
    field(:code, :string, primary_key: true, source: :Code)
    field(:name, :string)
  end
end

defmodule Strukt.Test.EmbedUpdates.CompositeParent do
  use Strukt

  defstruct do
    embeds_many(:items, Strukt.Test.EmbedUpdates.CompositeChild, on_replace: :delete)

    polymorphic_embeds_many(:polys,
      types: [child: Strukt.Test.EmbedUpdates.CompositeChild],
      on_replace: :delete
    )
  end
end
