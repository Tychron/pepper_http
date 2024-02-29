## Body Decompressors

__Accept__ `Accept-Encoding`

__Content__ `Content-Encoding`

Starting at `pepper_http >= 0.8.0`, ContentClient decompressors can be set using the config:

```elixir
config :pepper_http,
  # As with most custom modules, content-encoding types must be translated to an internal name
  decompressor_types: [
    {"br", :br},
  ],
  # Once the name is available, the decompressor module can be specified
  decompressors: [
    br: MyBrDecompressor
  ]
```

Pepper provides modules for Identity, Gzip and Deflate out of the box

```elixir
config :pepper_http
  base_decompressor_types: [
    {"identity", :identity},
    {"deflate", :deflate},
    {"gzip", :gzip},
  ],
  base_decompressors: [
    identity: Pepper.HTTP.BodyDecompressor.Identity,
    deflate: Pepper.HTTP.BodyDecompressor.Deflate,
    gzip: Pepper.HTTP.BodyDecompressor.Gzip,
  ]
```

Normally there is no need to overwrite that config, but it is provided just in case, otherwise you are expected to use `:decompressor_types` and `:decompressors` which will be added to the base.
