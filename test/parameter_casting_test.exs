# Modified from upstream by the maintainers of the fishtreesugar/strukt fork.

defmodule Strukt.ParameterCastingTest do
  use ExUnit.Case, async: true
  alias Strukt.Test.ParameterCasting.{Child, Parent, Collision}

  test "filtered string-keyed pair lists retain source fields and validation" do
    params =
      Enum.reject(%{"NAME" => "Ada", "note" => "saved", "absent" => nil}, fn {_, v} ->
        is_nil(v)
      end)

    assert {:ok, %Child{name: "Ada", note: "saved", uuid: uuid}} = Child.new(params)
    assert is_binary(uuid)

    alias Strukt.Test.ParameterCasting.Email
    assert {:ok, %{address: "a@example.com"}} = Email.new([{"ADDRESS", "a@example.com"}])
    assert {:error, cs} = Email.new([{"ADDRESS", nil}])
    assert Keyword.has_key?(cs.errors, :address)
  end

  test "pair-list source aliases update structs and pending changesets including explicit nil" do
    original = %Child{uuid: Ecto.UUID.generate(), name: "original", note: "saved"}
    pending = Child.change(original, name: "pending")

    for current <- [original, pending] do
      cs = Child.change(current, [{"NAME", "next"}])
      assert cs.valid?
      assert Ecto.Changeset.apply_changes(cs) == %{original | name: "next"}
      cleared = Child.change(cs, [{"NAME", nil}, {"name", "ignored"}])
      assert cleared.valid?
      assert Ecto.Changeset.apply_changes(cleared) == %{original | name: nil}
    end
  end

  for field <- [:child, :children, :poly, :polys] do
    test "top-level pair lists normalize nested #{field} fields and generate keys" do
      field = unquote(field)
      child = %{"NAME" => "nested", "__type__" => "child"}
      value = if field in [:children, :polys], do: [child], else: child
      assert {:ok, parent} = Parent.new([{to_string(field), value}])
      assert [%Child{name: "nested", uuid: uuid}] = List.wrap(Map.fetch!(parent, field))
      assert is_binary(uuid)
    end
  end

  for field <- [:child, :children] do
    test "nested string-keyed pair lists normalize #{field} creation and updates" do
      field = unquote(field)
      wrap = fn child -> if unquote(field == :children), do: [child], else: child end

      assert {:ok, parent} =
               Parent.new(%{field => wrap.([{"NAME", "nested"}, {"note", "saved"}])})

      [child] = List.wrap(Map.fetch!(parent, field))
      assert child.name == "nested"
      assert is_binary(child.uuid)

      cs = Parent.change(parent, %{field => wrap.([{"NAME", "updated"}])})
      assert cs.valid?

      assert List.wrap(Map.fetch!(Ecto.Changeset.apply_changes(cs), field)) == [
               %{child | name: "updated"}
             ]
    end

    test "direct changesets accept nested pair lists with field names in #{field}" do
      field = unquote(field)
      params = [{"name", "direct"}, {"note", "saved"}]
      value = if unquote(field == :children), do: [params], else: params
      cs = Parent.changeset(%Parent{}, %{field => value})
      assert cs.valid?

      assert [%Child{name: "direct", note: "saved", uuid: nil}] =
               List.wrap(Map.fetch!(Ecto.Changeset.apply_changes(cs), field))
    end
  end

  test "pair-list embed entries match IDs before borrowing positional context" do
    a = %Child{uuid: Ecto.UUID.generate(), name: "A", note: "saved A"}
    b = %Child{uuid: Ecto.UUID.generate(), name: "B", note: "saved B"}
    parent = %Parent{children: [a, b]}

    cs = Parent.change(parent, children: [[{"uuid", b.uuid}, {"NAME", "B2"}], [{"uuid", a.uuid}]])
    assert cs.valid?
    assert Ecto.Changeset.apply_changes(cs).children == [%{b | name: "B2"}, a]
  end

  for api <- [:new, :change, :changeset, :pending_change, :pending_changeset] do
    test "#{api} reports malformed top-level params as Ecto cast errors" do
      original = %Parent{title: "saved"}
      pending = Parent.change(original, title: "pending")

      for params <- [42, :atom, "invalid", [1], [{42, "invalid key"}], [{:title, "x"}, :bad]] do
        assert_raise Ecto.CastError, fn ->
          case unquote(api) do
            :new -> Parent.new(params)
            :change -> Parent.change(original, params)
            :changeset -> Parent.changeset(original, params)
            :pending_change -> Parent.change(pending, params)
            :pending_changeset -> Parent.changeset(pending, params, :update)
          end
        end
      end
    end
  end

  test "the Ecto invalid sentinel produces an invalid changeset without casting embeds" do
    original = %Parent{title: "saved", child: %Child{name: "saved"}}
    pending = Parent.change(original, title: "pending")
    assert {:error, %{valid?: false}} = Parent.new(:invalid)

    for cs <- [
          Parent.changeset(original, :invalid),
          Parent.change(original, :invalid),
          Parent.changeset(pending, :invalid, :update),
          Parent.change(pending, :invalid)
        ] do
      refute cs.valid?
      assert Ecto.Changeset.apply_changes(cs).child == original.child
    end
  end

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

  defp compile(name, body) do
    Code.compile_string(
      "defmodule #{name} do\n@compile {:debug_info, true}\nuse Strukt\n#{body}\nend"
    )
  end

  defp call(module, function, args), do: apply(module, function, args)
  defp params_for(field, attrs) when field in [:many, :binary_many], do: %{field => [attrs]}
  defp params_for(field, attrs), do: %{field => attrs}
  defp expect_unknown(:raise, run), do: assert_raise(RuntimeError, run)
  defp expect_unknown(:nilify, run), do: assert(Ecto.Changeset.apply_changes(run.()).item == nil)
  defp expect_unknown(:changeset_error, run), do: refute(run.().valid?)

  test "custom primary key types can be used in polymorphic embeds" do
    assert {:ok, %{custom: %{id: id}}} =
             Strukt.Test.SchemaOptions.Parent.new(custom: %{__type__: :child})

    assert is_binary(id)
  end

  for field <- [:one, :many] do
    test "a map type discriminator in #{field} returns a field error" do
      field = unquote(field)
      attrs = %{__type__: %{bad: "tag"}}
      assert {:error, cs} = Strukt.Test.SchemaOptions.Parent.new(params_for(field, attrs))
      assert Keyword.has_key?(cs.errors, field)
    end
  end

  test "an unknown parent discriminator returns a field error" do
    assert {:error, cs} =
             Strukt.Test.SchemaOptions.Parent.new(kind: "unknown", parent_kind: %{name: "x"})

    assert Keyword.has_key?(cs.errors, :parent_kind)
  end

  for policy <- [:changeset_error, :nilify, :raise] do
    test "unknown explicit tags honor #{policy} with an existing variant" do
      policy = unquote(policy)
      m = Module.concat(Strukt.Test.SchemaOptions, "Policy#{policy}")

      compile(m, """
      defstruct do
        polymorphic_embeds_one :item, types: [child: Strukt.Test.SchemaOptions.Child], on_replace: :update, on_type_not_found: #{inspect(policy)}
      end
      """)

      p =
        struct(m, item: %Strukt.Test.SchemaOptions.Child{uuid: Ecto.UUID.generate(), name: "old"})

      run = fn -> call(m, :change, [p, [item: %{__type__: :unknown, name: "new"}]]) end
      expect_unknown(policy, run)
    end
  end

  for field <- [:binary_one, :binary_many] do
    test "explicit nil binary IDs override autogeneration in #{field}" do
      field = unquote(field)
      attrs = %{__type__: :child, id: nil}
      assert {:ok, p} = Strukt.Test.SchemaOptions.Parent.new(params_for(field, attrs))
      child = Map.fetch!(p, field) |> List.wrap() |> hd()
      assert child.id == nil
    end
  end

  test "explicit nil UUID on a polymorphic update does not raise" do
    assert {:ok, p} = Strukt.Test.SchemaOptions.Parent.new(one: %{__type__: :child, name: "old"})
    cs = Strukt.Test.SchemaOptions.Parent.change(p, one: %{uuid: nil})
    assert cs.valid?
    assert Ecto.Changeset.apply_changes(cs).one.uuid == nil
  end

  test "a no-key ordinary list retains omitted fields during a positional update" do
    c = %Strukt.Test.SchemaOptions.NoKey{name: "old", note: "saved"}

    cs =
      Strukt.Test.SchemaOptions.Parent.change(%Strukt.Test.SchemaOptions.Parent{no_keys: [c]},
        no_keys: [%{name: "new"}]
      )

    assert cs.valid?
    assert Ecto.Changeset.apply_changes(cs).no_keys == [%{c | name: "new"}]
  end

  for kind <- [:embeds_one, :polymorphic_embeds_one] do
    test "insert-only child validation runs through #{kind} construction" do
      child = Module.concat(Strukt.Test.SchemaOptions, "ActionChild#{unquote(kind)}")
      parent = Module.concat(Strukt.Test.SchemaOptions, "ActionParent#{unquote(kind)}")

      compile(child, """
      defstruct do
        field :name, :string
      end
      validation :reject when changeset.action == :insert
      defp reject(cs, _), do: add_error(cs, :name, "rejected")
      """)

      declaration =
        case unquote(kind) do
          :embeds_one ->
            "embeds_one :child, #{inspect(child)}, on_replace: :update"

          :polymorphic_embeds_one ->
            "polymorphic_embeds_one :child, types: [child: #{inspect(child)}], on_replace: :update"
        end

      compile(parent, "defstruct do\n#{declaration}\nend")
      assert {:error, _} = call(child, :new, [[name: "x"]])
      assert {:error, _} = call(parent, :new, [[child: %{__type__: :child, name: "x"}]])
    end
  end

  test "unknown and malformed polymorphic list tags honor ignore and raise policies" do
    for policy <- [:ignore, :raise] do
      m = Module.concat(Strukt.Test.SchemaOptions, "ListPolicy#{policy}")

      compile(m, """
      defstruct do
        polymorphic_embeds_many :items, types: [child: Strukt.Test.SchemaOptions.Child],
          on_replace: :delete, on_type_not_found: #{inspect(policy)}
      end
      """)

      trusted = %Strukt.Test.SchemaOptions.Child{name: "trusted"}

      for tag <- [:unknown, %{bad: "type"}, nil] do
        run = fn ->
          call(m, :new, [[items: [trusted, %{__type__: tag}, %{__type__: :child, name: "cast"}]]])
        end

        if policy == :raise do
          assert_raise RuntimeError, ~r/could not infer/, run
        else
          assert {:ok, %{items: [^trusted, %{name: "cast"}]}} = run.()
        end
      end
    end
  end

  test "parent discriminator errors follow the configured policy and mismatches remain explicit" do
    for policy <- [:nilify, :raise] do
      m = Module.concat(Strukt.Test.SchemaOptions, "ParentPolicy#{policy}")

      compile(m, """
      defstruct do
        field :kind, :string
        polymorphic_embeds_one :item, types: [child: Strukt.Test.SchemaOptions.Child],
          on_replace: :update, use_parent_field_for_type: :kind,
          on_type_not_found: #{inspect(policy)}
      end
      """)

      run = fn -> call(m, :new, [[kind: "unknown", item: %{name: "x"}]]) end

      if policy == :raise,
        do: assert_raise(RuntimeError, ~r/could not infer/, run),
        else: assert({:ok, %{item: nil}} = run.())

      assert_raise RuntimeError, ~r/does not match/, fn ->
        call(m, :new, [[kind: "child", item: %{__type__: :other}]])
      end
    end
  end

  test "no-key list updates preserve positional data through pending changes and resizing" do
    alias Strukt.Test.SchemaOptions, as: Options
    a = %Options.NoKey{name: "A", note: "saved A"}
    b = %Options.NoKey{name: "B", note: "saved B"}

    pending =
      Options.Parent.change(%Options.Parent{no_keys: [a, b]},
        no_keys: [%{name: "pending A"}, %{}]
      )

    cs = Options.Parent.change(pending, no_keys: [%{note: "next"}])
    assert cs.valid?
    assert Ecto.Changeset.apply_changes(cs).no_keys == [%{a | name: "pending A", note: "next"}]
  end

  test "nested validators receive insert and update actions for both embed cardinalities" do
    child = Strukt.Test.SchemaOptions.ActionChild
    parent = Strukt.Test.SchemaOptions.ActionParent

    compile(child, """
    defstruct do
      field :name, :string
      field :seen, :string
    end
    validation :record
    defp record(cs, _), do: put_change(cs, :seen, Atom.to_string(cs.action))
    """)

    compile(parent, """
    defstruct do
      embeds_one :one, #{inspect(child)}, on_replace: :update
      embeds_many :many, #{inspect(child)}, on_replace: :delete
      polymorphic_embeds_one :poly, types: [child: #{inspect(child)}], on_replace: :update
      polymorphic_embeds_many :polys, types: [child: #{inspect(child)}], on_replace: :delete
    end
    """)

    attrs = %{name: "created", __type__: :child}

    assert {:ok, p} =
             call(parent, :new, [[one: attrs, many: [attrs], poly: attrs, polys: [attrs]]])

    for field <- [:one, :many, :poly, :polys] do
      [created] = List.wrap(Map.fetch!(p, field))
      assert created.seen == "insert"
      attrs = %{uuid: created.uuid, name: "updated", __type__: :child}
      attrs = if field in [:many, :polys], do: [attrs], else: attrs
      cs = call(parent, :change, [p, %{field => attrs}])
      assert cs.valid?
      [updated] = List.wrap(Map.fetch!(Ecto.Changeset.apply_changes(cs), field))
      assert updated.seen == "update"
    end
  end

  test "direct polymorphic changesets do not autogenerate omitted or nil keys" do
    alias Strukt.Test.SchemaOptions.Parent, as: OptionsParent

    for attrs <- [%{__type__: :child}, %{__type__: :child, id: nil}] do
      cs = OptionsParent.changeset(%OptionsParent{}, %{binary_one: attrs, custom: attrs})
      assert cs.valid?
      p = Ecto.Changeset.apply_changes(cs)
      assert p.binary_one.id == nil
      assert p.custom.id == nil
    end
  end

  test "polymorphic custom IDs and explicit nil binary IDs round trip through JSON" do
    alias Strukt.Test.SchemaOptions.Parent, as: OptionsParent

    assert {:ok, p} =
             OptionsParent.new(
               custom: %{__type__: :child, name: "custom"},
               binary_one: %{__type__: :child, id: nil},
               binary_many: [%{__type__: :child, id: nil}]
             )

    assert is_binary(p.custom.id)
    assert {:ok, ^p} = p |> Jason.encode!() |> OptionsParent.from_json()
  end

  test "JSON encoding preserves nil polymorphic IDs inside source-mapped ordinary embeds" do
    alias Strukt.Test.SchemaOptions.Envelope
    assert {:ok, envelope} = Envelope.new(payload: %{binary_one: %{__type__: :child, id: nil}})
    encoded = Jason.encode!(envelope)

    assert %{"PAYLOAD" => %{"binary_one" => %{"id" => nil, "__type__" => "child"}}} =
             Jason.decode!(encoded)

    assert {:ok, ^envelope} = Envelope.from_json(encoded)
  end

  test "plain Ecto children retain changeset/2 even when they define changeset/3" do
    assert {:ok, %{ordinary: %{name: "ordinary"}, poly: %{name: "poly"}}} =
             Strukt.Test.SchemaOptions.EctoParent.new(
               ordinary: %{name: "ordinary"},
               poly: %{__type__: :child, name: "poly"}
             )
  end
end
