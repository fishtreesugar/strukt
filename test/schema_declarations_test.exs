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
end
