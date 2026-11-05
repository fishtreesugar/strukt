# Modified from upstream by the maintainers of the fishtreesugar/strukt fork.

defmodule Strukt do
  import Kernel, except: [defstruct: 1, defstruct: 2]

  @doc """
  See `c:new/1`
  """
  @callback new() :: {:ok, struct()} | {:error, Ecto.Changeset.t()}

  @doc """
  This callback can be overridden to provide custom initialization behavior.

  The default implementation provided for you performs all of the necessary
  validation and autogeneration of fields with those options set.

  NOTE: It is critical that if you do override this callback, that you call
  `super/1` to run the default implementation at some point in your implementation.
  """
  @callback new(Keyword.t() | map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}

  @doc """
  See `c:change/2`
  """
  @callback change(Ecto.Changeset.t() | term()) :: Ecto.Changeset.t()

  @doc """
  This callback can be overridden to provide custom change behavior.

  The default implementation provided for you creates a changeset and applies
  all of the inline validations defined on the schema.

  NOTE: It is recommended that if you need to perform custom validations, that
  you use the `validation/1` and `validation/2` facility for performing custom
  validations in a module or function, and if necessary, override `c:validate/1` 
  instead of performing validations in this callback. If you need to override this 
  callback specifically for some reason, make sure you call `super/2` at some point during
  your implementation to ensure that validations are run.
  """
  @callback change(Ecto.Changeset.t() | term(), Keyword.t() | map()) :: Ecto.Changeset.t()

  @doc """
  This callback can be overridden to manually implement your own validation logic.

  The default implementation handles invoking the validation rules expressed inline
  or via the `validation/1` and `validation/2` macros. You may still invoke the default
  validations from your own implementation using `super/1`.

  This function can be called directly on a changeset, and is automatically invoked
  by the default `new/1` and `change/2` implementations.
  """
  @callback validate(Ecto.Changeset.t()) :: Ecto.Changeset.t()

  @field_types [
    :field,
    :embeds_one,
    :embeds_many,
    :polymorphic_embeds_one,
    :polymorphic_embeds_many,
    :belongs_to,
    :has_many,
    :has_one,
    :many_to_many,
    :timestamps
  ]

  @definition_types [
    :def,
    :defp,
    :defmacro,
    :defmacrop,
    :defdelegate,
    :defguard,
    :defguardp,
    :defoverridable
  ]

  @schema_attrs [
    :primary_key,
    :schema_prefix,
    :foreign_key_type,
    :timestamps_opts,
    :derive,
    :field_source_mapper
  ]

  defmacro __using__(_) do
    quote do
      Strukt.__register_validators__(__MODULE__)
      import Kernel, except: [defstruct: 1, defstruct: 2, validation: 1, validation: 2]
      import unquote(__MODULE__), only: :macros
    end
  end

  @doc false
  def __register_validators__(module) do
    unless Module.has_attribute?(module, :strukt_validators) do
      Module.register_attribute(module, :strukt_validators, accumulate: true)
    end
  end

  @doc """
  Defines a validation rule for the current struct validation pipeline.

  A validation pipeline is constructed by expressing the rules in the order
  in which you want them applied, from top down. The validations may be defined
  anywhere in the module, but the order of application is always top down.

  You may define either module validators or function validators, much like `Plug.Builder`.
  For module validators, the module is expected to implement the `Strukt.Validator` behavior,
  consisting of the `init/1` and `validate/2` callbacks. For function validators, they are
  expected to be of arity 2. Both the `validate/2` callback and function validators receive
  the changeset to validate/manipulate as their first argument, and options passed to the
  `validation/2` macro, if provided.

  ## Guards

  Validation rules that should be applied conditionally can either handle the conditional
  logic in their implementation, or if simple, can use guards to express this instead, which
  can be more efficient.

  Guards may use the changeset being validated in their conditions by referring to `changeset`.
  See the example below to see how these can be expressed.

  ## Example

      defmodule Upload do
        use Strukt

        @allowed_content_types ["application/json", "application/pdf", "text/csv"]

        defstruct do
          field :filename, :string
          field :content, :binary, default: <<>>
          field :content_type, :string, required: true
        end

        # A simple function validator, expects a function in the same module
        validation :validate_filename

        # A function validator with a guard clause, only applied when the guard is successful
        validation :validate_content_type when is_map_key(changeset.changes, :content_type)

        # A module validator with options
        validation MyValidations.EnsureContentMatchesType, @allowed_content_types

        # A validator with options and a guard clause
        validation :example, [foo: :bar] when changeset.action == :update

        defp validate_filename(changeset, _opts), do: changeset
      end
  """
  defmacro validation(validator, opts \\ [])

  defmacro validation(validator, {:when, meta, [opts | guards]}) do
    quote do
      Strukt.validation(unquote({:when, meta, [validator | guards]}), unquote(opts))
    end
  end

  defmacro validation({:when, _meta, [validator | guards]}, opts) do
    validator = Macro.expand(validator, %{__CALLER__ | function: {:init, 1}})

    quote do
      Strukt.__register_validators__(__MODULE__)

      @strukt_validators {unquote(validator), unquote(opts),
                          Strukt.Schema.capture_attributes(
                            unquote(Macro.escape(guards, unquote: true)),
                            __ENV__
                          )}
    end
  end

  defmacro validation(validator, opts) do
    validator = Macro.expand(validator, %{__CALLER__ | function: {:init, 1}})

    quote do
      Strukt.__register_validators__(__MODULE__)
      @strukt_validators {unquote(validator), unquote(opts), true}
    end
  end

  @doc ~S"""
  This variant of `defstruct` can accept a list of fields, just like `Kernel.defstruct/1`, in which
  case it simply defers to `Kernel.defstruct/1` and does nothing; or it can be passed a block
  containing an `Ecto.Schema` definition. The resulting struct/schema is defined in the current
  module scope, and will inherit attributes like `@derive`, `@primary_key`, etc., which are already
  defined in the current scope.

  ## Example

      defmodule Passthrough do
        use Strukt

        defstruct [:name]
      end

      defmodule Person do
        use Strukt

        @derive [Jason.Encoder]
        defstruct do
          field :name, :string
        end

        def say_hello(%__MODULE__{name: name}), do: "Hello #{name}!"
      end

  Above, even though `Strukt.defstruct/1` is in scope, it simply passes through the list of fields
  to `Kernel.defstruct/1`, as without a proper schema, there isn't much useful we can do. This allows
  intermixing uses of `defstruct/1` in the same scope without conflict.
  """
  defmacro defstruct(arg)

  defmacro defstruct(do: block) do
    define_struct(__CALLER__, nil, block)
  end

  defmacro defstruct(fields) do
    quote bind_quoted: [fields: fields] do
      Kernel.defstruct(fields)
    end
  end

  @doc ~S"""
  This variant of `defstruct` takes a module name and block containing a struct schema and
  any other module contents desired, and defines a new module with that name, generating
  a struct just like `Strukt.defstruct/1`.

  ## Example

      defmodule Entities do
        use Strukt

        defstruct Person do
          @derives [Jason.Encoder]

          field :name, :string

          def say_hello(%__MODULE__{name: name}), do: "Hello #{name}!"
        end
      end

  NOTE: Unlike `Strukt.defstruct/1`, which inherits attributes like `@derive` or `@primary_key` from
  the surrounding scope; this macro requires them to be defined in the body, as shown above.
  """
  defmacro defstruct(name, do: body) do
    define_struct(__CALLER__, name, body)
  end

  defp define_struct(_env, name, body) do
    {meta, nodes} =
      case body do
        {:__block__, meta, nodes} -> {meta, nodes}
        nil -> {[], []}
        node -> {[], [node]}
      end

    # A module body after its last field can use the completed struct directly.
    # Only definitions interleaved with later fields need deferred evaluation.
    last_field =
      nodes
      |> Enum.with_index()
      |> Enum.reduce(-1, fn
        {{type, _, _}, index}, last when type in @field_types -> max(index, last)
        _, last -> last
      end)

    tail_index =
      Enum.find_index(Enum.with_index(nodes), fn
        {{type, _, _}, index} -> type in @definition_types and index > last_field
        _ -> false
      end)

    {nodes, body} = Enum.split(nodes, tail_index || length(nodes))

    {declarations, fields} =
      Enum.map_reduce(nodes, [], fn
        {type, _, _} = declaration, fields when type in @field_types ->
          [field] = Strukt.Field.parse([declaration])
          value = Macro.unique_var(:strukt_field, __MODULE__)
          {prepare_field_ast(field, value), [{field, value} | fields]}

        {type, _, _} = definition, fields
        when type in @definition_types ->
          ast =
            quote do
              Strukt.Schema.defer(__MODULE__, unquote(Macro.escape(definition)), __ENV__)
            end

          {ast, fields}

        {:@, meta, [{attr, _, [value]}]}, fields when attr in [:doc, :impl, :deprecated] ->
          ast =
            quote do
              Strukt.Schema.defer_attribute(
                __MODULE__,
                unquote(attr),
                unquote(value),
                unquote(meta),
                __ENV__
              )
            end

          {ast, fields}

        declaration, fields ->
          {declaration, fields}
      end)

    fields = Enum.reverse(fields)

    cast_fields = for {%{type: :field}, value} <- fields, do: quote(do: unquote(value).name)

    cast_embed_fields =
      for {%{type: type}, value} <- fields,
          type in [:embeds_one, :embeds_many],
          do: quote(do: unquote(value).name)

    cast_polymorphic_embed_fields =
      for {%{type: type}, value} <- fields,
          type in [:polymorphic_embeds_one, :polymorphic_embeds_many],
          do: quote(do: unquote(value).name)

    fields_ast = for {field, value} <- fields, do: schema_field_ast(field, value)

    primary_key_options =
      for {%{type: :field}, value} <- fields,
          do: quote(do: Keyword.get(unquote(value).options, :primary_key, false))

    quoted =
      quote location: :keep do
        schema_attrs =
          unquote(@schema_attrs)
          |> Enum.map(&{&1, Module.get_attribute(__MODULE__, &1)})
          |> Enum.reject(fn {_, value} -> is_nil(value) end)

        use Ecto.Schema
        import Ecto.Changeset, except: [change: 2]
        @behaviour unquote(__MODULE__)
        @before_compile unquote(__MODULE__)
        Strukt.__register_validators__(__MODULE__)
        Strukt.Schema.register(__MODULE__)

        for {schema_attr, value} <- schema_attrs do
          Module.put_attribute(__MODULE__, schema_attr, value)
        end

        @validated_fields %{}
        unquote_splicing(declarations)

        defines_primary_key? = Enum.any?(unquote(primary_key_options), &(&1 == true))

        case Module.get_attribute(__MODULE__, :primary_key) do
          nil when not defines_primary_key? ->
            Module.put_attribute(__MODULE__, :primary_key, {:uuid, Ecto.UUID, autogenerate: true})

          _ when defines_primary_key? ->
            Module.put_attribute(__MODULE__, :primary_key, false)

          _ ->
            :ok
        end

        @schema_name Macro.underscore(__MODULE__)
        @cast_embed_fields unquote(cast_embed_fields)
        @cast_polymorphic_embed_fields unquote(cast_polymorphic_embed_fields)
        Module.put_attribute(
          __MODULE__,
          :cast_fields,
          case Module.get_attribute(__MODULE__, :primary_key) do
            false -> unquote(cast_fields)
            {pk, _, _} -> [pk | unquote(cast_fields)]
          end
        )

        derives = Module.get_attribute(__MODULE__, :derives) || []

        if Jason.Encoder in derives do
          Module.put_attribute(__MODULE__, :derives_jason, true)
          Module.put_attribute(__MODULE__, :derives, Enum.reject(derives, &(&1 == Jason.Encoder)))
        end

        embedded_schema do
          unquote({:__block__, meta, fields_ast})
        end

        @doc """
        Creates a `#{__MODULE__}`, using the provided params.

        This operation is fallible, so it returns `{:ok, t}` or `{:error, Ecto.Changeset.t}`.

        If this struct has an autogenerated primary key, it will be generated, assuming it
        was not provided in the set of params. By default, all structs generated by `defstruct`
        are given a primary key field of `:uuid`, which is autogenerated using `Ecto.UUID.generate/0`.
        See the docs for `defstruct` if you wish to change this.
        """
        @impl Strukt
        def new(params \\ %{})

        def new(params) do
          struct =
            struct(__MODULE__)
            |> Strukt.Autogenerate.generate()

          formed_params = Strukt.Params.transform(__MODULE__, params, struct)

          struct
          |> changeset(formed_params, :insert)
          |> from_changeset()
        end

        @doc """
        Prepares an `Ecto.Changeset` from a struct, or an existing `Ecto.Changeset`, by applying
        the provided params as changes. The resulting changeset is validated.

        Omitted fields retain their current values. Explicit `nil` clears ordinary fields
        and single embeds; `nil` or `[]` clears embed collections. Embed removal respects
        `on_replace`, and required validation still applies. Both schema field names and
        `source:` names are accepted, with source names taking precedence.

        See `from_changeset/1`, for converting the changeset back to a struct.
        """
        @impl Strukt
        def change(entity_or_changeset, params \\ %{})

        def change(entity_or_changeset, params) do
          case entity_or_changeset do
            %Ecto.Changeset{} = cs ->
              entity = Ecto.Changeset.apply_changes(cs)
              formed_params = Strukt.Params.transform(__MODULE__, params, entity)
              changeset(cs, formed_params, cs.action)

            %__MODULE__{} = entity ->
              formed_params = Strukt.Params.transform(__MODULE__, params, entity)
              changeset(entity, formed_params, :update)
          end
        end

        @doc """
        Validates a changeset for this type.
        """
        @impl Strukt
        def validate(changeset) do
          changeset
          |> __validate__()
          |> validator_builder_call([])
        end

        defoverridable unquote(__MODULE__)

        Strukt.Schema.emit_definitions(__MODULE__)
        unquote_splicing(body)
      end

    if is_nil(name) do
      quoted
    else
      quote do
        defmodule unquote(name) do
          unquote(quoted)
        end
      end
    end
  end

  defp prepare_field_ast(field, value) do
    child =
      if field.type in [:embeds_one, :embeds_many] and field.block != nil do
        quote do
          Strukt.defstruct unquote(field.value_type) do
            unquote(field.block)
          end
        end
      end

    quote do
      unquote(child)

      unquote(value) =
        Strukt.Schema.field(
          __MODULE__,
          unquote(field.name),
          unquote(field.value_type),
          unquote(field.type),
          unquote(field.options)
        )
    end
  end

  defp schema_field_ast(field, value) do
    declaration =
      case field.type do
        :timestamps ->
          quote do: timestamps(unquote(value).options)

        type when type in [:polymorphic_embeds_one, :polymorphic_embeds_many] ->
          many? = type == :polymorphic_embeds_many
          type = if many?, do: {:array, PolymorphicEmbed}, else: PolymorphicEmbed
          # These are the same field/default options supplied by PolymorphicEmbed's
          # macros, using the options already evaluated at the declaration site.
          quote do
            field(
              unquote(value).name,
              unquote(Macro.escape(type)),
              unquote(value).options
              |> Keyword.put_new(:array?, unquote(many?))
              |> Keyword.put_new(:default, unquote(if many?, do: [], else: nil))
            )
          end

        type ->
          {type, field.meta,
           [
             quote(do: unquote(value).name),
             quote(do: unquote(value).value_type),
             quote(do: unquote(value).options)
           ]}
      end

    quote do
      context = Strukt.Schema.context(__MODULE__)
      Strukt.Schema.restore_context(__MODULE__, unquote(value).context)
      unquote(declaration)
      Strukt.Schema.restore_context(__MODULE__, context)
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    schema_module = env.module
    validators = Module.get_attribute(env.module, :strukt_validators)

    {changeset, validate_body} = Strukt.Validator.Builder.compile(env, validators, [])

    quote location: :keep do
      # Injects the type spec for this module based on the schema
      typespec_ast =
        Strukt.Typespec.generate(%Strukt.Typespec{
          caller: __MODULE__,
          info: @validated_fields,
          fields: @cast_fields,
          embeds: @cast_embed_fields ++ @cast_polymorphic_embed_fields
        })

      Code.eval_quoted(typespec_ast, [], __ENV__)

      defp validator_builder_call(unquote(changeset), opts),
        do: unquote(validate_body)

      @doc """
      Generates an `Ecto.Changeset` for this type, using the provided params.

      Parameters use schema field names; unlike `new/1` and `change/2`, this function does
      not normalize `source:` aliases. It applies the same nil-clearing rules as `change/2`.

      This function automatically performs validations based on the schema, and additionally,
      it invokes `validate/1` in order to apply custom validations, if present.

      Use `from_changeset/1` to apply the changes in the changeset,
      and get back a valid instance of this type
      """
      @spec changeset(t) :: Ecto.Changeset.t()
      @spec changeset(t, Keyword.t() | map()) :: Ecto.Changeset.t()
      def changeset(%__MODULE__{} = entity, params \\ %{}) do
        changeset(entity, params, nil)
      end

      # This function is used to build and validate a changeset for the corresponding action.
      @doc false
      def changeset(%__MODULE__{} = entity, params, action)
          when action in [:insert, :update, :delete, nil] do
        params =
          case params do
            %__MODULE__{} ->
              Map.from_struct(params)

            m when is_map(m) ->
              m

            other ->
              Enum.into(other, %{})
          end

        cast(entity, params, @cast_fields)
        |> Map.put(:action, action)
        |> __cast_embeds__(Strukt.Params.supplied_fields(params, @cast_embed_fields))
        |> __cast_polymorphic_embeds__(
          Strukt.Params.supplied_fields(params, @cast_polymorphic_embed_fields)
        )
        |> validate()
      end

      def changeset(%Ecto.Changeset{data: %__MODULE__{}} = changeset, params, action)
          when action in [:insert, :update, :delete, nil] do
        params =
          case params do
            %__MODULE__{} ->
              Map.from_struct(params)

            m when is_map(m) ->
              m

            other ->
              Enum.into(other, %{})
          end

        cast(changeset, params, @cast_fields)
        |> Map.put(:action, action)
        |> __cast_embeds__(Strukt.Params.supplied_fields(params, @cast_embed_fields))
        |> __cast_polymorphic_embeds__(
          Strukt.Params.supplied_fields(params, @cast_polymorphic_embed_fields)
        )
        |> validate()
      end

      defp __cast_embeds__(changeset, []), do: changeset

      if length(@cast_embed_fields) > 0 do
        defp __cast_embeds__(%Ecto.Changeset{params: params} = changeset, [field | fields]) do
          # If we get a struct(s) in the params for an embed, there is no need to cast, presume validity and apply the change directly
          f = to_string(field)
          prev = Ecto.Changeset.fetch_field!(changeset, field)

          # Ensure a change can always be applied, whether inserting or updated
          changeset =
            case Map.fetch(params, f) do
              :error ->
                changeset

              {:ok, nil} ->
                Strukt.Params.clear_embed(changeset, field)

              {:ok, []} when is_list(prev) ->
                Ecto.Changeset.put_embed(changeset, field, [])

              {:ok, %_{} = entity} ->
                Strukt.Params.put_embed_struct(changeset, field, entity)

              {:ok, _other} ->
                # For all other parameters, we need to cast. Depending on how the embedded entity is configured, this may raise an error
                Strukt.Params.cast_embed(changeset, field)
            end

          __cast_embeds__(changeset, fields)
        end
      end

      defp __cast_polymorphic_embeds__(changeset, fields) do
        Enum.reduce(fields, changeset, &Strukt.Params.cast_polymorphic_embed/2)
      end

      @doc """
      Applies the changes if the changeset is valid, returning the updated data.
      This function checks validity; it does not require or change the action.

      Returns `{:ok, t}` or `{:error, Ecto.Changeset.t}`, depending on validity of the changeset
      """
      @spec from_changeset(Ecto.Changeset.t()) :: {:ok, t} | {:error, Ecto.Changeset.t()}
      def from_changeset(changeset)

      def from_changeset(%Ecto.Changeset{valid?: true} = cs),
        do: {:ok, Ecto.Changeset.apply_changes(cs)}

      def from_changeset(%Ecto.Changeset{} = cs), do: {:error, cs}

      @doc "Deserialize this type from a JSON string or iodata"
      @spec from_json(binary | iodata) :: {:ok, t} | {:error, reason :: term}
      def from_json(input) do
        with {:ok, map} <- Jason.decode(input, strings: :copy) do
          {:ok, Ecto.embedded_load(__MODULE__, map, :json)}
        end
      end

      # Generate the __validate__ function
      validate_ast = Strukt.Validation.generate(__MODULE__, @validated_fields)
      Code.eval_quoted(validate_ast, [], __ENV__)

      # Handle conditional implementation of Jason.Encoder
      if Module.get_attribute(__MODULE__, :derives_jason) do
        defimpl Jason.Encoder, for: unquote(schema_module) do
          def encode(value, opts) do
            value
            |> Strukt.JSON.dump()
            |> Jason.Encode.map(opts)
          end
        end
      end
    end
  end
end
