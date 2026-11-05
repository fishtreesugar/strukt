# Modified from upstream by the maintainers of the fishtreesugar/strukt fork.

defmodule Strukt.Field do
  @moduledoc false

  defstruct type: nil,
            name: nil,
            meta: nil,
            value_type: nil,
            options: [],
            block: nil

  @validation_opts [
    :required,
    :length,
    :format,
    :one_of,
    :none_of,
    :subset_of,
    :range,
    :number
  ]

  @supported_field_types [
    :field,
    :embeds_one,
    :embeds_many,
    :polymorphic_embeds_one,
    :polymorphic_embeds_many,
    :timestamps
  ]

  def split_options(options), do: Keyword.split(options, @validation_opts)

  @doc """
  This function receives the AST of all field definitions provided to `defstruct`, and
  converts the nodes to a more useful form for the macro internals.

  Options remain unevaluated until their declaration is processed in the schema module.

  This is intended for use only in the internal implementation of `defstruct`.
  """
  def parse(fields) do
    for {type, meta, args} <- fields, do: parse(type, meta, args)
  end

  defp parse(type, meta, [name, opts])
       when type in [:polymorphic_embeds_one, :polymorphic_embeds_many] do
    %__MODULE__{
      name: name,
      type: type,
      meta: meta,
      value_type: PolymorphicEmbed,
      options: opts
    }
  end

  defp parse(:field, meta, [name]), do: parse(:field, meta, [name, :string])

  defp parse(type, meta, [name, value_type]) when type in @supported_field_types,
    do: %__MODULE__{name: name, type: type, meta: meta, value_type: value_type}

  defp parse(type, meta, [name, value_type, opts]) when type in @supported_field_types do
    {block, opts} = if is_list(opts), do: Keyword.pop(opts, :do), else: {nil, opts}

    %__MODULE__{
      name: name,
      type: type,
      meta: meta,
      value_type: value_type,
      block: block,
      options: opts
    }
  end

  defp parse(type, meta, [name, value_type, opts, list])
       when type in [:embeds_one, :embeds_many] do
    block = Keyword.fetch!(list, :do)

    %__MODULE__{
      name: name,
      type: type,
      meta: meta,
      value_type: value_type,
      block: block,
      options: opts
    }
  end

  defp parse(:timestamps, meta, args),
    do: %__MODULE__{type: :timestamps, meta: meta, options: args}

  defp parse(field_type, _meta, args) do
    raise ArgumentError,
      message:
        "unsupported use of #{field_type}/#{length(args)} within `defstruct`, " <>
          "only #{Enum.join(@supported_field_types, ",")} are permitted"
  end
end
