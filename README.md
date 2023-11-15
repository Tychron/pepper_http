# Pepper.HTTP

An HTTP Client library built around [Mint](https://github.com/elixir-mint/mint), includes handy utilities for making JSON, CSV, Text and Form requests.

## Quick Usage

```elixir
{:ok, resp} = Pepper.HTTP.Client.request(method, url, headers, body, options)

{:ok, resp} = Pepper.HTTP.Client.request(:get, "https://example.com", [{"user-agent", "pepper-http/0.6.0"}], nil, [])

resp.status_code # => 200
resp.headers # => [{"content-type", "text/plain"}, {"content-length", "12"}]
resp.body # => "Hello, World"
```

## Documentation

* [Clients](docs/clients.md)
* [Connection Managers - Pools](docs/connection_managers.md)
* [Response Body Handlers](docs/response_body_handlers.md)
