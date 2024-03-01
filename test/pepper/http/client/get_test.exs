defmodule Pepper.HTTP.Client.GetTest do
  use Pepper.HTTP.Support.ClientCase

  alias Pepper.HTTP.ContentClient, as: Client

  import Plug.Conn

  Enum.each([true, false], fn with_connection_pool ->
    Enum.each([:http1, :http2], fn protocol ->
      describe "request/6 (with_connection_pool:#{with_connection_pool}, protocol:#{protocol}, method:GET)" do
        @describetag with_connection_pool: with_connection_pool, protocol: to_string(protocol), method: "GET"

        test "can perform a GET request with string url", %{client_options: client_options} do
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
              client_options
            )
        end

        test "can perform a GET request with URI", %{client_options: client_options} do
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
              client_options
            )
        end

        test "can handle a request that fails to connect", %{client_options: client_options} do
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
              Keyword.merge(client_options, [
                recv_timeout: 1000,
                connect_timeout: 1000,
              ])
            )
        end

        test "can handle a timeout while receiving data from endpoint", %{client_options: client_options} do
          bypass = Bypass.open()

          Bypass.expect bypass, "GET", "/path/to/glory", fn conn ->
            # purposely stall
            Process.sleep 3_000

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
              Keyword.merge(client_options, [recv_timeout: 1000])
            )

          Bypass.down bypass
        end
      end
    end)
  end)
end
