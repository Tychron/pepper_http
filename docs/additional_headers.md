## Additional Headers

Sometimes it's nice to have a common module that decorates the request with some additional headers, for example adding authorization based on the request options.

By default Pepper provides an Authorization module which

Starting at `pepper_http >= 0.8.0`, ContentClient additional header modules can be added:

```elixir
config :pepper_http,
  additional_header_modules: [
    MyAdditionalHeaderModule
  ]
```

Additional header modules are expected to define a `call/3` function which returns a tuple with the headers and options respectively:

```elixir
defmodule MyAdditionalHeaderModule do
  def call(_body, headers, options) do
    # Note the body is also provided for reference, in case the header module needs to know
    # the body ahead of time, the body is expected to be in its encoded form but may not be
    # a valid binary
    {headers, options}
  end
end
```

As with any configurable property pepper also provides a `base_additional_headers_modules`:

```elixir
config :pepper_http,
  # by default the authorization module is provided
  base_additional_header_modules: [
    Pepper.HTTP.ContentClient.Headers.Authorization,
  ]
```
