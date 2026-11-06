# 0.4.2

- Restore source-name mapping and nested normalization for string-keyed pair-list parameters,
  including map entries returned by `Enum.filter/2` and `Enum.reject/2`. Ordinary embedded
  records accept pair lists through both normalized and direct changeset APIs.
- Report malformed top-level parameters with `Ecto.CastError`, and preserve Ecto's `:invalid`
  sentinel as an invalid changeset instead of raising an Enumerable protocol error.
- Include attribute-defined primary keys and generated timestamps in typespecs. Type `:id`
  fields as integers, including the negative values accepted by Ecto.
- Clarify migration from 0.4.0 for foreign structs in ordinary single embeds and embed lists.

# 0.4.1

- Preserve field declaration context, including redaction, source mappers, timestamp
  options, aliases, and constants interleaved with functions. Validation guards capture
  attributes at their declaration, and functions can reference their completed struct.
- Support evaluated option expressions for fields and embeds, implicit string fields,
  and schemas containing only attributes.
- Handle malformed and explicitly unknown polymorphic tags through `on_type_not_found`,
  including existing single variants and unknown parent discriminator values.
- Generate custom and parameterized primary keys, and run grouped generators once so
  initial timestamps agree.
- Preserve explicit nil polymorphic primary keys during casting and Strukt JSON encoding.
  Direct polymorphic changesets now leave omitted keys unset, matching ordinary embeds.
- Preserve omitted fields in positional updates to ordinary embed lists without keys.
- Assign Strukt child changeset actions before validation, so nested insert/update guards
  execute. Ordinary replacement actions and trusted-struct validation behavior are retained.
- Clarify supported schema declarations, nested validation, and JSON encoding behavior.
- Persist trusted struct updates to existing ordinary embed lists and reject foreign structs
  in ordinary single embeds and embed lists. Unlike 0.4.0, a struct must belong to the declared
  child schema. Convert foreign child structs with `Map.from_struct/1` to cast their fields
  as parameters; see the [migration guidance](guides/usage.md#parameter-names-and-changeset-apis).
- Cast only newly supplied embed fields when updating a changeset, preserving deleted or
  manually edited changes instead of replaying historical parameters.
- Select the new polymorphic variant before normalization when using a parent discriminator,
  including source aliases, enum values, and pending parent changes.
- Autogenerate built-in `:binary_id` primary keys during construction, including nested embeds.
- Evaluate field options once in declaration order, including primary-key flags; type
  declarations no longer delay constants needed by following fields.
- Include nullable array elements and typed-map values in generated types.
- Preserve single ordinary embed IDs and pending fields during direct changeset updates
  with `on_replace: :update`, including updates that omit the primary key.
- Normalize source aliases in tagless polymorphic updates using the current variant;
  schema struct inputs always use field names, even when another field's source collides.
- Handle indexed-map embed collections with the same normalization and identity matching
  as lists. Mixed ordinary struct/map lists cast correctly, and malformed nested lists
  return field errors instead of raising.
- Preserve validators declared before `defstruct`, support guards following validator
  options, and evaluate schema constants alongside their field declarations.
- Fix keyword-form range validation, empty inclusion/exclusion/subset sets, and generated
  typed-map specifications. `primary_key: false` on a field no longer disables the schema key.
- Correct the README's changeset return values and timestamp precision in JSON round-trips.
- Fixed polymorphic embeds restoring stale data after clearing or switching types within
  one changeset, including stale values satisfying required validation.
- Match embed list updates by supplied primary keys before falling back to position,
  preserving pending changes during removal and reordering without mixing records.
- Generate nested primary keys for empty map parameters and preserve inferred polymorphic
  type tags across source-name normalization.
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
