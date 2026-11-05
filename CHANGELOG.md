# 0.4.1

- Fixed explicit `nil` updates for ordinary and polymorphic embeds: single embeds clear,
  and embed collections normalize `nil` to `[]`. List elements cannot be `nil`.
  Unlike 0.4.0, clearing existing embeds now observes `on_replace` and required validation;
  configurations such as `on_replace: :raise` may reject previously ignored updates.
- Omitted fields are no longer resubmitted for casting, preserving stored empty strings
  and pending embedded values across partial changeset updates.
- Fixed source-mapped fields being lost when schema structs are supplied as parameters.
- Fixed `required: false` incorrectly enabling required validation.
- Fixed generated types: optional fields remain nullable regardless of their defaults,
  and keyword-form required declarations are recognized for fields and single embeds.
- Added a polymorphic embeds guide with schema, update, validation, and JSON examples.
- Documented parameter precedence, nil and empty-list behavior, and differences between
  `new`/`change`, direct changeset APIs, and JSON loading.
- Updated ExDoc to 0.40.4 and refreshed its Markdown and syntax-highlighting dependencies.
- Included guides in the Hex package and linked documentation source to the release tag.

# 0.4.0

First release of the `strukt_fork` Hex package, maintained by fishtreesugar and based on
upstream Strukt 0.3.2. The OTP application is still `:strukt`, and existing modules can
continue to `use Strukt`.

- Added support for polymorphic embeds via `polymorphic_embed`.
- Fixed polymorphic embeds to return field errors for invalid input shapes and undeclared structs.
  Polymorphic embed lists now cast a mix of declared structs and parameter maps in input order.
- Fixed field updates so an explicit `nil` clears an optional field and omitted fields keep their values.
  Fields with a custom `source:` accept either the schema field name or the source name.
- Fixed handling of invalid embed parameters, including scalar values passed to `embeds_many`.
- Fixed typespec generation for fields that reference types from other modules.
- Updated the Elixir requirement to `~> 1.17` and the Ecto requirement to `~> 3.12`.
  Jason is now a required dependency (`~> 1.4`).

# 0.3.1

- FIXED: Improved generation of typespecs

# 0.3.0

- ADDED: Support for reusable validation rules via the `Strukt.Validator` behavior
- ADDED: Support for describing validation pipelines for structs using the `validation/1` and `validation/2` macros
- BREAKING CHANGE: When overriding the `validate/1` callback, users must now explicitly call `super/1` to ensure inline
validations are applied (as well as the validation pipeline, but that is newly added). Previously, inline validations
would be run regardless of whether a user overrode `validate/1`
