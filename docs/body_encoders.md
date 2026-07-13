## Body Encoders

Starting at `pepper_http >= 0.8.0`, ContentClient encoders can be set using the config:

```elixir
config :pepper_http,
  # Unlike the decodes, the encoders use the type name from the body parameter during the request
  # so there is no need to transform content types
  encoders: [
    my_type: MyType.Encoder,
  ]
```

Same as with the body decoders, encoders also have a `base_encoders` config:

```elixir
config :pepper_http
  base_encoders: [
    csv: Pepper.HTTP.BodyEncoder.CSV,
    form: Pepper.HTTP.BodyEncoder.Form,
    form_stream: Pepper.HTTP.BodyEncoder.FormStream,
    form_urlencoded: Pepper.HTTP.BodyEncoder.FormUrlencoded,
    json: Pepper.HTTP.BodyEncoder.JSON,
    stream: Pepper.HTTP.BodyEncoder.Stream,
    text: Pepper.HTTP.BodyEncoder.Text,
    xml: Pepper.HTTP.BodyEncoder.XML,
  ]
```

Normally there is no need to overwrite that config, but it is provided just in case, otherwise you are expected to use `:encoders` which will be added to the base.
