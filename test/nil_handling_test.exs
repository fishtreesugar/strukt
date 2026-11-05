# Modified from upstream by the maintainers of the fishtreesugar/strukt fork.

defmodule Strukt.NilHandlingTest do
  use ExUnit.Case, async: true

  alias Strukt.Test.{NilChild, NilParent, NilRequired}

  defp populated do
    child = %NilChild{uuid: Ecto.UUID.generate(), name: "child", note: "keep"}

    %NilParent{
      uuid: Ecto.UUID.generate(),
      name: "old",
      optional: "old",
      label: "keep",
      one: child,
      many: [child],
      poly: child,
      polys: [child]
    }
  end

  test "nil clears optional single embeds through both update APIs and changesets" do
    original = populated()

    for field <- [:one, :poly],
        params <- [%{field => nil}, %{to_string(field) => nil}, [{field, nil}]],
        api <- [:change, :changeset] do
      cs = apply(NilParent, api, [original, params])
      assert cs.valid?
      assert Map.fetch!(Ecto.Changeset.apply_changes(cs), field) == nil
    end

    for field <- [:one, :poly] do
      pending = NilParent.change(%NilParent{}, %{field => Map.fetch!(original, field)})
      cs = NilParent.change(pending, %{field => nil})
      assert cs.valid?
      assert Map.fetch!(Ecto.Changeset.apply_changes(cs), field) == nil
    end
  end

  test "nil and empty lists clear both embed list kinds" do
    for original <- [%NilParent{}, populated()],
        field <- [:many, :polys],
        value <- [nil, []],
        api <- [:change, :changeset] do
      cs = apply(NilParent, api, [original, %{field => value}])
      assert cs.valid?
      assert Map.fetch!(Ecto.Changeset.apply_changes(cs), field) == []
    end
  end

  test "nil list elements are invalid regardless of existing data" do
    for original <- [%NilParent{}, populated()],
        field <- [:many, :polys],
        api <- [:change, :changeset] do
      cs = apply(NilParent, api, [original, %{field => [nil]}])
      refute cs.valid?
      assert Keyword.has_key?(cs.errors, field)
    end
  end

  test "clearing required fields and embeds reports required validation" do
    child = populated().one
    original = %NilRequired{name: "name", one: child, poly: child}

    for field <- [:name, :one, :poly], api <- [:change, :changeset] do
      cs = apply(NilRequired, api, [original, %{field => nil}])
      refute cs.valid?
      assert {_, opts} = Keyword.fetch!(cs.errors, field)
      assert opts[:validation] == :required
    end
  end

  test "required false allows nil on creation and clearing" do
    assert {:ok, %NilParent{optional: nil}} = NilParent.new(optional: nil)
    cs = NilParent.change(populated(), optional: nil)
    assert {:ok, %NilParent{optional: nil}} = NilParent.from_changeset(cs)
  end

  test "omitted fields are not recast, including empty keyword params" do
    assert {:ok, original} = NilParent.from_json(~s({"name":"   ","LABEL":""}))

    for params <- [%{}, [], nil, %{optional: "updated"}, [optional: "updated"]] do
      cs = NilParent.change(original, params)
      assert {:ok, updated} = NilParent.from_changeset(cs)
      assert updated.name == "   "
      assert updated.label == ""
      refute Map.has_key?(cs.params, "name")
      refute Map.has_key?(cs.params, "label")
    end
  end

  test "omitted embeds retain their data when another field changes" do
    original = populated()
    cs = NilParent.change(original, name: "updated")
    assert {:ok, updated} = NilParent.from_changeset(cs)

    for field <- [:one, :many, :poly, :polys] do
      assert Map.fetch!(updated, field) == Map.fetch!(original, field)
      refute Map.has_key?(cs.params, to_string(field))
    end
  end

  test "nested updates preserve omitted fields and primary keys" do
    original = populated()

    original = %{
      original
      | one: %{original.one | note: "   "},
        many: [%{original.one | note: "   "}]
    }

    cs = NilParent.change(original, one: %{NAME: nil}, many: [%{NAME: nil}])
    assert {:ok, updated} = NilParent.from_changeset(cs)
    assert updated.one == %{original.one | name: nil}
    assert updated.many == Enum.map(original.many, &%{&1 | name: nil})
  end

  test "polymorphic partial updates preserve omitted fields without recasting" do
    original = populated()
    child = %{original.poly | note: "   "}
    original = %{original | poly: child, polys: [child, child]}

    for values <- [
          [%{__type__: :child, NAME: nil}],
          [%{__type__: :child, NAME: nil}, child],
          [child, %{__type__: :child, NAME: nil}]
        ] do
      cs = NilParent.change(original, poly: %{__type__: :child, NAME: nil}, polys: values)
      assert {:ok, updated} = NilParent.from_changeset(cs)
      assert updated.poly == %{child | name: nil}

      assert updated.polys ==
               Enum.map(values, fn
                 %NilChild{} -> child
                 _ -> %{child | name: nil}
               end)
    end
  end

  test "successive partial changes preserve pending embedded values" do
    for original <- [%NilParent{}, populated()], field <- [:one, :poly, :many, :polys] do
      first = %{NAME: "pending", __type__: :child}
      second = %{note: nil, __type__: :child}

      {first, second} =
        if field in [:many, :polys], do: {[first], [second]}, else: {first, second}

      pending = NilParent.change(original, %{field => first})
      assert pending.valid?
      updated = NilParent.change(pending, %{field => second})
      assert {:ok, result} = NilParent.from_changeset(updated)
      child = result |> Map.fetch!(field) |> List.wrap() |> hd()
      assert child.name == "pending"
      assert child.note == nil
    end
  end

  test "clearing lists also cancels pending insertions" do
    for field <- [:many, :polys], value <- [nil, []] do
      pending = NilParent.change(%NilParent{}, %{field => [populated().one]})
      cs = NilParent.change(pending, %{field => value})
      assert cs.valid?
      assert Map.fetch!(Ecto.Changeset.apply_changes(cs), field) == []
    end
  end

  test "explicit nil overrides ordinary defaults and autogenerated primary keys" do
    assert {:ok, %NilParent{name: nil, uuid: nil}} = NilParent.new(name: nil, uuid: nil)
    assert {:ok, %NilParent{name: "default", uuid: uuid}} = NilParent.new()
    assert {:ok, _} = Ecto.UUID.cast(uuid)
  end

  test "new embeds still autogenerate primary keys" do
    assert {:ok, parent} = NilParent.new(one: %{NAME: "one"}, many: [%{NAME: "many"}])
    assert {:ok, _} = Ecto.UUID.cast(parent.one.uuid)
    assert {:ok, _} = Ecto.UUID.cast(hd(parent.many).uuid)
  end

  test "same-schema structs and maps agree on source-mapped fields" do
    original = populated()
    params = %{original | label: "changed"}

    for input <- [params, Map.from_struct(params)] do
      assert {:ok, updated} = original |> NilParent.change(input) |> NilParent.from_changeset()
      assert updated.label == "changed"
      assert updated.one.name == "child"
      assert hd(updated.many).name == "child"
    end
  end

  test "source and atom key precedence includes explicit nil" do
    for params <- [
          %{LABEL: nil, label: "ignored"},
          %{:LABEL => nil, "LABEL" => "ignored"},
          %{label: nil},
          %{"LABEL" => nil},
          [LABEL: nil]
        ] do
      assert {:ok, %NilParent{label: nil}} =
               populated() |> NilParent.change(params) |> NilParent.from_changeset()
    end
  end

  test "changeset accepts schema names while change also accepts source names" do
    original = populated()
    assert Ecto.Changeset.apply_changes(NilParent.changeset(original, LABEL: nil)).label == "keep"
    assert Ecto.Changeset.apply_changes(NilParent.changeset(original, label: nil)).label == nil
    assert Ecto.Changeset.apply_changes(NilParent.change(original, LABEL: nil)).label == nil
  end

  test "clearing an embed respects its on_replace policy" do
    alias Strukt.Test.Fixtures.CustomFieldsWithEmbeddedSchema, as: Parent
    assert {:ok, parent} = Parent.new(meta: %{SOURCE: "source"})
    assert_raise RuntimeError, ~r/on_replace/, fn -> Parent.change(parent, meta: nil) end
  end

  test "optional defaults are nullable and keyword required declarations are not" do
    for module <- [NilParent, NilRequired] do
      {:ok, types} = Code.Typespec.fetch_types(module)
      {:type, type} = Enum.find(types, fn {_, {name, _, _}} -> name == :t end)
      spec = Macro.to_string(Code.Typespec.type_to_quoted(type))

      if module == NilParent do
        assert spec =~ "name: String.t() | nil"
        assert spec =~ "optional: String.t() | nil"
      else
        assert spec =~ "name: String.t()"
        refute spec =~ "name: String.t() | nil"
        assert spec =~ "one: Strukt.Test.NilChild.t()"
        refute spec =~ "one: Strukt.Test.NilChild.t() | nil"
        assert spec =~ "poly: Strukt.Test.NilChild.t()"
        refute spec =~ "poly: Strukt.Test.NilChild.t() | nil"
      end
    end
  end

  test "JSON loading bypasses validations and uses source keys" do
    assert {:ok, %NilRequired{name: nil, one: nil, poly: nil}} =
             NilRequired.from_json(~s({"name":null,"one":null,"poly":null}))

    assert {:ok, %NilParent{label: "source", many: [], polys: nil}} =
             NilParent.from_json(
               ~s({"label":"ignored","LABEL":"source","many":null,"polys":null})
             )

    assert Ecto.embedded_dump(populated(), :json)[:LABEL] == "keep"
  end
end
