# Modified from upstream by the maintainers of the fishtreesugar/strukt fork.

defmodule Strukt.SchemaDeclarationsTest do
  use ExUnit.Case, async: false

  defp compile(name, body) do
    Code.compile_string(
      "defmodule #{name} do\n@compile {:debug_info, true}\nuse Strukt\n#{body}\nend"
    )
  end

  # These modules are compiled by each test, after this test module itself is compiled.
  defp call(module, function, args), do: apply(module, function, args)

  test "keyword range validation compiles and applies the custom message" do
    compile(
      Strukt.Test.SchemaDeclarations.Range,
      "defstruct do\nfield :n, :integer, range: [value: 1..10, message: \"outside\"]\nend"
    )

    assert {:error, cs} = call(Strukt.Test.SchemaDeclarations.Range, :new, [[n: 11]])
    assert {"outside", _} = cs.errors[:n]
  end

  test "validation options followed by a guard work as documented" do
    compile(Strukt.Test.SchemaDeclarations.Guard, """
    defstruct do
      field :n, :integer
    end
    validation :reject, [message: "reject"] when changeset.action == :update
    defp reject(cs, opts), do: Ecto.Changeset.add_error(cs, :n, opts[:message])
    """)

    assert {:ok, entity} = call(Strukt.Test.SchemaDeclarations.Guard, :new, [[n: 1]])
    refute call(Strukt.Test.SchemaDeclarations.Guard, :change, [entity, [n: 2]]).valid?
  end

  test "named struct field metadata can use a preceding module attribute" do
    Code.compile_string("""
    defmodule Strukt.Test.SchemaDeclarations.AttributeHost do
      use Strukt
      defstruct Child do
        @allowed ["a", "b"]
        field :name, :string, one_of: @allowed
      end
    end
    """)

    assert {:ok, _} =
             call(Strukt.Test.SchemaDeclarations.AttributeHost.Child, :new, [[name: "a"]])
  end

  for {name, option, type, value, expected} <- [
        {Strukt.Test.SchemaDeclarations.EmptyInclusion, :one_of, ":string", "x", :error},
        {Strukt.Test.SchemaDeclarations.EmptyExclusion, :none_of, ":string", "x", :ok},
        {Strukt.Test.SchemaDeclarations.EmptySubset, :subset_of, "{:array, :string}", ["x"],
         :error}
      ] do
    test "#{option} accepts an empty set" do
      name = unquote(name)
      compile(name, "defstruct do\nfield :v, #{unquote(type)}, #{unquote(option)}: []\nend")
      assert {unquote(expected), _} = call(name, :new, [[v: unquote(value)]])
    end
  end

  test "primary_key false on a non-key field leaves the schema's primary key enabled" do
    compile(
      Strukt.Test.SchemaDeclarations.FalsePrimary,
      "defstruct do\nfield :n, :integer, primary_key: false\nend"
    )

    assert call(Strukt.Test.SchemaDeclarations.FalsePrimary, :__schema__, [:primary_key]) == [
             :uuid
           ]
  end

  test "typed map generated types allow arbitrary keys and empty maps" do
    [{_, beam}] =
      compile(
        Strukt.Test.SchemaDeclarations.TypedMap,
        "defstruct do\nfield :counts, {:map, :integer}\nend"
      )

    {:ok, types} = Code.Typespec.fetch_types(beam)
    [{:type, {:t, {:type, _, :map, fields}, []}}] = types

    {:type, _, :map_field_exact, [_, {:type, _, :union, [map, _]}]} =
      Enum.find(fields, fn {:type, _, :map_field_exact, [{:atom, _, key}, _]} ->
        key == :counts
      end)

    assert {:type, _, :map,
            [{:type, _, :map_field_assoc, [{:type, _, :any, []}, {:type, _, :integer, []}]}]} =
             map
  end

  test "validation declarations before defstruct are retained" do
    compile(Strukt.Test.SchemaDeclarations.BeforeSchema, """
    validation :reject
    defstruct do
      field :n, :integer
    end
    defp reject(cs, _), do: Ecto.Changeset.add_error(cs, :n, "rejected")
    """)

    assert {:error, _} = call(Strukt.Test.SchemaDeclarations.BeforeSchema, :new, [[n: 1]])
  end

  test "field constants retain declaration order without changing function attribute bindings" do
    Code.compile_string("""
    defmodule Strukt.Test.SchemaDeclarations.OrderedAttributes do
      use Strukt
      defstruct Child do
        @allowed ["a"]
        field :first, :string, one_of: @allowed, default: hd(@allowed)
        @allowed ["b"]
        field :second, :string, one_of: @allowed, default: hd(@allowed)
        @doc "The value visible to the first function."
        def first_allowed, do: @allowed
        @allowed ["c"]
        def second_allowed, do: @allowed
      end
    end
    """)

    module = Strukt.Test.SchemaDeclarations.OrderedAttributes.Child
    assert {:ok, %{first: "a", second: "b"}} = call(module, :new, [])
    assert {:error, _} = call(module, :new, [[first: "b"]])
    assert {:error, _} = call(module, :new, [[second: "a"]])
    assert call(module, :first_allowed, []) == ["b"]
    assert call(module, :second_allowed, []) == ["c"]
  end

  test "validators before inside and after a schema run in declaration order with guards" do
    compile(Strukt.Test.SchemaDeclarations.OrderedValidators, """
    validation :record, "a"
    validation :record, "b" when changeset.action == :insert
    defstruct do
      field :trace, :string, default: ""
      validation :record, "c"
    end
    validation :record, "d"
    defp record(cs, marker), do: put_change(cs, :trace, get_field(cs, :trace) <> marker)
    """)

    module = Strukt.Test.SchemaDeclarations.OrderedValidators
    assert {:ok, %{trace: "abcd"} = entity} = call(module, :new, [])
    assert %{trace: "abcdacd"} = call(module, :change, [entity]) |> Ecto.Changeset.apply_changes()
  end

  test "range keyword options supply a default message and empty set options accept custom messages" do
    compile(Strukt.Test.SchemaDeclarations.ValidationOptions, """
    defstruct do
      field :n, :integer, range: [value: 1..3]
      field :allowed, :string, one_of: [values: [], message: "no values allowed"]
      field :excluded, :string, none_of: [values: []]
      field :subset, {:array, :string}, subset_of: [values: [], message: "empty only"]
    end
    """)

    assert {:error, cs} =
             call(Strukt.Test.SchemaDeclarations.ValidationOptions, :new, [
               [n: 4, allowed: "x", excluded: "x", subset: ["x"]]
             ])

    assert {"must be in the range 1..3", _} = cs.errors[:n]
    assert {"no values allowed", _} = cs.errors[:allowed]
    assert {"empty only", _} = cs.errors[:subset]
    refute Keyword.has_key?(cs.errors, :excluded)
  end

  test "primary key false on fields preserves custom and disabled schema primary keys" do
    for {module, primary_key, expected} <- [
          {Strukt.Test.SchemaDeclarations.CustomKey, "{:id, :binary_id, autogenerate: true}",
           [:id]},
          {Strukt.Test.SchemaDeclarations.NoKey, "false", []}
        ] do
      compile(
        module,
        "@primary_key #{primary_key}\ndefstruct do\nfield :n, :integer, primary_key: false\nend"
      )

      assert call(module, :__schema__, [:primary_key]) == expected
    end
  end

  test "field primary key flags may reference schema constants" do
    for {module, flag, expected} <- [
          {Strukt.Test.SchemaDeclarations.TrueKeyFlag, true, [:n]},
          {Strukt.Test.SchemaDeclarations.FalseKeyFlag, false, [:uuid]}
        ] do
      compile(module, """
      defstruct do
        @key? #{flag}
        field :n, :integer, primary_key: @key?
      end
      """)

      assert call(module, :__schema__, [:primary_key]) == expected
    end
  end
end
