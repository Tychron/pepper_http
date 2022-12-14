defmodule Pepper.HTTP.ContentClientTest do
  use Pepper.HTTP.Support.ClientCase

  alias Pepper.HTTP.ContentClient, as: Client

  import Plug.Conn
  import Pepper.HTTP.Utils

  @user_agent "content-client-test/1.0"

  @port 9899

  @response_body_types [:none, :json, :text, :xml, :csv, :other]

  setup tags do
    tags =
      case tags[:with_connection_pool] do
        true ->
          {:ok, pid} =
            start_supervised({Pepper.HTTP.ConnectionManager.Pooled, [
              [pool_size: 10],
              []
            ]})

          Map.put(tags, :connection_pool_pid, pid)

        false ->
          tags
      end

    protocol = String.to_existing_atom(Map.fetch!(tags, :protocol))

    client_options = [
      connect_options: [
        protocols: [protocol]
      ]
    ]

    client_options =
      case tags[:connection_pool_pid] do
        nil ->
          client_options

        pid ->
          Keyword.merge(client_options, [
            connection_manager: :pooled,
            connection_manager_id: pid,
          ])
      end

    Map.put(tags, :client_options, client_options)
  end

  for with_connection_pool <- [true, false] do
    for protocol <- [:http1, :http2] do
      for {method, method_string} <- [{:get, "GET"}, {:delete, "DELETE"}] do
        describe "request/6 [with_connection_pool:#{with_connection_pool}, protocol:#{protocol}, method:#{method}]" do
          @describetag with_connection_pool: with_connection_pool, protocol: to_string(protocol), method: to_string(method)

          test "can issue a simple http request and receive a 204 status", %{client_options: client_options} do
            test_no_content_response(%{
              protocol: unquote(protocol),
              method: unquote(method),
              method_string: unquote(method_string),
              client_options: client_options
            })
          end
        end

        for response_body_type <- @response_body_types do
          describe "request/6 [with_connection_pool:#{with_connection_pool}, protocol:#{protocol}, method:#{method}, response_body:#{response_body_type}]" do
            @describetag with_connection_pool: with_connection_pool, protocol: to_string(protocol), method: to_string(method)

            test "is inline process safe", %{client_options: client_options} do
              test_inline_process_is_safe(%{
                protocol: unquote(protocol),
                method: unquote(method),
                method_string: unquote(method_string),
                response_body_type: unquote(response_body_type),
                client_options: client_options,
              })
            end

            test "can issue an http request with query parameters", %{client_options: client_options} do
              test_request_with_query_params(%{
                protocol: unquote(protocol),
                method: unquote(method),
                method_string: unquote(method_string),
                response_body_type: unquote(response_body_type),
                client_options: client_options,
              })
            end

            test "can issue an http request which will return a specific body type", %{client_options: client_options} do
              test_request_response_only(%{
                protocol: unquote(protocol),
                method: unquote(method),
                method_string: unquote(method_string),
                response_body_type: unquote(response_body_type),
                client_options: client_options,
              })
            end
          end
        end
      end

      for {method, method_string} <- [{:post, "POST"}, {:patch, "PATCH"}, {:put, "PUT"}] do
        describe "request/6 [with_connection_pool:#{with_connection_pool}, protocol:#{protocol}, method:#{method}]" do
          @describetag with_connection_pool: with_connection_pool, protocol: to_string(protocol), method: to_string(method)

          test "can issue a urlencoded form http request and receive a 204 status", %{client_options: client_options} do
            test_urlencoded_request_with_no_content_response(%{
              protocol: unquote(protocol),
              method: unquote(method),
              method_string: unquote(method_string),
              client_options: client_options
            })
          end

          test "can issue a form-data http request and receive a 204 status", %{client_options: client_options} do
            test_form_data_request_with_no_content_response(%{
              protocol: unquote(protocol),
              method: unquote(method),
              method_string: unquote(method_string),
              client_options: client_options
            })
          end

          test "can issue a json http request and receive a 204 status", %{client_options: client_options} do
            test_json_request_with_no_content_response(%{
              protocol: unquote(protocol),
              method: unquote(method),
              method_string: unquote(method_string),
              client_options: client_options
            })
          end

          test "can issue an xml http request and receive a 204 status", %{client_options: client_options} do
            test_xml_request_with_no_content_response(%{
              protocol: unquote(protocol),
              method: unquote(method),
              method_string: unquote(method_string),
              client_options: client_options
            })
          end

          test "can send a large text blob (without server reading)", %{client_options: client_options} do
            test_large_text_request_with_no_content_response(%{
              protocol: unquote(protocol),
              method: unquote(method),
              method_string: unquote(method_string),
              client_options: client_options,
              server_read: false
            })
          end

          test "can send a large text blob (with server reading)", %{client_options: client_options} do
            test_large_text_request_with_no_content_response(%{
              protocol: unquote(protocol),
              method: unquote(method),
              method_string: unquote(method_string),
              client_options: client_options,
              server_read: true
            })
          end
        end

        for response_body_type <- @response_body_types do
          describe "request/6 [with_connection_pool:#{with_connection_pool}, protocol:#{protocol}, method:#{method}, response_body_type:#{response_body_type}]" do
            @describetag with_connection_pool: with_connection_pool, protocol: to_string(protocol), method: to_string(method), response_body_type: response_body_type
          end
        end
      end
    end
  end

  # 16mb blob
  @large_text_blob generate_random_base32(0x100_0000)

  defp large_text_blob do
    @large_text_blob
  end

  defp test_large_text_request_with_no_content_response(options) do
    %{
      protocol: protocol,
      method: method,
      method_string: method_string,
      client_options: client_options,
      server_read: server_read?
    } = options

    bypass = Bypass.open(port: @port)

    blob = large_text_blob()

    Bypass.expect(bypass, method_string, "/path", fn conn ->
      assert [@user_agent] == get_req_header(conn, "user-agent")
      assert ["text/plain"] == get_req_header(conn, "content-type")

      conn =
        if server_read? do
          {:ok, text, conn} = read_all_body(conn)
          assert blob == text
          conn
        else
          conn
        end

      send_resp(conn, 204, "")
    end)

    headers = [
      {"accept", "*/*"},
      {"user-agent", @user_agent}
    ]

    query_params = []

    body = {:text, blob}

    assert {:ok, %{protocol: ^protocol, status_code: 204}, {:unk, ""}} =
      Client.request(
        method,
        "http://localhost:#{bypass.port}/path",
        query_params,
        headers,
        body,
        Keyword.merge([
         recv_timeout: 5000,
        ], client_options)
      )
  end

  defp test_xml_request_with_no_content_response(options) do
    %{
      protocol: protocol,
      method: method,
      method_string: method_string,
      client_options: client_options
    } = options

    bypass = Bypass.open(port: @port)

    Bypass.expect(bypass, method_string, "/path", fn conn ->
      assert [@user_agent] == get_req_header(conn, "user-agent")
      assert ["application/xml"] == get_req_header(conn, "content-type")

      {:ok, body, conn} = handle_xml_request(conn)

      # TODO: compare this to the given
      assert body

      send_resp(conn, 204, "")
    end)

    headers = [
      {"accept", "*/*"},
      {"user-agent", @user_agent}
    ]

    query_params = []

    body =
      {:xml,
       XmlBuilder.document([
         {:head, [],
          [
            {:ref, [], ["Test Value"]}
          ]}
       ])}

    assert {:ok, %{protocol: ^protocol, status_code: 204}, {:unk, ""}} =
      Client.request(
        method,
        "http://localhost:#{bypass.port}/path",
        query_params,
        headers,
        body,
        client_options
      )
  end

  defp test_json_request_with_no_content_response(options) do
    %{
      protocol: protocol,
      method: method,
      method_string: method_string,
      client_options: client_options
    } = options

    bypass = Bypass.open(port: @port)

    Bypass.expect(bypass, method_string, "/path", fn conn ->
      assert [@user_agent] == get_req_header(conn, "user-agent")
      assert ["application/json"] == get_req_header(conn, "content-type")

      {:ok, doc, conn} = handle_json_request(conn)

      assert %{
               "body" => "Hello, World"
             } == doc

      send_resp(conn, 204, "")
    end)

    headers = [
      {"accept", "*/*"},
      {"user-agent", @user_agent}
    ]

    query_params = []

    body =
      {:json,
       %{
         body: "Hello, World"
       }}

    assert {:ok, %{protocol: ^protocol, status_code: 204}, {:unk, ""}} =
      Client.request(
        method,
        "http://localhost:#{bypass.port}/path",
        query_params,
        headers,
        body,
        client_options
      )
  end

  defp test_urlencoded_request_with_no_content_response(options) do
    %{
      protocol: protocol,
      method: method,
      method_string: method_string,
      client_options: client_options
    } = options

    bypass = Bypass.open(port: @port)

    Bypass.expect(bypass, method_string, "/path", fn conn ->
      conn = fetch_query_params(conn)

      assert [@user_agent] == get_req_header(conn, "user-agent")
      assert ["application/x-www-form-urlencoded"] == get_req_header(conn, "content-type")

      {:ok, doc, conn} = handle_urlencoded_request(conn)

      assert %{
        "action" => "Test",
        "other" => "Data",
        "list" => ["1", "2", "3"],
        "submap" => %{
          "a" => "A",
          "b" => "B",
          "c" => "C"
        }
      } == doc

      send_resp(conn, 204, "")
    end)

    headers = [
      {"accept", "*/*"},
      {"user-agent", @user_agent}
    ]

    query_params = []

    body =
      {:form_urlencoded,
       [
         {"action", "Test"},
         {"other", "Data"},
         {"list", ["1", "2", "3"]},
         {"submap",
          [
            {"a", "A"},
            {"b", "B"},
            {"c", "C"}
          ]}
       ]}

    assert {:ok, %{protocol: ^protocol, status_code: 204}, {:unk, ""}} =
      Client.request(
        method,
        "http://localhost:#{bypass.port}/path",
        query_params,
        headers,
        body,
        client_options
      )
  end

  defp test_form_data_request_with_no_content_response(options) do
    %{
      protocol: protocol,
      method: method,
      method_string: method_string,
      client_options: client_options
    } = options

    bypass = Bypass.open(port: @port)

    parent = self()

    Bypass.expect(bypass, method_string, "/path", fn conn ->
      conn = fetch_query_params(conn)

      assert [@user_agent] == get_req_header(conn, "user-agent")

      assert ["multipart/form-data; boundary=" <> _boundary] =
               get_req_header(conn, "content-type")

      {:ok, doc, conn} = handle_multipart_request(conn)

      send(parent, {:request_body, doc})

      send_resp(conn, 204, "")
    end)

    headers = [
      {"accept", "*/*"},
      {"user-agent", @user_agent}
    ]

    query_params = []

    body =
      {:form,
       [
         {"file1", [{"content-type", "text/plain"}],
          """
          Some data here
          """},
         {"attr", [{"content-type", "text/x-attribute"}], "Value"}
       ]}

    assert {:ok, %{protocol: ^protocol, status_code: 204}, {:unk, ""}} =
      Client.request(
        method,
        "http://localhost:#{bypass.port}/path",
        query_params,
        headers,
        body,
        client_options
      )

    receive do
      {:request_body, doc} ->
        assert [
          %{
            body: ["Some data here"],
            headers: [
              {"content-disposition", "form-data; name=\"file1\""},
              {"content-length", "15"},
              {"content-type", "text/plain"},
            ]
          },
          %{
            body: ["Value"],
            headers: [
              {"content-disposition", "form-data; name=\"attr\""},
              {"content-length", "5"},
              {"content-type", "text/x-attribute"},
            ]
          }
        ] = doc

    after 5000 ->
      flunk "timeout while waiting for request body"
    end
  end

  defp test_request_with_query_params(options) do
    %{
      protocol: protocol,
      method: method,
      method_string: method_string,
      client_options: client_options
    } = options

    bypass = Bypass.open(port: @port)

    Bypass.expect(bypass, method_string, "/path", fn conn ->
      conn = fetch_query_params(conn)

      assert [@user_agent] == get_req_header(conn, "user-agent")

      assert %{
        "a" => "value",
        "b" => [
          "1",
          "2",
          "3"
        ],
        "c" => %{
          "x" => "X",
          "y" => "Dy",
          "z" => "BIGZ"
        }
      } == conn.query_params

      send_resp(conn, 204, "")
    end)

    headers = [
      {"accept", "*/*"},
      {"user-agent", @user_agent}
    ]

    query_params = [
      a: "value",
      b: ["1", "2", "3"],
      c: [
        {:x, "X"},
        {:y, "Dy"},
        {:z, "BIGZ"}
      ]
    ]

    assert {:ok, %{protocol: ^protocol, status_code: 204}, {:unk, ""}} =
      Client.request(
        method,
        "http://localhost:#{bypass.port}/path",
        query_params,
        headers,
        "",
        client_options
      )
  end

  defp test_no_content_response(options) do
    %{
      protocol: protocol,
      method: method,
      method_string: method_string,
      client_options: client_options
    } = options

    bypass = Bypass.open(port: @port)

    Bypass.expect(bypass, method_string, "/path", fn conn ->
      assert [@user_agent] == get_req_header(conn, "user-agent")

      send_resp(conn, 204, "")
    end)

    headers = [
      {"accept", "*/*"},
      {"user-agent", @user_agent}
    ]

    query_params = []

    assert {:ok, %{protocol: ^protocol, status_code: 204}, {:unk, ""}} =
      Client.request(
        method,
        "http://localhost:#{bypass.port}/path",
        query_params,
        headers,
        "",
        client_options
      )
  end

  defp test_inline_process_is_safe(options) do
    %{
      protocol: protocol,
      method: method,
      method_string: method_string,
      client_options: client_options
    } = options
    # mint has a habit of throwing a bunch of 'unknown' responses back while fetching responses
    # this test ensures it isn't eating the parent process' messages for itself and discarding
    # them
    me = self()

    child =
      spawn_link(fn ->
        receive do
          :execute ->
            send(me, :a)
            send(me, :b)
            send(me, :c)
            send(me, :d)
        after
          5000 ->
            flunk("timeout")
        end
      end)

    bypass = Bypass.open(port: @port)

    Bypass.expect(bypass, method_string, "/path", fn conn ->
      assert [@user_agent] == get_req_header(conn, "user-agent")

      send(child, :execute)
      Process.sleep(100)

      send_resp(conn, 200, "DONE")
    end)

    headers = [
      {"accept", "*/*"},
      {"user-agent", @user_agent}
    ]

    query_params = []

    assert {:ok, %{protocol: ^protocol, status_code: 200}, {:unk, "DONE"}} =
      Client.request(
        method,
        "http://localhost:#{bypass.port}/path",
        query_params,
        headers,
        "",
        client_options
      )

    for letter <- [:a, :b, :c, :d] do
      receive do
        ^letter -> :ok
      after
        1000 ->
          flunk("missing :a message")
      end
    end
  end

  def test_request_response_only(options) do
    %{
      protocol: protocol,
      method: method,
      method_string: method_string,
      response_body_type: response_body_type,
      client_options: client_options
    } = options

    bypass = Bypass.open(port: @port)

    Bypass.expect(bypass, method_string, "/path", fn conn ->
      assert [@user_agent] == get_req_header(conn, "user-agent")

      case response_body_type do
        :none ->
          send_resp(conn, 200, "")

        :text ->
          conn
          |> put_resp_content_type("text/plain")
          |> send_resp(200, "Hello, World")

        :csv ->
          conn
          |> put_resp_content_type("application/csv")
          |> send_resp(200, "header1,header2\r\nr1_value1,r1_value2\r\nr2_value1,r2_value2\r\nr3_value1,r3_value2")

        :json ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            200,
            Jason.encode!(%{
              body: "Hello, World"
            })
          )

        :xml ->
          conn
          |> put_resp_content_type("application/xml")
          |> send_resp(200, """
          <head>
            <ref>Test value</ref>
          </head>
          """)

        :other ->
          conn
          |> put_resp_content_type("application/x-other")
          |> send_resp(200, """
          Some content type blah de dah
          """)
      end
    end)

    headers = [
      {"accept", "*/*"},
      {"user-agent", @user_agent}
    ]

    query_params = []

    assert {:ok, %{protocol: ^protocol, status_code: 200}, body} =
      Client.request(
        method,
        "http://localhost:#{bypass.port}/path",
        query_params,
        headers,
        "",
        client_options
      )

    case body do
      {:text, blob} ->
        assert :text == response_body_type
        assert "Hello, World" == blob

      {:csv, blob} ->
        rows =
          blob
          |> String.split("\r\n")
          |> CSV.decode(headers: true)
          |> Enum.map(fn {:ok, row} ->
            row
          end)
          |> Enum.into([])

        assert [
          %{
            "header1" => "r1_value1",
            "header2" => "r1_value2",
          },
          %{
            "header1" => "r2_value1",
            "header2" => "r2_value2",
          },
          %{
            "header1" => "r3_value1",
            "header2" => "r3_value2",
          },
        ] == rows

      {:json, %{"body" => "Hello, World"}} ->
        assert :json == response_body_type

      {:jsonapi, %{"body" => "Hello, World"}} ->
        assert :jsonapi == response_body_type

      {:xml, _doc} ->
        assert :xml == response_body_type

      {:unk, _} ->
        assert response_body_type in [:other, :none]
    end
  end
end
