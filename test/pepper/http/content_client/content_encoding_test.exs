defmodule Pepper.HTTP.ContentClient.GetTest do
  use Pepper.HTTP.Support.ClientCase

  alias Pepper.HTTP.ContentClient, as: Client

  import Plug.Conn

  Enum.each([true, false], fn with_connection_pool ->
    Enum.each([:http1, :http2], fn protocol ->
      describe "request/6 (with_connection_pool:#{with_connection_pool}, protocol:#{protocol}, method:GET)" do
        @describetag with_connection_pool: with_connection_pool, protocol: to_string(protocol), method: "GET"

        test "can perform a GET request with string url and no special encodings", %{client_options: client_options} do
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

        test "can perform a GET request with string url and with accept-encoding: identity", %{client_options: client_options} do
          bypass = Bypass.open()

          Bypass.expect bypass, "GET", "/path/to/glory", fn conn ->
            conn = Plug.Conn.fetch_query_params(conn)

            assert %{
              "this" => "is a test",
              "also" => %{
                "that" => "was a test",
              }
            } = conn.query_params

            conn
            |> put_resp_header("content-encoding", "identity")
            |> send_resp(200, "")
          end

          headers = [
            {"accept-encoding", "identity"}
          ]

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

        test "can perform a GET request with string url and with accept-encoding: gzip", %{client_options: client_options} do
          bypass = Bypass.open()

          Bypass.expect bypass, "GET", "/path/to/glory", fn conn ->
            conn = Plug.Conn.fetch_query_params(conn)

            assert %{
              "this" => "is a test",
              "also" => %{
                "that" => "was a test",
              }
            } = conn.query_params

            conn
            |> put_resp_header("content-encoding", "gzip")
            |> send_resp(200, :zlib.gzip("Hello, World"))
          end

          headers = [
            {"accept-encoding", "gzip"}
          ]

          assert {:ok, %{status_code: 200}, {:unk, "Hello, World"}} =
            Client.request(
              "GET",
              "http://localhost:#{bypass.port}/path/to/glory",
              [{"this", "is a test"}, {"also", %{"that" => "was a test"}}],
              headers,
              nil,
              client_options
            )
        end

        test "can perform a GET request with string url and with accept-encoding: deflate", %{client_options: client_options} do
          bypass = Bypass.open()

          Bypass.expect bypass, "GET", "/path/to/glory", fn conn ->
            conn = Plug.Conn.fetch_query_params(conn)

            assert %{
              "this" => "is a test",
              "also" => %{
                "that" => "was a test",
              }
            } = conn.query_params

            conn
            |> put_resp_header("content-encoding", "deflate")
            |> send_resp(200, deflate("Hello, World"))
          end

          headers = [
            {"accept-encoding", "deflate"}
          ]

          assert {:ok, %{status_code: 200}, {:unk, "Hello, World"}} =
            Client.request(
              "GET",
              "http://localhost:#{bypass.port}/path/to/glory",
              [{"this", "is a test"}, {"also", %{"that" => "was a test"}}],
              headers,
              nil,
              client_options
            )
        end

        test "can perform a GET request with string url and with accept-encoding that doesn't match", %{client_options: client_options} do
          bypass = Bypass.open()

          Bypass.expect bypass, "GET", "/path/to/glory", fn conn ->
            conn = Plug.Conn.fetch_query_params(conn)

            assert %{
              "this" => "is a test",
              "also" => %{
                "that" => "was a test",
              }
            } = conn.query_params

            conn
            |> put_resp_header("content-encoding", "gzip")
            |> send_resp(200, :zlib.gzip("Hello, World"))
          end

          headers = [
            {"accept-encoding", "deflate"}
          ]

          assert {:error, {:unaccepted_content_encoding, "gzip", _}} =
            Client.request(
              "GET",
              "http://localhost:#{bypass.port}/path/to/glory",
              [{"this", "is a test"}, {"also", %{"that" => "was a test"}}],
              headers,
              nil,
              client_options
            )
        end
      end
    end)
  end)

  defp deflate(message) do
    z = :zlib.open()
    try do
      :ok = :zlib.deflateInit(z, :default)
      blob = :zlib.deflate(z, message, :finish)
      :ok = :zlib.deflateEnd(z)
      blob
    after
      :zlib.close(z)
    end
  end
end
