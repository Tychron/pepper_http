defmodule Pepper.HTTP.ClientTest do
  use Pepper.HTTP.Support.ClientCase

  alias Pepper.HTTP.ContentClient, as: Client

  import Plug.Conn

  describe "request/6 (GET)" do
    test "can perform a GET request with string url" do
      bypass = Bypass.open()

      Bypass.expect bypass, "GET", "/path/to/glory", fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)

        assert %{
          "this" => "is a test",
          "also" => %{
            "that" => "was a test",
          }
        } = conn.query_params

        send_resp(conn, 200, "")
      end

      headers = []

      assert {:ok, %{status_code: 200}, _} =
        Client.request(
          "GET",
          "http://localhost:#{bypass.port}/path/to/glory",
          [{"this", "is a test"}, {"also", %{"that" => "was a test"}}],
          headers,
          nil,
          []
        )
    end

    test "can perform a GET request with URI" do
      bypass = Bypass.open()

      Bypass.expect bypass, "GET", "/path/to/glory", fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)

        assert %{
          "this" => "is a test",
          "also" => %{
            "that" => "was a test",
          }
        } = conn.query_params

        send_resp(conn, 200, "")
      end

      headers = []

      uri = %URI{
        scheme: "http",
        host: "localhost",
        path: "/path/to/glory",
        port: bypass.port,
      }

      assert {:ok, %{status_code: 200}, _} =
        Client.request(
          "GET",
          uri,
          [{"this", "is a test"}, {"also", %{"that" => "was a test"}}],
          headers,
          nil,
          []
        )
    end

    test "can handle a request that fails to connect" do
      bypass = Bypass.open()

      Bypass.down bypass

      headers = []

      assert {:error, %Pepper.HTTP.ConnectError{reason: %Mint.TransportError{reason: :econnrefused}}} =
        Client.request(
          "GET",
          "http://localhost:#{bypass.port}/path/to/glory",
          [{"this", "is a test"}, {"also", %{"that" => "was a test"}}],
          headers,
          nil,
          # timeout is intentionally lower than sleep timer in server
          [
            recv_timeout: 1000,
            connect_timeout: 1000,
          ]
        )
    end

    test "can handle a timeout while receiving data from endpoint" do
      bypass = Bypass.open()

      Bypass.expect bypass, "GET", "/path/to/glory", fn conn ->
        # purposely stall
        Process.sleep 3000

        send_resp(conn, 200, "")
      end

      headers = []

      assert {:error, %Pepper.HTTP.ReceiveError{reason: %Mint.TransportError{reason: :timeout}}} =
        Client.request(
          "GET",
          "http://localhost:#{bypass.port}/path/to/glory",
          [{"this", "is a test"}, {"also", %{"that" => "was a test"}}],
          headers,
          nil,
          # timeout is intentionally lower than sleep timer in server
          [recv_timeout: 1000]
        )

      Bypass.down bypass
    end
  end

  describe "request/6 (POST)" do
    test "can perform a POST request" do
      bypass = Bypass.open()

      Bypass.expect bypass, "POST", "/path/to/fame", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        conn = Plug.Conn.fetch_query_params(conn)

        assert "Hello, World" == body

        assert %{
          "this" => "is a test",
          "also" => %{
            "that" => "was a test",
          }
        } = conn.query_params

        send_resp(conn, 200, "")
      end

      headers = []
      body = {:text, "Hello, World"}

      assert {:ok, %{status_code: 200}, _} =
        Client.request(
          "POST",
          "http://localhost:#{bypass.port}/path/to/fame",
          [{"this", "is a test"}, {"also", %{"that" => "was a test"}}],
          headers,
          body,
          []
        )
    end
  end
end
