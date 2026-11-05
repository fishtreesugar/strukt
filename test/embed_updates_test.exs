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
end
