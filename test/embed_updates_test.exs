# Modified from upstream by the maintainers of the fishtreesugar/strukt fork.

defmodule Strukt.Test.EmbedUpdates.RegressionTest do
  use ExUnit.Case, async: true
  alias Strukt.Test.{NilChild, NilParent}
  alias Strukt.Test.Fixtures.PolymorphicReminder, as: Reminder

  test "switching back to email starts fresh and validates the missing address" do
    {:ok, original} = Reminder.new(channel: %{__type__: :email, address: "old@example.com"})

    cs =
      original
      |> Reminder.change(channel: %{__type__: :sms, number: "+1"})
      |> Reminder.change(channel: %{__type__: :email})

    refute cs.valid?
  end

  test "direct polymorphic changeset retains data belonging to the explicit ID" do
    a = %Strukt.Test.EmbedUpdates.IDChild{id: Ecto.UUID.generate(), name: "Alice"}
    b = %Strukt.Test.EmbedUpdates.IDChild{id: Ecto.UUID.generate(), name: "Bob"}
    original = %Strukt.Test.EmbedUpdates.IDParent{items: [a, b]}

    cs =
      Strukt.Test.EmbedUpdates.IDParent.changeset(original, %{
        items: [%{__type__: :child, id: b.id}]
      })

    assert cs.valid?
    assert Ecto.Changeset.apply_changes(cs).items == [b]
  end

  test "removing the first ordinary embed retains the second embed's pending update" do
    a = %NilChild{uuid: Ecto.UUID.generate(), name: "A"}
    b = %NilChild{uuid: Ecto.UUID.generate(), name: "B"}

    cs =
      %NilParent{many: [a, b]}
      |> NilParent.change(
        many: [%{uuid: a.uuid, name: "pending A"}, %{uuid: b.uuid, name: "pending B"}]
      )
      |> NilParent.change(many: [%{uuid: b.uuid}])

    assert cs.valid?
    assert Ecto.Changeset.apply_changes(cs).many == [%{b | name: "pending B"}]
  end

  test "empty map embed parameters generate a primary key just like keyword parameters" do
    {:ok, parent} = NilParent.new(one: %{})
    assert is_binary(parent.one.uuid)
  end

  test "field-based type inference survives source-name normalization" do
    assert {:ok, parent} =
             Strukt.Test.EmbedUpdates.InferredParent.new(
               channel: %{emailAddress: "ok@example.com"}
             )

    assert parent.channel.address == "ok@example.com"
  end

  test "clearing a polymorphic value then recreating it does not resurrect old fields" do
    child = %NilChild{uuid: Ecto.UUID.generate(), name: "old", note: "old note"}
    cleared = NilParent.change(%NilParent{poly: child}, poly: nil)

    for api <- [:change, :changeset] do
      params = %{poly: %{__type__: :child, name: "new"}}

      cs =
        if api == :change,
          do: NilParent.change(cleared, params),
          else: NilParent.changeset(cleared, params, :update)

      assert cs.valid?
      assert %NilChild{name: "new", note: "default"} = Ecto.Changeset.apply_changes(cs).poly
    end
  end

  test "single polymorphic updates use the pending type even without a new discriminator" do
    {:ok, original} = Reminder.new(channel: %{__type__: :email, address: "old@example.com"})
    pending = Reminder.change(original, channel: %{__type__: :sms, number: "+1"})
    cs = Reminder.change(pending, channel: %{number: "+2"})
    assert cs.valid?

    assert %Strukt.Test.Fixtures.PolymorphicSMS{number: "+2"} =
             Ecto.Changeset.apply_changes(cs).channel

    assert Ecto.Changeset.apply_changes(Reminder.change(cs, channel: %{})) ==
             Ecto.Changeset.apply_changes(cs)
  end

  test "ordinary and polymorphic lists keep pending values when reordered by UUID" do
    a = %NilChild{uuid: Ecto.UUID.generate(), name: "A", note: "   "}
    b = %NilChild{uuid: Ecto.UUID.generate(), name: "B", note: "   "}

    for field <- [:many, :polys], api <- [:change, :changeset] do
      original = %NilParent{many: [a, b], polys: [a, b]}

      pending =
        NilParent.change(original, %{
          field => [
            %{uuid: a.uuid, name: "pending A", __type__: :child},
            %{uuid: b.uuid, name: "pending B", __type__: :child}
          ]
        })

      params = %{
        to_string(field) => [
          %{"uuid" => b.uuid, "__type__" => "child"},
          %{"uuid" => a.uuid, "__type__" => "child"}
        ]
      }

      cs =
        if api == :change,
          do: NilParent.change(pending, params),
          else: NilParent.changeset(pending, params, :update)

      assert cs.valid?

      assert Map.fetch!(Ecto.Changeset.apply_changes(cs), field) ==
               [%{b | name: "pending B"}, %{a | name: "pending A"}]
    end
  end

  test "explicit new or nil IDs do not borrow data from the same list position" do
    alias Strukt.Test.EmbedUpdates.{IDChild, IDParent}
    a = %IDChild{id: Ecto.UUID.generate(), name: "Alice"}

    for id <- [Ecto.UUID.generate(), nil], api <- [:change, :changeset] do
      cs =
        apply(IDParent, api, [
          %IDParent{items: [a]},
          %{"items" => [%{"__type__" => "child", "id" => id}]}
        ])

      assert cs.valid?
      assert [%IDChild{name: nil}] = Ecto.Changeset.apply_changes(cs).items
    end
  end

  test "composite source-mapped keys are cast before matching and partial keys do not fall back" do
    alias Strukt.Test.EmbedUpdates.{CompositeChild, CompositeParent}
    a = %CompositeChild{account_id: 1, code: "a", name: "Alice"}
    b = %CompositeChild{account_id: 2, code: "b", name: "Bob"}

    for field <- [:items, :polys] do
      original = %CompositeParent{items: [a, b], polys: [a, b]}
      params = %{field => [%{"accountId" => "2", "Code" => "b", "__type__" => "child"}]}
      cs = CompositeParent.change(original, params)
      assert cs.valid?
      assert Map.fetch!(Ecto.Changeset.apply_changes(cs), field) == [b]

      partial = CompositeParent.change(original, %{field => [%{accountId: 2, __type__: :child}]})
      assert partial.valid?

      assert [%CompositeChild{account_id: 2, code: nil, name: nil}] =
               Map.fetch!(Ecto.Changeset.apply_changes(partial), field)
    end
  end

  test "empty maps and keyword lists autogenerate each new ordinary embed only once" do
    for params <- [%{}, []] do
      {:ok, parent} = NilParent.new(one: params, many: [params, params])
      ids = [parent.one.uuid | Enum.map(parent.many, & &1.uuid)]

      for id <- ids do
        assert is_binary(id)
        assert {:ok, ^id} = Ecto.UUID.cast(id)
      end

      assert length(Enum.uniq(ids)) == 3
      cs = NilParent.change(parent, one: params, many: [params, params])
      assert cs.valid?
      assert Ecto.Changeset.apply_changes(cs) == parent
    end
  end

  test "inferred list types survive source mapping with a custom discriminator" do
    alias Strukt.Test.EmbedUpdates.InferredParent
    {:ok, parent} = InferredParent.new(channels: [%{"emailAddress" => "first@example.com"}])

    assert [%Strukt.Test.Fixtures.PolymorphicEmail{address: "first@example.com"}] =
             parent.channels

    cs = InferredParent.change(parent, channels: [%{emailAddress: "next@example.com"}])
    assert cs.valid?

    assert [%Strukt.Test.Fixtures.PolymorphicEmail{address: "next@example.com"}] =
             Ecto.Changeset.apply_changes(cs).channels
  end
end
