# Modified from upstream by the maintainers of the fishtreesugar/strukt fork.

defmodule Strukt.ParameterCastingTest do
  use ExUnit.Case, async: true
  alias Strukt.Test.ParameterCasting.{Child, Parent, Collision}

  test "pending ordinary single update retains omitted fields and identity with on_replace update" do
    child = %Child{uuid: Ecto.UUID.generate(), name: "original", note: "saved"}
    pending = Parent.change(%Parent{child: child}, child: %{name: "pending"})
    cs = Parent.changeset(pending, %{child: %{note: "next"}}, :update)
    assert cs.valid?
    assert Ecto.Changeset.apply_changes(cs).child == %{child | name: "pending", note: "next"}
  end

  test "polymorphic partial updates normalize aliases using the existing type" do
    child = %Child{uuid: Ecto.UUID.generate(), name: "old"}
    cs = Parent.change(%Parent{poly: child}, poly: %{NAME: "next"})
    assert cs.valid?
    assert Ecto.Changeset.apply_changes(cs).poly.name == "next"
  end

  test "schema struct values are not reinterpreted as another field's source alias" do
    input = %Collision{a: "A", b: "B"}
    assert {:ok, ^input} = Collision.new(input)
  end

  test "indexed polymorphic list maps preserve the explicitly selected UUID data" do
    a = %Child{uuid: Ecto.UUID.generate(), name: "A"}
    b = %Child{uuid: Ecto.UUID.generate(), name: "B"}

    cs =
      Parent.change(%Parent{polys: [a, b]},
        polys: %{"0" => %{"__type__" => "child", "uuid" => b.uuid}}
      )

    assert cs.valid?
    assert Ecto.Changeset.apply_changes(cs).polys == [b]
  end

  test "indexed ordinary list maps normalize source names and autogenerate" do
    assert {:ok, parent} = Parent.new(children: %{"0" => %{"NAME" => "new"}})
    assert [%Child{name: "new", uuid: uuid}] = parent.children
    assert is_binary(uuid)
  end

  test "ordinary embed mixed lists work through the direct changeset API" do
    cs = Parent.changeset(%Parent{}, %{children: [%Child{name: "struct"}, %{name: "map"}]})
    assert cs.valid?
    assert Enum.map(Ecto.Changeset.apply_changes(cs).children, & &1.name) == ["struct", "map"]
  end

  for {field, input} <- [child: [1], children: [[1]]] do
    test "invalid list shape in #{field} returns a changeset error" do
      assert {:error, cs} = Parent.new(%{unquote(field) => unquote(input)})
      assert Keyword.has_key?(cs.errors, unquote(field))
    end
  end
end
