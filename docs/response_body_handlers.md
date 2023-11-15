## Response Body Handlers

When Pepper is reading a response for a request, it will use the `response_body_handler` module specified.

By default this will be `Pepper.HTTP.ResponseBodyHandler.Default`.

### Default

`Pepper.HTTP.ResponseBodyHandler.Default` will read the response body into memory and set the response.body to the result of that operation.

```elixir
options = [
  # recv_size still applies even when using file
  recv_size: :infinity,
  response_body_handler: Pepper.HTTP.ResponseBodyHandler.Default,
]

{:ok, response} = Pepper.HTTP.Client.request(:get, "http://example.com/file.bin", [], nil, options)

response.body # => "response-body-here"
```

### File

`Pepper.HTTP.ResponseBodyHandler.File` will read the response body into a file configured by `response_body_handler_options[:filename]`

```elixir
options = [
  # recv_size still applies even when using file
  recv_size: :infinity,
  response_body_handler: Pepper.HTTP.ResponseBodyHandler.File,
  response_body_handler_options: [
    filename: "/path/to/file"
  ]
]

{:ok, response} = Pepper.HTTP.Client.request(:get, "http://example.com/file.bin", [], nil, options)

response.body # => {:file, "/path/to/file"}
```

__Note__ `Pepper.HTTP.ContentClient` will not parse the result from a File handler.
