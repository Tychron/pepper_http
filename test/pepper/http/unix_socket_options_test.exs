defmodule Pepper.HTTP.UnixSocketOptionsTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Pepper.HTTP.Client
  alias Pepper.HTTP.ContentClient

  defmodule CaptureRequest do
    def request(pid, request) do
      send(pid, {:request, request})
      {:error, :captured}
    end
  end

  defp options(extra) do
    [connection_manager: CaptureRequest, connection_manager_id: self()] ++ extra
  end

  test "ContentClient forwards the socket option and keeps the HTTP destination" do
    log =
      capture_log(fn ->
        assert {:error, :captured} =
                 ContentClient.get(
                   "http://service.invalid:8080/api/status",
                   [detail: "full"],
                   [],
                   options(unix_socket: "/tmp/service.sock")
                 )
      end)

    refute log =~ "unexpected option"

    assert_received {:request, request}
    assert request.uri.host == "service.invalid"
    assert request.uri.port == 8080
    assert request.path == "/api/status?detail=full"
    assert request.options[:unix_socket] == "/tmp/service.sock"
  end

  test "nil disables the socket option" do
    assert {:error, :captured} =
             Client.request(
               :get,
               "http://localhost/status",
               [],
               nil,
               options(unix_socket: nil)
             )

    assert_received {:request, request}
    assert request.options[:unix_socket] == nil
  end

  test "rejects invalid socket paths before submitting a request" do
    for path <- ["", 123, String.to_charlist("/tmp/service.sock"), "/tmp/service\0.sock"] do
      assert_raise ArgumentError, ":unix_socket must be a non-empty path string or nil", fn ->
        Client.request(:get, "http://localhost/status", [], nil, options(unix_socket: path))
      end
    end

    refute_received {:request, _}
  end

  test "rejects proxy options with a Unix socket before connecting" do
    assert_raise ArgumentError, ":unix_socket cannot be combined with a proxy", fn ->
      Client.request(:get, "http://localhost/status", [], nil,
        unix_socket: "/tmp/service.sock",
        connect_options: [proxy: {:http, "localhost", 8080, []}]
      )
    end
  end
end
