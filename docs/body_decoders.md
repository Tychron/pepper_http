## Body Decoders

Starting at `pepper_http >= 0.8.0`, ContentClient decoders can be set using the config:

```elixir
config :pepper_http,
  # Before you can use your decoder, pepper needs to know how to translate content-type headers
  # into internal type names
  # the decoder_content_types (and base_decoder_content_types) config does provides that information
  # Note the the decoder is expected to return the same type name or similar
  decoder_content_types: [
    {{"application", "x-my-type"}, :my_type}
  ],
  # Once you have your type name, you can finally decode it using the specified decoder module
  # The module is expected to return {type_name::atom(), any()}
  # This is the third element returned in the response tuple:
  #   {:ok, Pepper.HTTP.Response.t(), {type_name::atom(), any()}}
  #   Example:
  #     {:ok, _resp, {:json, doc}}
  decoders: [
    my_type: MyType.Decoder
  ]
```

As one may have noticed, `base_decoder_content_types` was mentioned, this config is the _default_ for pepper, in addition to `base_decoders`:

```elixir
config :pepper_http
  base_decoder_content_types: [
    {{"application", "json"}, :json},
    {{"application", "vnd.api+json"}, :json},
    {{"application", "xml"}, :xml},
    {{"application", "vnd.api+xml"}, :xml},
    {{"text", "xml"}, :xml},
    {{"text", "plain"}, :text},
    {{"application", "csv"}, :csv},
    {{"text", "csv"}, :csv},
  ],
  base_decoders: [
    csv: Pepper.HTTP.BodyDecoder.CSV,
    json: Pepper.HTTP.BodyDecoder.JSON,
    xml: Pepper.HTTP.BodyDecoder.XML,
    text: Pepper.HTTP.BodyDecoder.Text,
  ]
```

Normally there is no need to overwrite that config, but it is provided just in case, otherwise you are expected to use `:decoder_content_types` and `:decoders` which will be added to the base.
