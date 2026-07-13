defmodule Pepper.HTTP.ConnectionManagerTest do
  use Pepper.HTTP.Support.ClientCase

  alias Pepper.HTTP.ContentClient, as: Client

  import Plug.Conn

  @user_agent "content-client-test/1.0"

  @port 9899

  Enum.each([:http1, :http2], fn protocol ->
    describe "without connection pool (protocol:#{protocol})" do
      @describetag with_connection_pool: false, protocol: to_string(protocol)

      test "can perform GET requests without connection pool", %{client_options: client_options} do
        bypass = Bypass.open(port: @port)

        Bypass.stub(bypass, "GET", "/path", fn conn ->
          assert [@user_agent] == get_req_header(conn, "user-agent")
          send_resp(conn, 200, "DONE")
        end)

        headers = [
          {"accept", "*/*"},
          {"user-agent", @user_agent}
        ]

        query_params = []

        for _ <- 1..1000 do
          assert {:ok, %{status_code: 200}, {:unk, "DONE"}} =
            Client.request(
              :get,
              "http://localhost:#{@port}/path",
              query_params,
              headers,
              "",
              client_options
            )
        end
      end

      test "can perform HEAD requests without connection pool", %{client_options: client_options} do
        bypass = Bypass.open(port: @port)

        Bypass.stub(bypass, "HEAD", "/path", fn conn ->
          assert [@user_agent] == get_req_header(conn, "user-agent")
          send_resp(conn, 200, "")
        end)

        headers = [
          {"accept", "*/*"},
          {"user-agent", @user_agent}
        ]

        query_params = []

        for _ <- 1..1000 do
          assert {:ok, %{status_code: 200}, {:unk, ""}} =
            Client.request(
              :head,
              "http://localhost:#{@port}/path",
              query_params,
              headers,
              "",
              client_options
            )
        end
      end
    end

    describe "with connection pool (protocol:#{protocol})" do
      @describetag with_connection_pool: true, protocol: to_string(protocol)

      @tag connection_pool_options: [default_lifespan: 1000]
      test "shortlived connections", %{connection_pool_pid: connection_pool_pid, client_options: client_options} do
        bypass = Bypass.open(port: @port)

        Bypass.stub(bypass, "GET", "/path", fn conn ->
          assert [@user_agent] == get_req_header(conn, "user-agent")
          send_resp(conn, 200, "DONE")
        end)

        headers = [
          {"accept", "*/*"},
          {"user-agent", @user_agent}
        ]

        query_params = []

        assert %{
          pool_size: 10,
          total_size: 0,
          busy_size: 0,
          available_size: 0,
        } = Pepper.HTTP.ConnectionManager.Pooled.get_stats(connection_pool_pid)

        assert {:ok, %{protocol: unquote(protocol), status_code: 200}, {:unk, "DONE"}} =
                 Client.request(
                   :get,
                   "http://localhost:#{@port}/path",
                   query_params,
                   headers,
                   "",
                   client_options
                 )

        assert %{
          pool_size: 10,
          total_size: 1,
          busy_size: 0,
          available_size: 1
        } = Pepper.HTTP.ConnectionManager.Pooled.get_stats(connection_pool_pid)

        Process.sleep 1100

        assert %{
          pool_size: 10,
          total_size: 0,
          busy_size: 0,
          available_size: 0
        } = Pepper.HTTP.ConnectionManager.Pooled.get_stats(connection_pool_pid)
      end

      test "can close all connections", %{connection_pool_pid: connection_pool_pid, client_options: client_options} do
        bypass = Bypass.open(port: @port)

        Bypass.stub(bypass, "GET", "/path", fn conn ->
          assert [@user_agent] == get_req_header(conn, "user-agent")
          send_resp(conn, 200, "DONE")
        end)

        headers = [
          {"accept", "*/*"},
          {"user-agent", @user_agent}
        ]

        query_params = []

        assert %{
          pool_size: 10,
          total_size: 0,
          busy_size: 0,
          available_size: 0,
        } = Pepper.HTTP.ConnectionManager.Pooled.get_stats(connection_pool_pid)

        assert {:ok, %{protocol: unquote(protocol), status_code: 200}, {:unk, "DONE"}} =
                 Client.request(
                   :get,
                   "http://localhost:#{@port}/path",
                   query_params,
                   headers,
                   "",
                   client_options
                 )

        Enum.each(["a", "b", "c", "d", "e", "f"], fn prefix ->
          assert {:ok, %{protocol: unquote(protocol), status_code: 200}, {:unk, "DONE"}} =
                   Client.request(
                     :get,
                     "http://#{prefix}.localhost:#{@port}/path",
                     query_params,
                     headers,
                     "",
                     client_options
                   )
        end)

        assert %{
          pool_size: 10,
          total_size: 7,
          busy_size: 0,
          available_size: 7
        } = Pepper.HTTP.ConnectionManager.Pooled.get_stats(connection_pool_pid)

        :ok = Pepper.HTTP.ConnectionManager.Pooled.close_all(connection_pool_pid, :nuke)
      end

      test "can perform a GET request with connection pool", %{connection_pool_pid: connection_pool_pid, client_options: client_options} do
        bypass = Bypass.open(port: @port)

        Bypass.stub(bypass, "GET", "/path", fn conn ->
          assert [@user_agent] == get_req_header(conn, "user-agent")
          send_resp(conn, 200, "DONE")
        end)

        headers = [
          {"accept", "*/*"},
          {"user-agent", @user_agent}
        ]

        query_params = []

        assert %{
          pool_size: 10,
          total_size: 0,
          busy_size: 0,
          available_size: 0,
        } = Pepper.HTTP.ConnectionManager.Pooled.get_stats(connection_pool_pid)

        for _x <- 1..20 do
          assert {:ok, %{protocol: unquote(protocol), status_code: 200}, {:unk, "DONE"}} =
            Client.request(
              :get,
              "http://localhost:#{@port}/path",
              query_params,
              headers,
              nil,
              client_options
            )
        end

        assert %{
          pool_size: 10,
          total_size: 1,
          busy_size: 0,
          available_size: 1
        } = Pepper.HTTP.ConnectionManager.Pooled.get_stats(connection_pool_pid)
      end

      test "can perform a GET request with connection pool and handle a connect timeout", %{client_options: client_options, connection_pool_pid: connection_pool_pid} do
        bypass = Bypass.open(port: @port)

        Bypass.down bypass

        headers = [
          {"accept", "*/*"},
          {"user-agent", @user_agent}
        ]

        query_params = []

        client_options = Keyword.merge(client_options, [
          connect_timeout: 1000,
          recv_timeout: 1000,
        ])

        assert %{
          busy_size: 0,
          available_size: 0
        } = Pepper.HTTP.ConnectionManager.Pooled.get_stats(connection_pool_pid)

        for _ <- 1..1000 do
          assert {:error,
            %Pepper.HTTP.ConnectError{
              reason: %Mint.TransportError{reason: :econnrefused, __exception__: true}
            }
          } = Client.request(
            :get,
            "http://localhost:#{@port}/path",
            query_params,
            headers,
            "",
            client_options
          )
        end

        assert %{
          busy_size: 0,
          available_size: 1
        } = Pepper.HTTP.ConnectionManager.Pooled.get_stats(connection_pool_pid)
      end

      test "can perform a GET request with connection pool and non-connectable endpoint", %{client_options: client_options, connection_pool_pid: connection_pool_pid} do
        headers = [
          {"accept", "*/*"},
          {"user-agent", @user_agent}
        ]

        query_params = []

        for _ <- 1..1000 do
          assert {:error, reason} =
            Client.request(
              :get,
              "http://localhost:#{@port}/path",
              query_params,
              headers,
              "",
              client_options
            )

          assert %Pepper.HTTP.ConnectError{
            reason: %Mint.TransportError{reason: :econnrefused}
          } = reason
        end

        assert %{
                 busy_size: 0,
                 available_size: 1
               } = Pepper.HTTP.ConnectionManager.Pooled.get_stats(connection_pool_pid)
      end
    end
  end)
end
