defmodule Pepper.HTTP.ContentClient2Test do
  use Pepper.HTTP.Support.ClientCase

  for protocol <- [:http1, :http2] do
    for {method, method_string} <- [{:post, "POST"}, {:patch, "PATCH"}, {:put, "PUT"}] do
      describe "request/6 [protocol:#{protocol}, method:#{method}, body:text]" do
        test "can send a large text blob (without server reading body)" do
          test_send_large_text_blob(%{
            server_read_body: false,
            protocol: unquote(protocol),
            method: unquote(method),
            method_string: unquote(method_string)
          })
        end

        test "can send a large text blob (with server reading body)" do
          test_send_large_text_blob(%{
            server_read_body: true,
            protocol: unquote(protocol),
            method: unquote(method),
            method_string: unquote(method_string)
          })
        end
      end

      describe "request/6 [protocol:#{protocol}, method:#{method}, body:form-data]" do
        # test "can send a form-data" do
        # end
      end
    end

    for {method, method_string} <- [{:get, "GET"}, {:delete, "DELETE"}] do
      describe "request/6 [protocol:#{protocol}, method:#{method}, body:json]" do
        test "will not parse an json response if not accepted" do
          test_json_unparsed_with_header(%{
            protocol: unquote(protocol),
            method: unquote(method),
            method_string: unquote(method_string)
          })
        end

        test "will parse an json response if no accept header is given" do
          test_json_parsed_without_header(%{
            protocol: unquote(protocol),
            method: unquote(method),
            method_string: unquote(method_string)
          })
        end

        test "will parse an json response if accepted" do
          test_json_parsed_with_accept(%{
            protocol: unquote(protocol),
            method: unquote(method),
            method_string: unquote(method_string)
          })
        end
      end

      describe "request/6 [protocol:#{protocol}, method:#{method}, body:xml]" do
        test "will not parse an xml response if not accepted" do
          test_xml_unparsed_with_unaccepted(%{
            protocol: unquote(protocol),
            method: unquote(method),
            method_string: unquote(method_string)
          })
        end

        test "will parse an xml response if no accept header is given" do
          test_xml_parsed_without_header(%{
            protocol: unquote(protocol),
            method: unquote(method),
            method_string: unquote(method_string)
          })
        end

        test "will parse an xml response if accepted" do
          test_xml_parsed_if_accepted(%{
            protocol: unquote(protocol),
            method: unquote(method),
            method_string: unquote(method_string)
          })
        end
      end
    end
  end

  defp test_send_large_text_blob(options) do
    %{
      protocol: protocol,
      method: method,
      method_string: method_string,
      server_read_body: server_read_body?,
    } = options

    client_options = [
      connect_options: [
        protocols: [protocol]
      ]
    ]

    blob = Pepper.HTTP.Utils.generate_random_base32(0x100_0000)

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

    assert {:ok, %{status_code: 204}, {:unk, ""}} =
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

  defp test_json_unparsed_with_header(options) do
    %{
      protocol: protocol,
      method: method,
      method_string: method_string,
    } = options

    client_options = [
      connect_options: [
        protocols: [protocol]
      ]
    ]

    bypass = Bypass.open()

    Bypass.expect bypass, method_string, "/path/to/json", fn conn ->
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, """
      {
        "response": {
          "status": "ok"
        }
      }
      """)
    end

    headers = [
      {"Accept", "application/xml"}
    ]

    assert {:ok, %{status_code: 200}, {:unk, _}} =
      ContentClient.request(
        method,
        "http://localhost:#{bypass.port}/path/to/json",
        @no_query_params,
        headers,
        @no_body,
        client_options
      )
  end

  defp test_json_parsed_without_header(options) do
    %{
      protocol: protocol,
      method: method,
      method_string: method_string,
    } = options

    client_options = [
      connect_options: [
        protocols: [protocol]
      ]
    ]

    bypass = Bypass.open()

    Bypass.expect bypass, method_string, "/path/to/json", fn conn ->
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, """
      {
        "response": {
          "status": "ok"
        }
      }
      """)
    end

    assert {:ok, %{status_code: 200}, {:json, _}} =
      ContentClient.request(
        method,
        "http://localhost:#{bypass.port}/path/to/json",
        @no_query_params,
        @no_headers,
        @no_body,
        client_options
      )
  end

  defp test_json_parsed_with_accept(options) do
    %{
      protocol: protocol,
      method: method,
      method_string: method_string,
    } = options

    client_options = [
      connect_options: [
        protocols: [protocol]
      ]
    ]

    bypass = Bypass.open()

    Bypass.expect bypass, method_string, "/path/to/json", fn conn ->
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, """
      {
        "response": {
          "status": "ok"
        }
      }
      """)
    end

    headers = [
      # testing downcased headers
      {"Accept", "application/json"}
    ]

    # regular json
    assert {:ok, %{status_code: 200}, {:json, doc}} =
      ContentClient.request(
        method,
        "http://localhost:#{bypass.port}/path/to/json",
        @no_query_params,
        headers,
        @no_body,
        client_options
      )

    assert %{
      "response" => %{
        "status" => "ok"
      }
    } = doc
  end

  defp test_xml_unparsed_with_unaccepted(options) do
    %{
      protocol: protocol,
      method: method,
      method_string: method_string,
    } = options

    client_options = [
      connect_options: [
        protocols: [protocol]
      ]
    ]

    bypass = Bypass.open()

    Bypass.expect bypass, method_string, "/path/to/xml", fn conn ->
      conn
      |> put_resp_content_type("application/xml")
      |> send_resp(200, """
      <Response>
        <Status>OK</Status>
      </Response>
      """)
    end

    headers = [
      {"Accept", "application/json"}
    ]

    assert {:ok, %{status_code: 200}, {:unk, _}} =
      ContentClient.request(
        method,
        "http://localhost:#{bypass.port}/path/to/xml",
        @no_query_params,
        headers,
        @no_body,
        client_options
      )
  end

  defp test_xml_parsed_without_header(options) do
    %{
      protocol: protocol,
      method: method,
      method_string: method_string,
    } = options

    client_options = [
      connect_options: [
        protocols: [protocol]
      ]
    ]

    bypass = Bypass.open()

    Bypass.expect bypass, method_string, "/path/to/xml", fn conn ->
      conn
      |> put_resp_content_type("application/xml")
      |> send_resp(200, """
      <Response>
        <Status>OK</Status>
      </Response>
      """)
    end

    assert {:ok, %{status_code: 200}, {:xml, _}} =
      ContentClient.request(
        method,
        "http://localhost:#{bypass.port}/path/to/xml",
        @no_query_params,
        @no_headers,
        @no_body,
        client_options
      )
  end

  defp test_xml_parsed_if_accepted(options) do
    %{
      protocol: protocol,
      method: method,
      method_string: method_string,
    } = options

    client_options = [
      connect_options: [
        protocols: [protocol]
      ]
    ]

    bypass = Bypass.open()

    Bypass.expect bypass, method_string, "/path/to/xml", fn conn ->
      conn
      |> put_resp_content_type("application/xml")
      |> send_resp(200, """
      <Response><Status>OK</Status></Response>
      """)
    end

    headers = [
      # testing downcased headers
      {"Accept", "application/xml"}
    ]

    # regular xml
    assert {:ok, %{status_code: 200}, {:xml, _}} =
      ContentClient.request(
        method,
        "http://localhost:#{bypass.port}/path/to/xml",
        @no_query_params,
        headers,
        @no_body,
        client_options
      )

    # normalized xml
    assert {:ok, %{status_code: 200}, {:xmldoc, doc}} =
      ContentClient.request(
        method,
        "http://localhost:#{bypass.port}/path/to/xml",
        @no_query_params,
        headers,
        @no_body,
        Keyword.put(client_options, :normalize_xml, true)
      )

    assert [%{
      :Response => [%{
        :Status => ["OK"]
      }]
    }] = doc
  end
end
