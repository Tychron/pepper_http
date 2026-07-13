defmodule Pepper.HTTP.ContentClient.LargeBlobsTest do
  use Pepper.HTTP.Support.ClientCase

  Enum.each([true, false], fn with_connection_pool ->
    Enum.each([:http1, :http2], fn protocol ->
      Enum.each([{:post, "POST"}, {:patch, "PATCH"}, {:put, "PUT"}], fn {method, method_string} ->
        describe "request/6 [with_connection_pool:#{with_connection_pool}, protocol:#{protocol}, method:#{method}, body:text]" do
          @describetag with_connection_pool: with_connection_pool, protocol: to_string(protocol), method: to_string(method)

          test "can send a large text blob (without server reading body)", %{client_options: client_options} do
            test_send_large_text_blob(%{
              server_read_body: false,
              protocol: unquote(protocol),
              method: unquote(method),
              method_string: unquote(method_string),
              client_options: client_options,
            })
          end

          test "can send a large text blob (with server reading body)", %{client_options: client_options} do
            test_send_large_text_blob(%{
              server_read_body: true,
              protocol: unquote(protocol),
              method: unquote(method),
              method_string: unquote(method_string),
              client_options: client_options,
            })
          end
        end

        describe "request/6 [with_connection_pool:#{with_connection_pool}, protocol:#{protocol}, method:#{method}, body:binary]" do
          @describetag with_connection_pool: with_connection_pool, protocol: to_string(protocol), method: to_string(method)

          test "can send a large binary blob (without server reading body)", %{client_options: client_options} do
            test_send_large_binary_blob(%{
              server_read_body: false,
              protocol: unquote(protocol),
              method: unquote(method),
              method_string: unquote(method_string),
              client_options: client_options,
            })
          end

          test "can send a large binary blob (with server reading body)", %{client_options: client_options} do
            test_send_large_binary_blob(%{
              server_read_body: true,
              protocol: unquote(protocol),
              method: unquote(method),
              method_string: unquote(method_string),
              client_options: client_options,
            })
          end
        end

        describe "request/6 [with_connection_pool:#{with_connection_pool}, protocol:#{protocol}, method:#{method}, body:form-data]" do
          @describetag with_connection_pool: with_connection_pool, protocol: to_string(protocol), method: to_string(method)
          # test "can send a form-data" do
          # end
        end
      end)
    end)
  end)

  # 16mb blobs
  @text_blob Pepper.HTTP.Utils.generate_random_base32(0x100_0000)
  @binary_blob Pepper.HTTP.Utils.generate_random_binary(0x100_0000)

  defp test_send_large_text_blob(options) do
    %{
      protocol: protocol,
      method: method,
      method_string: method_string,
      client_options: client_options,
      server_read_body: server_read_body?,
    } = options

    blob = @text_blob

    bypass = Bypass.open()

    Bypass.expect bypass, method_string, "/path/to/text", fn conn ->
      if server_read_body? do
        {:ok, body, conn} = read_all_body(conn)

        assert blob == body

        conn
        |> send_resp(204, "")
      else
        conn
        |> send_resp(204, "")
      end
    end

    headers = [
      {"accept", "*/*"},
      {"user-agent", @user_agent}
    ]

    query_params = []

    body = {:text, blob}

    assert {:ok, %{protocol: ^protocol, status_code: 204}, {:unk, ""}} =
      ContentClient.request(
        method,
        "http://localhost:#{bypass.port}/path/to/text",
        query_params,
        headers,
        body,
        Keyword.merge([
          recv_timeout: 5000,
        ], client_options)
      )
  end

  defp test_send_large_binary_blob(options) do
    %{
      protocol: protocol,
      method: method,
      method_string: method_string,
      server_read_body: server_read_body?,
      client_options: client_options,
    } = options

    blob = @binary_blob

    bypass = Bypass.open()

    Bypass.expect bypass, method_string, "/path/to/text", fn conn ->
      if server_read_body? do
        {:ok, body, conn} = read_all_body(conn)

        assert blob == body

        conn
        |> send_resp(204, "")
      else
        conn
        |> send_resp(204, "")
      end
    end

    headers = [
      {"accept", "*/*"},
      {"user-agent", @user_agent}
    ]

    query_params = []

    body = {:text, blob}

    assert {:ok, %{protocol: ^protocol, status_code: 204}, {:unk, ""}} =
      ContentClient.request(
        method,
        "http://localhost:#{bypass.port}/path/to/text",
        query_params,
        headers,
        body,
        Keyword.merge([
          recv_timeout: 5000,
        ], client_options)
      )
  end
end
