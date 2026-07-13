## Client

Pepper provides 2 client modules:,
  * `Pepper.HTTP.Client` - The basic client provides no special functions such as response parsing, and automatic body encoding.
  * `Pepper.HTTP.ContentClient` - The content client provides response parsing based on the initial request's accept header and automatic body encoding for supported types.

ContentClient builds upon Client and so any options that would be passed to Client can also be passed through from ContentClient.

### Client Usage

If you just need a simple HTTP Client with no bells and whistles the base Client is your goto.

```elixir
# By default Pepper will not use a connection pool, unlike other HTTP Libraries that have some
# kind of default pool, Pepper has none, and will create a new connection.
method = :get
url = "https://raw.githubusercontent.com/Tychron/pepper_http/main/README.md"
headers = [
  {"user-agent", "pepper-test-client/1.0.0"},
  {"accept", "*/*"},
]
# When using Client, body must either be nil, string or a {:stream, any()}, more on streams later
body = nil

# Defaults:
#   attempts: 1
#   connect_timeout: 30_000
#   recv_timeout: 30_000
#   recv_size: 8 * 1024 * 1024 # 8388608 bytes or 8 megabytes
#   response_body_handler: Pepper.HTTP.ResponseBodyHandler.Default
#   response_body_handler_options: []
#   connection_manager: :one_off
#   connection_manager_id: nil
#
options = []

result = Pepper.HTTP.Client.request(method, url, headers, body, options)

case result do
  {:ok, %Pepper.HTTP.Response{} = resp} ->
    # The properties you likely care the most about
    resp.status_code # => 200
    resp.headers # => [{"header-name", "header-value"}]
    resp.body
end
```

### ContentClient Usage

If you are in need of something more featured, Pepper provides a ContentClient which can handle most common request body types and response bodies.

```elixir
method = :get
url = "https://raw.githubusercontent.com/Tychron/pepper_http/main/README.md"
query_params = []

headers = [
  {"user-agent", "pepper-test-client/1.0.0"},
  # ContentClient will actually check the request's accept header against the
  # response's Content-Type and will only parse content that matches the accept
  # so if you ask for XML and the server returns JSON, it will not parse the JSON.
  {"accept", "*/*"},
]
body = nil
options = []

result =
  Pepper.HTTP.ContentClient.request(
    method,
    url,
    query_params,
    headers,
    body,
    options
  )

case result do
  {:ok, %Pepper.HTTP.Response{} = resp, resp_body} ->
    case resp_body do
      # Content-Type: application/json
      {:json, doc} ->
        # doc is parsed JSON payload
        :ok

      # Content-Type: application/xml
      # Content-Type: text/xml
      {:xml, doc} ->
        # `Saxy.SimpleForm.parse_string/1` will be used to parse the blob and returns the document
        :ok

      {:xmldoc, doc} ->
        # If normalize_xml option is set to true, this will be returned instead of {:xml, doc}
        # normalized is a simpified structure for XML documents containing only the values
        :ok

      # Content-Type: text/plain
      {:text, doc} ->
        :ok

      # Anything else
      {:unk, doc} ->
        :ok
    end
end
```
