defmodule Pepper.HTTP.ConnectionManagerTest do
  use Pepper.HTTP.Support.ClientCase

  alias Pepper.HTTP.ContentClient, as: Client

  import Plug.Conn

  @user_agent "content-client-test/1.0"

  @port 9899

  describe "connection pool" do
    test "can perform requests without connection pool" do
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

      options = []

      for _ <- 1..1000 do
        assert {:ok, %{status_code: 200}, {:unk, "DONE"}} =
                 Client.request(
                   :get,
                   "http://localhost:#{@port}/path",
                   query_params,
                   headers,
                   "",
                   options
                 )
      end
    end

    test "can perform a request with connection pool" do
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

      {:ok, pid} = Pepper.HTTP.ConnectionManager.Pooled.start_link([pool_size: 100], [])

      try do
        options = [
          connection_manager: :pooled,
          connection_manager_id: pid
        ]

        for _ <- 1..1000 do
          assert {:ok, %{status_code: 200}, {:unk, "DONE"}} =
                   Client.request(
                     :get,
                     "http://localhost:#{@port}/path",
                     query_params,
                     headers,
                     "",
                     options
                   )
        end

        assert %{
                 busy_size: 0,
                 available_size: 1
               } = Pepper.HTTP.ConnectionManager.Pooled.get_stats(pid)
      after
        Pepper.HTTP.ConnectionManager.Pooled.stop(pid)
      end
    end

    test "can perform a request with connection pool and non-connectable endpoint" do
      headers = [
        {"accept", "*/*"},
        {"user-agent", @user_agent}
      ]

      query_params = []

      {:ok, pid} = Pepper.HTTP.ConnectionManager.Pooled.start_link([pool_size: 100], [])

      try do
        options = [
          connection_manager: :pooled,
          connection_manager_id: pid
        ]

        for _ <- 1..1000 do
          assert {:error, reason} =
            Client.request(
              :get,
              "http://localhost:#{@port}/path",
              query_params,
              headers,
              "",
              options
            )

          assert %Pepper.HTTP.ConnectError{
            reason: %Mint.TransportError{reason: :econnrefused}
          } = reason
        end

        assert %{
                 busy_size: 0,
                 available_size: 0
               } = Pepper.HTTP.ConnectionManager.Pooled.get_stats(pid)
      after
        Pepper.HTTP.ConnectionManager.Pooled.stop(pid)
      end
    end
  end
end
