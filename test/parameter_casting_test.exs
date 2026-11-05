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

  test "single embed updates honor on_replace update while recreation starts fresh" do
    child = %Child{uuid: Ecto.UUID.generate(), name: "old", note: "saved"}
    pending = Parent.change(%Parent{child: child}, child: %{name: "pending"})

    for id <- [Ecto.UUID.generate(), nil] do
      cs = Parent.changeset(pending, %{child: %{uuid: id, note: "next"}}, :update)
      assert cs.valid?

      assert Ecto.Changeset.apply_changes(cs).child == %{
               child
               | uuid: id,
                 name: "pending",
                 note: "next"
             }
    end

    recreated = pending |> Parent.change(child: nil) |> Parent.change(child: %{uuid: child.uuid})
    assert recreated.valid?
    assert %Child{name: nil, note: "default"} = Ecto.Changeset.apply_changes(recreated).child
  end

  test "tagless polymorphic updates normalize explicit nil aliases against pending data" do
    child = %Child{uuid: Ecto.UUID.generate(), name: "old", note: "saved"}
    pending = Parent.change(%Parent{poly: child}, poly: %{__type__: :child, note: "pending"})
    cs = Parent.change(pending, poly: %{"NAME" => nil, "name" => "ignored"})
    assert cs.valid?
    assert Ecto.Changeset.apply_changes(cs).poly == %{child | name: nil, note: "pending"}

    assert Ecto.Changeset.apply_changes(Parent.change(cs, poly: %{})) ==
             Ecto.Changeset.apply_changes(cs)
  end

  test "nested schema structs use field names while parameter maps retain source precedence" do
    alias Strukt.Test.ParameterCasting.CollisionParent
    input = %Collision{a: "A", b: "B"}
    assert {:ok, %{child: ^input}} = CollisionParent.new(child: input)
    assert Ecto.Changeset.apply_changes(Collision.change(input, input)) == input

    assert {:ok, %{a: "source A", b: "source B"}} =
             Collision.new(%{a: "ignored", b: "source A", c: "source B"})
  end

  test "indexed lists sort numeric keys and retain pending records through both update APIs" do
    a = %Child{uuid: Ecto.UUID.generate(), name: "A"}
    b = %Child{uuid: Ecto.UUID.generate(), name: "B"}

    for field <- [:children, :polys], api <- [:change, :changeset] do
      original = %Parent{children: [a, b], polys: [a, b]}

      pending =
        Parent.change(original, %{
          field => [
            %{uuid: a.uuid, note: "pending A", __type__: :child},
            %{uuid: b.uuid, note: "pending B", __type__: :child}
          ]
        })

      params = %{
        field => %{
          "10" => %{uuid: a.uuid, __type__: :child},
          "2" => %{uuid: b.uuid, __type__: :child}
        }
      }

      cs =
        if api == :change,
          do: Parent.change(pending, params),
          else: Parent.changeset(pending, params, :update)

      assert cs.valid?

      assert Map.fetch!(Ecto.Changeset.apply_changes(cs), field) ==
               [%{b | note: "pending B"}, %{a | note: "pending A"}]

      cleared = Parent.changeset(cs, %{field => %{}}, :update)
      assert cleared.valid?
      assert Map.fetch!(Ecto.Changeset.apply_changes(cleared), field) == []
    end
  end

  test "mixed ordinary lists trust declared structs but validate maps regardless of position" do
    alias Strukt.Test.ParameterCasting.RequiredChild
    trusted = %RequiredChild{uuid: Ecto.UUID.generate(), name: nil}

    for values <- [[trusted, %{name: "valid"}], [%{name: "valid"}, trusted]] do
      cs = Parent.changeset(%Parent{}, %{required_children: values})
      assert cs.valid?
      children = Ecto.Changeset.apply_changes(cs).required_children
      assert trusted in children
      assert Enum.any?(children, &(&1.name == "valid"))
    end

    refute Parent.changeset(%Parent{}, %{required_children: [trusted, %{name: nil}]}).valid?
    refute Parent.changeset(%Parent{}, %{required_children: [trusted, %Child{}]}).valid?
  end

  test "ordinary lists handle keyword maps and reject malformed lists across public APIs" do
    for api <- [:new, :change, :changeset] do
      run = fn params ->
        if api == :new,
          do: Parent.new(params),
          else: apply(Parent, api, [%Parent{}, params]) |> Parent.from_changeset()
      end

      assert {:ok, %{children: [%Child{name: "keyword"}]}} =
               run.(%{children: [[name: "keyword"]]})

      for value <- [[[1]], [nil], [[], [1]], %{"0" => [1]}] do
        assert {:error, cs} = run.(%{children: value})
        assert Keyword.has_key?(cs.errors, :children)
      end
    end
  end

  defp populated_child(name), do: %Child{uuid: Ecto.UUID.generate(), name: name}

  test "trusted structs persist changed fields when updating an existing ordinary list" do
    old = populated_child("old")
    updated = %{old | name: "new"}
    cs = Parent.changeset(struct(Parent, children: [old]), %{children: [updated]})
    assert cs.valid?
    assert Ecto.Changeset.apply_changes(cs).children == [updated]
  end

  test "mixed lists persist changed trusted structs when map entries are unchanged" do
    old = populated_child("old")
    other = populated_child("other")
    updated = %{old | name: "new"}

    cs =
      Parent.changeset(struct(Parent, children: [old, other]), %{
        children: [updated, %{uuid: other.uuid}]
      })

    assert cs.valid?
    assert Ecto.Changeset.apply_changes(cs).children == [updated, other]
  end

  test "parent-field polymorphic switches select the new module before normalization" do
    {:ok, p} =
      Strukt.Test.ParameterCasting.ParentType.new(
        kind: "email",
        payload: %{address: "old@example.com"}
      )

    cs =
      Strukt.Test.ParameterCasting.ParentType.change(p, kind: "sms", payload: %{number: "+123"})

    assert cs.valid?

    assert %Strukt.Test.ParameterCasting.SMS{number: "+123"} =
             Ecto.Changeset.apply_changes(cs).payload
  end

  for field <- [:child, :poly, :children, :polys] do
    test "omitting #{field} does not restore a deleted change from historical params" do
      field = unquote(field)
      many? = field in [:children, :polys]
      original = populated_child("original")
      value = if many?, do: [original], else: original
      p = struct(Parent, [{field, value}])
      attrs = %{uuid: original.uuid, name: "submitted", __type__: :child}
      pending = Parent.change(p, %{field => if(many?, do: [attrs], else: attrs)})
      cancelled = Ecto.Changeset.delete_change(pending, field)

      for api <- [:change, :changeset] do
        update = fn changeset ->
          if api == :change,
            do: Parent.change(changeset, title: "unrelated"),
            else: Parent.changeset(changeset, %{title: "unrelated"}, :update)
        end

        cs = update.(cancelled)
        assert cs.valid?
        assert Map.fetch!(Ecto.Changeset.apply_changes(cs), field) == value

        edited = %{original | name: "manually edited"}
        edited = if many?, do: [edited], else: edited

        manual =
          if field in [:child, :children] do
            child_change = Ecto.Changeset.change(original, name: "manually edited")

            Ecto.Changeset.put_embed(
              pending,
              field,
              if(many?, do: [child_change], else: child_change)
            )
          else
            Ecto.Changeset.put_change(pending, field, edited)
          end

        assert Map.fetch!(Ecto.Changeset.apply_changes(manual), field) == edited
        cs = update.(manual)
        assert cs.valid?
        assert Map.fetch!(Ecto.Changeset.apply_changes(cs), field) == edited
      end
    end
  end

  test "ordinary single embeds reject structs outside their declared schema" do
    cs =
      Parent.changeset(struct(Parent), %{
        child: struct(Strukt.Test.ParameterCasting.Foreign, name: 123)
      })

    refute cs.valid?
  end

  test "ordinary embeds reject foreign structs during normalized creation and updates" do
    foreign = struct(Strukt.Test.ParameterCasting.Foreign, name: "looks valid")

    for field <- [:child, :children] do
      params = %{field => if(field == :child, do: foreign, else: [foreign])}
      assert {:error, cs} = Parent.new(params)
      assert Keyword.has_key?(cs.errors, field)

      for api <- [:change, :changeset] do
        cs = apply(Parent, api, [%Parent{child: populated_child("old")}, params])
        refute cs.valid?
        assert Keyword.has_key?(cs.errors, field)
      end
    end
  end

  test "trusted ordinary structs can revert pending fields and reorder existing list entries" do
    a = populated_child("A")
    b = populated_child("B")
    parent = %Parent{child: a, children: [a, b]}

    pending =
      Parent.change(parent,
        child: %{name: "pending"},
        children: [%{uuid: a.uuid, name: "pending"}, %{uuid: b.uuid}]
      )

    cs = Parent.changeset(pending, %{child: a, children: [b, a]}, :update)
    assert cs.valid?
    assert %{child: ^a, children: [^b, ^a]} = Ecto.Changeset.apply_changes(cs)
  end

  test "parent type selection uses source aliases and cast enum values including pending changes" do
    alias Strukt.Test.ParameterCasting.{ParentEnumType, Email, SMS}

    assert {:ok, parent} =
             ParentEnumType.new(%{"TYPE" => "email", "payload" => %{"ADDRESS" => "old"}})

    assert %Email{address: "old"} = parent.payload

    pending = ParentEnumType.change(parent, %{TYPE: "sms"})
    cs = ParentEnumType.change(pending, payload: %{"NUMBER" => "+123"})
    assert cs.valid?
    assert %{kind: :sms, payload: %SMS{number: "+123"}} = Ecto.Changeset.apply_changes(cs)

    cs = ParentEnumType.change(cs, payload: %{"NUMBER" => "+456"})
    assert cs.valid?
    assert %SMS{number: "+456"} = Ecto.Changeset.apply_changes(cs).payload
  end
end
