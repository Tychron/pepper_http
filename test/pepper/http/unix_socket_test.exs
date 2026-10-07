defmodule Pepper.HTTP.UnixSocketTest do
  use ExUnit.Case, async: true

  alias Pepper.HTTP.Client
  alias Pepper.HTTP.ContentClient
  alias Pepper.HTTP.ConnectionManager.Pooled

  @moduletag :unix_socket
  @moduletag skip: not match?({:unix, _}, :os.type())

  defmodule Server do
    import Plug.Conn

    def init(options), do: options

    def call(conn, {parent, identity}) do
      {:ok, body, conn} = read_body(conn)
      {_, request} = conn.adapter

      send(
        parent,
        {:served, identity, request.pid, conn.method, conn.request_path, conn.query_string,
         conn.host, conn.port, conn.req_headers, body}
      )

      conn |> put_resp_content_type("text/plain") |> send_resp(200, identity)
    end
  end

  defp start_server(identity, transport) do
    ref = make_ref()
    options = [ref: ref, port: 0, transport_options: [num_acceptors: 2]] ++ transport

    child =
      Plug.Cowboy.child_spec(scheme: :http, plug: {Server, {self(), identity}}, options: options)

    start_supervised!(Supervisor.child_spec(child, id: ref))
    ref
  end

  defp start_socket(identity) do
    path = Path.join(System.tmp_dir!(), "pepper-#{System.unique_integer([:positive])}.sock")
    on_exit(fn -> File.rm(path) end)
    start_server(identity, ip: {:local, path})
    path
  end

  defp client_options(:one_off, protocol) do
    [connect_options: [protocols: [protocol]]]
  end

  defp client_options(:pooled, protocol) do
    pool = start_supervised!({Pooled, [[pool_size: 1], []]})

    [
      connection_manager: :pooled,
      connection_manager_id: pool,
      connect_options: [protocols: [protocol]]
    ]
  end

  for manager <- [:one_off, :pooled], protocol <- [:http1, :http2] do
    test "#{manager} #{protocol} keeps the HTTP host, port, path, query, and body" do
      socket = start_socket("unix")
      options = client_options(unquote(manager), unquote(protocol)) ++ [unix_socket: socket]

      assert {:ok, %{status_code: 200, protocol: unquote(protocol)}, {:text, "unix"}} =
               ContentClient.post(
                 "http://service.invalid:8080/api/status",
                 [detail: "full"],
                 [],
                 {:text, "hello"},
                 options
               )

      assert_receive {:served, "unix", _, "POST", "/api/status", "detail=full", "service.invalid",
                      8080, _, "hello"}

      assert {:ok, %{body: "unix"}} =
               Client.request(:get, "http://service.invalid/status", [], nil, options)

      assert_receive {:served, "unix", _, "GET", "/status", "", "service.invalid", 80, _, ""}
    end
  end

  for manager <- [:one_off, :pooled] do
    test "#{manager} preserves an explicit Host header" do
      socket = start_socket("unix")
      options = client_options(unquote(manager), :http1) ++ [unix_socket: socket]

      assert {:ok, %{body: "unix"}} =
               Client.request(
                 :get,
                 "http://service.invalid/status",
                 [{"Host", "virtual.example:9090"}],
                 nil,
                 options
               )

      assert_receive {:served, "unix", _, "GET", "/status", "", "virtual.example", 9090, _, ""}
    end
  end

  for protocol <- [:http1, :http2] do
    test "#{protocol} reuses a socket and reconnects a reclaimed worker across sockets and TCP" do
      socket_a = start_socket("a")
      socket_b = start_socket("b")
      tcp_ref = start_server("tcp", ip: {127, 0, 0, 1})
      url = "http://localhost:#{:ranch.get_port(tcp_ref)}/status"
      options = client_options(:pooled, unquote(protocol))

      request = fn identity, socket_options ->
        assert {:ok, %{body: ^identity}} =
                 Client.request(:get, url, [], nil, options ++ socket_options)

        assert_receive {:served, ^identity, connection, "GET", "/status", "", _, _, _, ""}
        await_checkin(options[:connection_manager_id], 100)
        connection
      end

      first = request.("a", unix_socket: socket_a)
      assert first == request.("a", unix_socket: socket_a)
      assert first != request.("b", unix_socket: socket_b)
      request.("tcp", [])
      assert first != request.("a", unix_socket: socket_a)
    end
  end

  defp await_checkin(pool, attempts) do
    case Pooled.get_stats(pool) do
      %{busy_size: 0} ->
        :ok

      _ when attempts > 0 ->
        Process.sleep(1)
        await_checkin(pool, attempts - 1)

      stats ->
        flunk("connection was not returned to pool: #{inspect(stats)}")
    end
  end

  test "connect errors retain the socket option in the request" do
    path = Path.join(System.tmp_dir!(), "pepper-missing-#{System.unique_integer([:positive])}.sock")

    assert {:error, %Pepper.HTTP.ConnectError{request: request, reason: %Mint.TransportError{}}} =
             Client.request(:get, "http://service.invalid/status", [], nil, unix_socket: path)

    assert request.options[:unix_socket] == path
  end
end
