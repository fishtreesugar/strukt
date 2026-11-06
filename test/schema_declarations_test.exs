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

  defp field_types(beam) do
    {:ok, types} = Code.Typespec.fetch_types(beam)

    {:type, {:t, {:type, _, :map, fields}, []}} =
      Enum.find(types, fn {_, {name, _, _}} -> name == :t end)

    Map.new(fields, fn {:type, _, :map_field_exact, [{:atom, _, name}, type]} ->
      {name, Macro.to_string(Code.Typespec.type_to_quoted({name, type, []}))}
    end)
  end

  test "default UUID keys have a nullable Ecto UUID typespec" do
    [{_, beam}] =
      compile(Strukt.Test.SchemaDeclarations.UUIDType, "defstruct do\nfield :name, :string\nend")

    assert field_types(beam).uuid == "uuid() :: Ecto.UUID.t() | nil"
  end

  for {name, type, expected} <- [
        {"Integer", ":integer", "integer()"},
        {"Binary", ":binary_id", "binary()"},
        {"UUID", "Ecto.UUID", "Ecto.UUID.t()"},
        {"Custom", "Strukt.Test.SchemaOptions.CustomID", "binary()"},
        {"Parameterized", "Strukt.Test.SchemaOptions.ParamID", "binary()"}
      ] do
    test "attribute-defined #{name} primary keys retain their types" do
      module = Module.concat(Strukt.Test.SchemaDeclarations, "Attribute#{unquote(name)}Type")

      [{_, beam}] =
        compile(module, """
        @primary_key {:id, #{unquote(type)}, autogenerate: false}
        defstruct do
          field :name, :string
        end
        """)

      assert field_types(beam).id == "id() :: #{unquote(expected)} | nil"
    end
  end

  test "default timestamps have nullable NaiveDateTime types" do
    [{_, beam}] =
      compile(Strukt.Test.SchemaDeclarations.TimestampTypes, """
      defstruct do
        field :name, :string
        timestamps()
      end
      """)

    assert field_types(beam).inserted_at == "inserted_at() :: NaiveDateTime.t() | nil"
    assert field_types(beam).updated_at == "updated_at() :: NaiveDateTime.t() | nil"
  end

  test "ID types include the negative integers accepted by casting" do
    for {suffix, body} <- [
          {"Attribute",
           "@primary_key {:id, :id, autogenerate: false}\ndefstruct do\nfield :name, :string\nend"},
          {"Field", "defstruct do\nfield :id, :id, primary_key: true\nend"}
        ] do
      module = Module.concat(Strukt.Test.SchemaDeclarations, "#{suffix}IDRange")
      [{_, beam}] = compile(module, body)
      assert {:ok, %{id: -1}} = call(module, :new, [[id: -1]])
      assert field_types(beam).id == "id() :: integer() | nil"
    end
  end

  test "generated field types retain virtual and required fields without making timestamps castable" do
    module = Strukt.Test.SchemaDeclarations.GeneratedFieldTypes

    [{_, beam}] =
      compile(module, """
      @primary_key false
      defstruct do
        field :name, :string, required: true
        field :trace, :integer, default: 0, virtual: true
        timestamps(type: :utc_datetime)
      end
      """)

    types = field_types(beam)
    refute Map.has_key?(types, :uuid)
    assert types.name == "name() :: String.t()"
    assert types.trace == "trace() :: integer() | nil"
    assert types.inserted_at == "inserted_at() :: DateTime.t() | nil"

    cs = call(module, :changeset, [struct(module), %{name: "valid", inserted_at: "not a date"}])
    assert cs.valid?
    refute Map.has_key?(cs.changes, :inserted_at)
  end

  test "timestamp types respect declaration context, renamed fields and disabled fields" do
    [{_, beam}] =
      compile(Strukt.Test.SchemaDeclarations.RenamedTimestampTypes, """
      defstruct do
        @timestamps_opts [type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false]
        timestamps()
        @timestamps_opts [type: :naive_datetime]
      end
      """)

    types = field_types(beam)
    assert types.created_at == "created_at() :: DateTime.t() | nil"
    refute Map.has_key?(types, :inserted_at)
    refute Map.has_key?(types, :updated_at)
  end

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

    assert {:type, _, :map, [{:type, _, :map_field_assoc, [{:type, _, :any, []}, value]}]} =
             map

    assert {:type, _, :union, [{:type, _, :integer, []}, {:atom, _, nil}]} = value
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

  test "primary key flags are evaluated at their field declaration" do
    compile(Strukt.Test.SchemaDeclarations.ReassignedKey, """
    defstruct do
      @key? false
      field :name, :string
      @key? true
      field :key, :integer, primary_key: @key?
    end
    """)

    assert call(Strukt.Test.SchemaDeclarations.ReassignedKey, :__schema__, [:primary_key]) == [
             :key
           ]
  end

  test "primary key constants after a validator are available before fields" do
    compile(Strukt.Test.SchemaDeclarations.ValidatorKey, """
    defstruct do
      validation :pass
      @key? true
      field :key, :integer, primary_key: @key?
    end
    defp pass(cs,_), do: cs
    """)

    assert call(Strukt.Test.SchemaDeclarations.ValidatorKey, :__schema__, [:primary_key]) == [
             :key
           ]
  end

  test "binary_id primary keys autogenerate on direct construction" do
    compile(Strukt.Test.SchemaDeclarations.DirectID, """
    @primary_key {:id, :binary_id, autogenerate: true}
    defstruct do
      field :name, :string
    end
    """)

    assert {:ok, %{id: id}} = call(Strukt.Test.SchemaDeclarations.DirectID, :new, [])
    assert is_binary(id)
    assert {:ok, ^id} = Ecto.UUID.cast(id)
  end

  test "binary_id primary keys autogenerate inside ordinary embeds" do
    compile(Strukt.Test.SchemaDeclarations.NestedID, """
    @primary_key {:id, :binary_id, autogenerate: true}
    defstruct do
      field :name, :string
    end
    """)

    compile(Strukt.Test.SchemaDeclarations.IDContainer, """
    defstruct do
      embeds_one :child, Strukt.Test.SchemaDeclarations.NestedID, on_replace: :delete
    end
    """)

    assert {:ok, %{child: %{id: id}}} =
             call(Strukt.Test.SchemaDeclarations.IDContainer, :new, [[child: %{}]])

    assert is_binary(id)
  end

  test "type declarations do not delay constants needed by following fields" do
    compile(Strukt.Test.SchemaDeclarations.TypeConstant, """
    defstruct do
      @type value :: String.t()
      @allowed ["a"]
      field :name, :string, one_of: @allowed
    end
    """)

    assert {:ok, _} = call(Strukt.Test.SchemaDeclarations.TypeConstant, :new, [[name: "a"]])
  end

  test "field options and validation expressions are evaluated once at their declaration" do
    compile(Strukt.Test.SchemaDeclarations.EvaluateOnce, """
    defstruct do
      @key? true
      field :key, :integer, primary_key: (send(self(), :key_option); @key?)
      field :name, :string,
        default: (send(self(), :default_option); "a"),
        one_of: (send(self(), :validation_option); ["a"])
      @key? false
      field :other, :string, primary_key: @key?
    end
    """)

    module = Strukt.Test.SchemaDeclarations.EvaluateOnce
    assert call(module, :__schema__, [:primary_key]) == [:key]
    assert {:ok, %{name: "a"}} = call(module, :new, [])
    assert {:error, _} = call(module, :new, [[name: "b"]])

    for message <- [:key_option, :default_option, :validation_option] do
      assert_received ^message
      refute_received ^message
    end
  end

  test "schema-level attributes retain leading constants when later fields redefine them" do
    compile(Strukt.Test.SchemaDeclarations.SchemaConstant, """
    defstruct do
      @id_type :binary_id
      @primary_key {:id, @id_type, autogenerate: true}
      field :name, :string
      @id_type :integer
      field :count, @id_type
    end
    """)

    module = Strukt.Test.SchemaDeclarations.SchemaConstant
    assert call(module, :__schema__, [:type, :id]) == :binary_id
    assert call(module, :__schema__, [:type, :count]) == :integer
  end

  test "binary_id generation preserves supplied IDs and existing nested IDs" do
    compile(Strukt.Test.SchemaDeclarations.SourcedID, """
    @primary_key {:id, :binary_id, autogenerate: true, source: :ID}
    defstruct do
      field :name, :string
    end
    """)

    compile(Strukt.Test.SchemaDeclarations.IDList, """
    defstruct do
      embeds_many :children, Strukt.Test.SchemaDeclarations.SourcedID, on_replace: :delete
    end
    """)

    module = Strukt.Test.SchemaDeclarations.SourcedID
    id = Ecto.UUID.generate()
    assert {:ok, %{id: ^id}} = call(module, :new, [[ID: id]])
    assert {:ok, %{id: nil}} = call(module, :new, [[id: nil]])

    assert {:ok, parent} = call(Strukt.Test.SchemaDeclarations.IDList, :new, [[children: [%{}]]])
    [child] = parent.children
    assert is_binary(child.id)

    cs =
      call(Strukt.Test.SchemaDeclarations.IDList, :change, [parent, [children: [%{name: "next"}]]])

    assert cs.valid?
    assert [%{id: existing_id, name: "next"}] = Ecto.Changeset.apply_changes(cs).children
    assert existing_id == child.id
  end

  test "generated collection types include the nil values accepted by casting" do
    [{_, beam}] =
      compile(Strukt.Test.SchemaDeclarations.Nullable, """
      defstruct do
        field :values, {:map, :integer}, required: true
        field :items, {:array, :integer}, required: true
      end
      """)

    assert {:ok, _} =
             call(Strukt.Test.SchemaDeclarations.Nullable, :new, [
               [values: %{"x" => nil}, items: [1, nil]]
             ])

    {:ok, [{:type, {:t, {:type, _, :map, fields}, []}}]} = Code.Typespec.fetch_types(beam)

    types =
      Map.new(fields, fn {:type, _, :map_field_exact, [{:atom, _, key}, type]} -> {key, type} end)

    {:type, _, :map, [{:type, _, _, [_, map_value]}]} = types.values
    {:type, _, :list, [array_item]} = types.items
    assert nilable?(map_value)
    assert nilable?(array_item)
  end

  defp nilable?({:atom, _, nil}), do: true
  defp nilable?({:type, _, :union, types}), do: Enum.any?(types, &nilable?/1)
  defp nilable?(_), do: false

  test "schema redaction is captured at each field declaration" do
    m = Strukt.Test.SchemaOptions.Redaction
    assert call(m, :__schema__, [:redact_fields]) == [:secret]
    refute inspect(struct(m, secret: "example-secret")) =~ "example-secret"
  end

  for type <- [Strukt.Test.SchemaOptions.CustomID, Strukt.Test.SchemaOptions.ParamID] do
    test "#{inspect(type)} invokes its primary key generator" do
      m = Module.concat(unquote(type), :Schema)

      compile(
        m,
        "@primary_key {:id, #{inspect(unquote(type))}, autogenerate: true}\ndefstruct do\nfield :name, :string\nend"
      )

      assert {:ok, %{id: id}} = call(m, :new, [])
      assert is_binary(id)
    end
  end

  test "a grouped timestamp generator runs once and shares its result" do
    m = Strukt.Test.SchemaOptions.Timestamps

    compile(m, """
    @timestamps_opts [type: :utc_datetime, autogenerate: {Strukt.Test.SchemaOptions.Counter, :next, []}]
    defstruct do
      field :name, :string
      timestamps()
    end
    """)

    Process.put(Strukt.Test.SchemaOptions.Counter, 0)
    assert {:ok, t} = call(m, :new, [])
    assert t.inserted_at == t.updated_at
    assert Process.get(Strukt.Test.SchemaOptions.Counter) == 1
  end

  test "alias rebinding only affects following fields" do
    m = Strukt.Test.SchemaOptions.Aliases

    compile(m, """
    defstruct do
      alias Strukt.Test.SchemaOptions.Child, as: Item
      embeds_one :first, Item
      alias Strukt.Test.SchemaOptions.NoKey, as: Item
      embeds_one :second, Item
    end
    """)

    assert call(m, :__schema__, [:embed, :first]).related == Strukt.Test.SchemaOptions.Child
  end

  test "constants following a function are available to subsequent fields" do
    m = Strukt.Test.SchemaOptions.FunctionOrder

    compile(m, """
    defstruct do
      def helper, do: :ok
      @allowed ["a"]
      field :name, :string, one_of: @allowed
    end
    """)

    assert {:ok, _} = call(m, :new, [[name: "a"]])
  end

  test "schema attributes can use preceding constants between fields" do
    m = Strukt.Test.SchemaOptions.SchemaAttr

    compile(m, """
    defstruct do
      field :name, :string
      @precision :utc_datetime_usec
      @timestamps_opts [type: @precision]
      timestamps()
    end
    """)

    assert call(m, :__schema__, [:type, :inserted_at]) == :utc_datetime_usec
  end

  test "validation guards capture attributes at the validation declaration" do
    m = Strukt.Test.SchemaOptions.Guard

    compile(m, """
    @enabled true
    validation :reject when @enabled
    @enabled false
    def enabled?, do: @enabled
    defstruct do
      field :name, :string
    end
    defp reject(cs, _), do: add_error(cs, :name, "rejected")
    """)

    assert {:error, _} = call(m, :new, [[name: "a"]])
    refute call(m, :enabled?, [])
  end

  for {kind, declaration} <- [
        {:field, "@opts [default: \"a\", required: true]\nfield :name, :string, @opts"},
        {:embed,
         "@opts [on_replace: :update]\nembeds_one :child, Strukt.Test.SchemaOptions.Child, @opts"}
      ] do
    test "#{kind} options may be supplied by a module attribute" do
      m = Module.concat(Strukt.Test.SchemaOptions, "Options#{unquote(kind)}")
      compile(m, "defstruct do\n#{unquote(declaration)}\nend")
      assert {:ok, _} = call(m, :new, [])
    end
  end

  test "field without an explicit type defaults to string" do
    m = Strukt.Test.SchemaOptions.DefaultType
    compile(m, "defstruct do\nfield :name\nend")
    assert {:ok, %{name: "a"}} = call(m, :new, [[name: "a"]])
  end

  test "an attribute-only schema can disable its primary key" do
    m = Strukt.Test.SchemaOptions.AttributeOnly
    compile(m, "defstruct do\n@primary_key false\nend")
    assert call(m, :__schema__, [:primary_key]) == []
  end

  test "deferred functions retain self struct defaults, aliases, attributes and quoted code" do
    m = Strukt.Test.SchemaOptions.FunctionContext

    compile(m, ~S'''
    defstruct do
      @label "first"
      alias Strukt.Test.SchemaOptions.Child, as: Item
      field :name, :string, default: @label
      @doc @label
      def build(value \\ %__MODULE__{}), do: {value, @label, struct(Item)}
      @label "second"
      alias Strukt.Test.SchemaOptions.NoKey, as: Item
      field :other, :string, default: @label
      def second, do: {@label, struct(Item)}
      def quoted, do: quote(do: @label)
      def unquoted, do: quote(do: unquote(@label))
      def bound, do: quote(bind_quoted: [label: @label], do: label)
      @unquote? true
      def flagged, do: quote(unquote: @unquote?, do: unquote(@label))
      @label "third"
      def third, do: @label
      field :last, :string, default: @label
    end
    ''')

    assert {%{name: "first", other: "second"}, "first", %Strukt.Test.SchemaOptions.Child{}} =
             call(m, :build, [])

    assert {"second", %Strukt.Test.SchemaOptions.NoKey{}} = call(m, :second, [])
    assert {:@, _, [{:label, _, _}]} = call(m, :quoted, [])
    assert call(m, :unquoted, []) == "second"
    assert {"second", _} = Code.eval_quoted(call(m, :bound, []))
    assert call(m, :flagged, []) == "second"
    assert call(m, :third, []) == "third"
  end

  test "functions after fields can construct and return their completed struct" do
    m = Strukt.Test.SchemaOptions.StructBody

    compile(m, """
    defstruct do
      field :name, :string, default: "ready"
      def helper, do: :ok
      @example "ready"
      def example, do: %__MODULE__{name: @example}
    end
    """)

    assert %{name: "ready"} = call(m, :example, [])
  end

  test "binary ID types without a generator cast the generated UUID through their type" do
    m = Strukt.Test.SchemaOptions.FallbackID

    compile(m, """
    @primary_key {:id, Strukt.Test.SchemaOptions.BareID, autogenerate: true}
    defstruct do
      field :name
    end
    """)

    assert {:ok, %{id: id}} = call(m, :new, [])
    assert {:ok, ^id} = Ecto.UUID.cast(id)
    assert_received {:id_cast, ^id}
  end

  test "field source mapper and timestamp options are captured per declaration" do
    m = Strukt.Test.SchemaOptions.FieldContext

    compile(m, """
    @primary_key false
    defstruct do
      @field_source_mapper fn name -> String.to_atom("first_" <> Atom.to_string(name)) end
      field :name, :string
      @field_source_mapper fn name -> String.to_atom("next_" <> Atom.to_string(name)) end
      field :label, :string
      @timestamps_opts [type: :utc_datetime_usec]
      timestamps()
      @timestamps_opts [type: :naive_datetime]
    end
    """)

    assert call(m, :__schema__, [:field_source, :name]) == :first_name
    assert call(m, :__schema__, [:field_source, :label]) == :next_label
    assert call(m, :__schema__, [:type, :inserted_at]) == :utc_datetime_usec
  end

  test "dynamic field and inline embed options evaluate once in source order" do
    m = Strukt.Test.SchemaOptions.DynamicOptions

    compile(m, """
    defstruct do
      field :name, :string,
        (send(self(), :options); [default: "a", one_of: ["a"]])
      @opts [on_replace: :update, required: true]
      embeds_one :child, Child, @opts do
        field :name
      end
    end
    """)

    assert_received :options
    refute_received :options
    assert {:error, cs} = call(m, :new, [])
    assert Keyword.has_key?(cs.errors, :child)

    assert {:ok, %{name: "a", child: %{name: "child"}}} =
             call(m, :new, [[child: %{name: "child"}]])

    assert {:error, _} = call(m, :new, [[name: "b", child: %{name: "child"}]])
  end
end
