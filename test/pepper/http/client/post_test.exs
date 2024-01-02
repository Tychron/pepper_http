defmodule Pepper.HTTP.Client.PostTest do
  use Pepper.HTTP.Support.ClientCase

  alias Pepper.HTTP.ContentClient, as: Client

  import Plug.Conn

  Enum.each([true, false], fn with_connection_pool ->
    Enum.each([:http1, :http2], fn protocol ->
      describe "request/6 (with_connection_pool:#{with_connection_pool}, protocol:#{protocol}, method:POST)" do
        @describetag with_connection_pool: with_connection_pool, protocol: to_string(protocol), method: "POST"

        test "can perform a POST request", %{client_options: client_options} do
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
              client_options
            )
        end
      end
    end)
  end)
end
