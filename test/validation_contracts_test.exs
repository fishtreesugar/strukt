defmodule Strukt.ValidationContractsTest do
  use ExUnit.Case, async: true
  alias Strukt.Test.Lifecycle.Parent

  defp compile(name, body) do
    Code.compile_string("defmodule #{name} do\nuse Strukt\n#{body}\nend")
  end

  defp call(module, function, args), do: apply(module, function, args)

  test "updating a changeset preserves existing validation and business errors" do
    {:ok, parent} = Parent.new()

    cs =
      parent
      |> Parent.change(email: "bad")
      |> Ecto.Changeset.add_error(:email, "blocked by policy")

    corrected = Parent.change(cs, email: "good@example.com")
    refute corrected.valid?

    assert {"has invalid format", [validation: :format]} in Keyword.get_values(
             corrected.errors,
             :email
           )

    assert {"blocked by policy", []} in Keyword.get_values(corrected.errors, :email)
    assert Parent.change(parent, email: "good@example.com").valid?
  end

  describe "module validators" do
    test "init/1 runs once per validation, never while compiling" do
      compile(Strukt.ValidationContractsTest.CountingValidator, """
      use Strukt.Validator

      @impl true
      def init(opts) do
        Process.put(:strukt_init_calls, (Process.get(:strukt_init_calls) || 0) + 1)
        Keyword.put(opts, :initialized, true)
      end

      @impl true
      def validate(changeset, opts) do
        send(self(), {:validated, opts})
        changeset
      end
      """)

      compile(Strukt.ValidationContractsTest.CompileInit, """
      defstruct do
        field :name, :string
      end

      validation Strukt.ValidationContractsTest.CountingValidator, key: :value
      """)

      assert Process.get(:strukt_init_calls) == nil
      {:ok, _} = call(Strukt.ValidationContractsTest.CompileInit, :new, [[name: "a"]])
      {:ok, _} = call(Strukt.ValidationContractsTest.CompileInit, :new, [[name: "b"]])
      assert Process.get(:strukt_init_calls) == 2
      assert_received {:validated, [initialized: true, key: :value]}
    end

    test "init/1 may return an anonymous function" do
      compile(Strukt.ValidationContractsTest.FunValidator, """
      use Strukt.Validator

      @impl true
      def init(opts) do
        fn changeset ->
          send(self(), {:fun, opts})
          changeset
        end
      end

      @impl true
      def validate(changeset, fun), do: fun.(changeset)
      """)

      compile(Strukt.ValidationContractsTest.RuntimeInit, """
      defstruct do
        field :name, :string
      end

      validation Strukt.ValidationContractsTest.FunValidator, :opts
      """)

      {:ok, _} = call(Strukt.ValidationContractsTest.RuntimeInit, :new, [[name: "a"]])
      assert_received {:fun, :opts}
    end
  end

  test "range preserves integer membership and number supports continuous bounds" do
    module = Strukt.ValidationContractsTest.NumericBounds

    compile(module, """
    defstruct do
      field :step, :integer, range: 0..100//2
      field :member, :float, range: 0..100
      field :float, :float, number: [greater_than_or_equal_to: 0, less_than_or_equal_to: 100]
      field :decimal, :decimal, number: [greater_than_or_equal_to: 0, less_than_or_equal_to: 100]
    end
    """)

    assert {:ok, _} = call(module, :new, [[step: 50, float: 50.5, decimal: "50.5"]])

    for params <- [[step: 51], [member: 50.5], [float: 100.5], [decimal: "100.5"]] do
      assert {:error, _} = call(module, :new, [params])
    end
  end
end
