<!-- Modified from upstream by the maintainers of the fishtreesugar/strukt fork. -->

# JSON Support

Support for JSON serialization is built upon `Ecto.embedded_dump/2`, but must be explicitly enabled. This is to allow
you to provide your own implementation if you don't desire to use the generated one. However, deriving the
encoder is dead simple, and looks just like it would for any old struct. For example:

    # defstruct/1
    defmodule Person do
      @derives [Jason.Encoder]
      defstruct do
        field :name, :string

        timestamps()
      end
    end

    # defstruct/2
    defstruct Person do
      @derives [Jason.Encoder]

      field :name, :string

      timestamps()
    end

Internally, `defstruct` provides a concrete implementation of `Jason.Encoder` that calls out to `Ecto.embedded_dump/2`.
For deserialization, `from_json/1` is defined for the struct's module, and uses `Ecto.embedded_load/3` to deserialize 
back to the original struct using the canonical deserializer for each field type.

Unlike `new/1`, `from_json/1` loads stored representations directly. It does not run casting,
inline required checks, custom validations, or autogeneration. It can therefore return
`{:ok, struct}` with `nil` in a required field. Validate loaded data explicitly if those
constraints need to be enforced. Invalid JSON returns a decode error; valid JSON containing
values that Ecto cannot load can raise instead of returning a changeset error.

Missing JSON fields retain schema defaults. An explicit JSON `null` loads as `nil` for ordinary
fields and single embeds. For collections, the underlying loaders differ: `embeds_many` loads
`null` as `[]`, while `polymorphic_embeds_many` loads it as `nil`. Use JSON `[]` for an empty
collection of either kind. In contrast, `new/1`, `change/2`, and `changeset/2` normalize an explicit
nil collection parameter to `[]`.

A field's `source:` name is used both by the derived encoder and by `from_json/1`. For example,
`field :name, :string, source: :NAME` is encoded as `"NAME"`, and loading expects `"NAME"`.
The schema-name alias accepted by `new/1` and `change/2` is not an additional JSON loading alias.

Because JSON object keys are strings, maps passed to custom `c:Ecto.Type.load/1` callbacks are string-key maps. Strukt does
not atomize arbitrary JSON keys during `from_json/1`. Custom types that load nested maps should handle string keys, or
normalize their input internally, when they need to support JSON round-trips.

The difference versus just letting `@derives [Jason.Encoder]` do its thing, is that `embedded_dump/2` and `embedded_load/3`
ensure that the types are dumped/loaded according to their respective Ecto type definitions, which should produce canonical
JSON encodings, as opposed to naively encoding fields based on their raw Elixir representation.

NOTE: Currently, we only implement special support for `Jason.Encoder`, if you use another JSON library, it
is recommended that you implement the relevant encoder yourself using `Ecto.embedded_dump/2`, much like we do
for our implementation of `Jason.Encoder`.

For variant type tags and a complete JSON round-trip example, see
[Polymorphic Embeds](polymorphic-embeds.md#json-round-trips).
