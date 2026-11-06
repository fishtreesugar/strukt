defmodule Strukt.SchemaGenerationTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  alias Strukt.Test.Lifecycle.{
    Child,
    DeriveBefore,
    DerivesBare,
    DerivesExcept,
    DerivesOnly
  }

  defp compile(name, body) do
    Code.compile_string("defmodule #{name} do\nuse Strukt\n#{body}\nend")
  end

  defp call(module, function, args), do: apply(module, function, args)

  describe "@derives" do
    test "accepts a bare Jason.Encoder" do
      assert Jason.decode!(Jason.encode!(%DerivesBare{name: "name"})) == %{
               "uuid" => nil,
               "name" => "name"
             }
    end

    test "supports only and except options" do
      value = %DerivesOnly{uuid: "id", name: "name", secret: "secret"}
      assert Jason.decode!(Jason.encode!(value)) == %{"NAME" => "name"}
      refute inspect(value) =~ "secret"

      value = %DerivesExcept{uuid: "id", name: "name", secret: "secret"}
      assert Jason.decode!(Jason.encode!(value)) == %{"uuid" => "id", "name" => "name"}
    end

    test "rejects invalid encoder options and unknown fields" do
      assert_raise ArgumentError, ~r/invalid Jason.Encoder options/, fn ->
        compile(Strukt.SchemaGenerationTest.BadDerive, """
        @derives [{Jason.Encoder, only: [:name], except: [:name]}]
        defstruct do
          field :name, :string
        end
        """)
      end

      assert_raise ArgumentError, ~r/not defined in the schema: \[:missing\]/, fn ->
        compile(Strukt.SchemaGenerationTest.UnknownDerive, """
        @derives [{Jason.Encoder, only: [:missing]}]
        defstruct do
          field :name, :string
        end
        """)
      end
    end

    test "@derive before defstruct is applied once" do
      refute inspect(%DeriveBefore{name: "name", secret: "secret"}) =~ "secret"

      stderr =
        capture_io(:stderr, fn ->
          compile(Strukt.SchemaGenerationTest.DeriveOnce, """
          @derive {Inspect, only: [:name]}
          defstruct do
            field :name, :string
          end
          """)
        end)

      refute stderr =~ "redefining"
    end
  end

  describe "generated functions" do
    test "from_json/1 returns an error for non-object JSON" do
      for json <- ["null", "[1]", "1", ~s("text")] do
        assert {:error, %ArgumentError{message: "expected a JSON object" <> _}} =
                 Child.from_json(json)
      end

      assert {:error, %Jason.DecodeError{}} = Child.from_json("{")
      assert {:ok, %Child{name: "json"}} = Child.from_json(~s({"name": "json"}))
    end

    test "user-defined changeset/2 replaces the generated clauses" do
      stderr =
        capture_io(:stderr, fn ->
          compile(Strukt.SchemaGenerationTest.CustomChangeset, """
          defstruct do
            field :name, :string
          end

          def changeset(entity, params) do
            entity |> changeset(params, nil) |> Ecto.Changeset.put_change(:name, "custom")
          end
          """)
        end)

      refute stderr =~ "warning"
      module = Strukt.SchemaGenerationTest.CustomChangeset
      entity = struct(module)
      assert call(module, :changeset, [entity, %{name: "x"}]).changes.name == "custom"
      assert call(module, :changeset, [entity]).changes.name == "custom"
      assert {:ok, %{name: "x"}} = call(module, :new, [[name: "x"]])
    end
  end

  describe "overriding from_json/1" do
    test "super loads schema types and sources and preserves error results" do
      module = Strukt.SchemaGenerationTest.CustomFromJson

      stderr =
        capture_io(:stderr, fn ->
          compile(module, """
          defstruct do
            field :name, :string, source: :NAME, required: true
            timestamps()
          end

          def from_json(input) do
            with {:ok, value} <- super(input) do
              {:ok, %{value | name: String.trim(value.name || "")}}
            end
          end
          """)
        end)

      assert stderr == ""

      assert {:ok, %{__struct__: ^module, name: "Alice", uuid: nil, inserted_at: inserted_at}} =
               call(module, :from_json, [
                 [~s({"NAME":" Alice ",), ~s("inserted_at":"2026-01-02T03:04:05"})]
               ])

      assert inserted_at == ~N[2026-01-02 03:04:05]
      assert {:ok, %{name: "", uuid: nil, inserted_at: nil}} = call(module, :from_json, ["{}"])
      assert {:error, %Jason.DecodeError{}} = call(module, :from_json, ["{"])

      for json <- ["null", "[]", "42", "true", ~s("text")] do
        assert {:error, %ArgumentError{message: "expected a JSON object" <> _}} =
                 call(module, :from_json, [json])
      end

      assert_raise ArgumentError, fn -> call(module, :from_json, [~s({"NAME":123})]) end
    end

    test "super works in an override between schema fields" do
      module = Strukt.SchemaGenerationTest.InlineFromJson

      compile(module, """
      defstruct do
        field :name, :string
        @prefix "inline "

        def from_json(input) do
          with {:ok, value} <- super(input), do: {:ok, %{value | name: @prefix <> value.name}}
        end

        field :count, :integer
      end
      """)

      assert {:ok, %{__struct__: ^module, name: "inline json", count: 2}} =
               call(module, :from_json, [~s({"name":"json","count":2})])
    end

    test "super works in named defstruct blocks" do
      compile(Strukt.SchemaGenerationTest.NamedFromJson, """
      defstruct Record do
        field :name, :string

        def from_json(input), do: {:wrapped, super(input)}
      end
      """)

      module = Strukt.SchemaGenerationTest.NamedFromJson.Record

      assert {:wrapped, {:ok, %{__struct__: ^module, name: "json"}}} =
               call(module, :from_json, [~s({"name":"json"})])

      assert {:wrapped, {:error, %Jason.DecodeError{}}} = call(module, :from_json, ["{"])
    end

    test "a custom loader defined before defstruct is kept without merging clauses" do
      module = Strukt.SchemaGenerationTest.EarlyFromJson

      stderr =
        capture_io(:stderr, fn ->
          compile(module, """
          def from_json(input), do: {:custom, input}

          defstruct do
            field :name, :string
          end
          """)
        end)

      assert stderr == ""
      assert {:custom, "{}"} = call(module, :from_json, ["{}"])
    end
  end
end
