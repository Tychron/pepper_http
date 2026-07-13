defmodule Pepper.HTTP.ContentClient.QueryParamsTest do
  use Pepper.HTTP.Support.ClientCase

  alias Pepper.HTTP.ContentClient, as: Client

  import Plug.Conn

  Enum.each([true, false], fn with_connection_pool ->
    Enum.each([:http1, :http2], fn protocol ->
      describe "request/6 (with_connection_pool:#{with_connection_pool}, protocol:#{protocol}, method:GET)" do
        @describetag with_connection_pool: with_connection_pool, protocol: to_string(protocol), method: "GET"

        test "can encode query params with default encoding", %{client_options: client_options} do
          bypass = Bypass.open()

          Bypass.expect bypass, "GET", "/path/to/glory", fn conn ->
            conn = Plug.Conn.fetch_query_params(conn)

            assert %{
              "a" => "1",
              "b" => "2",
              "c" => "3",
              "d" => "5",
            } = conn.query_params

            send_resp(conn, 200, "")
          end

          headers = []

          assert {:ok, %{status_code: 200}, _} =
            Client.request(
              "GET",
              "http://localhost:#{bypass.port}/path/to/glory",
              [
                {"a", "1"},
                {"b", "2"},
                {"c", "3"},
                {"d", "5"},
                {"d", "4"},
              ],
              headers,
              nil,
              client_options
            )
        end

        test "can encode query params with duplicate encoding", %{client_options: client_options} do
          bypass = Bypass.open()

          Bypass.expect bypass, "GET", "/path/to/glory", fn conn ->
            assert "a=1&b=2&c=3&d=5&d=4" == conn.query_string

            send_resp(conn, 200, "")
          end

          headers = []

          assert {:ok, %{status_code: 200}, _} =
            Client.request(
              "GET",
              "http://localhost:#{bypass.port}/path/to/glory",
              [
                {"a", "1"},
                {"b", "2"},
                {"c", "3"},
                {"d", "5"},
                {"d", "4"},
              ],
              headers,
              nil,
              Keyword.put(client_options, :query_params_encoding, :duplicate)
            )
        end
      end
    end)
  end)
end
