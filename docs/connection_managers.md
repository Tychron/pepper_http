## Connection Managers

By default pepper will always establish a new connection per request.

This means Pepper's default settings are not fit for production use, when a connection pool is required it can be started using `Pepper.HTTP.ConnectionManager.Pooled`

### One Off

`Pepper.HTTP.ConnectionManager.OneOff` is the default connection manager, and it's not really  connection manager at all.

OneOff will create new connections per request, this is fine for "One off requests" such as quickly testing the library, but in more serious applications you should use a connection pool.

### Pooled

#### In Supervisor

```elixir
  children = [
    {Pepper.HTTP.ConnectionManager.Pooled, [
      # this keyword list contains the options for the pool itself
      [pool_size: 10],
      # this keyword list contains the options for the underlying gen server
      [name: :my_http_pool_name],
    ]},
  ]
```

```elixir
options = [
  connection_manager: :pooled,
  # this can also be the pid
  connection_manager_id: :my_http_pool_name
]
Pepper.HTTP.Client.request(method, url, headers, body, options)
```
