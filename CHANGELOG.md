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
