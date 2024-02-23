defmodule Pepper.HTTP.ContentClient.AcceptHeaderTest do
  use Pepper.HTTP.Support.ClientCase

  Enum.each([true, false], fn with_connection_pool ->
    Enum.each([:http1, :http2], fn protocol ->
      Enum.each([{:get, "GET"}, {:delete, "DELETE"}], fn {method, method_string} ->
        describe "request/6 [with_connection_pool:#{with_connection_pool}, protocol:#{protocol}, method:#{method}, body:json]" do
          @describetag with_connection_pool: with_connection_pool, protocol: to_string(protocol), method: to_string(method)

          test "will not parse an json response if not accepted", %{client_options: client_options} do
            test_json_unparsed_with_header(%{
              protocol: unquote(protocol),
              method: unquote(method),
              method_string: unquote(method_string),
              client_options: client_options,
            })
          end

          test "will parse an json response if no accept header is given", %{client_options: client_options} do
            test_json_parsed_without_header(%{
              protocol: unquote(protocol),
              method: unquote(method),
              method_string: unquote(method_string),
              client_options: client_options,
            })
          end

          test "will parse an json response if accepted", %{client_options: client_options} do
            test_json_parsed_with_accept(%{
              protocol: unquote(protocol),
              method: unquote(method),
              method_string: unquote(method_string),
              client_options: client_options,
            })
          end
        end

        describe "request/6 [with_connection_pool:#{with_connection_pool}, protocol:#{protocol}, method:#{method}, body:xml]" do
          @describetag with_connection_pool: with_connection_pool, protocol: to_string(protocol), method: to_string(method)

          test "will not parse an xml response if not accepted", %{client_options: client_options} do
            test_xml_unparsed_with_unaccepted(%{
              protocol: unquote(protocol),
              method: unquote(method),
              method_string: unquote(method_string),
              client_options: client_options,
            })
          end

          test "will parse an xml response if no accept header is given", %{client_options: client_options} do
            test_xml_parsed_without_header(%{
              protocol: unquote(protocol),
              method: unquote(method),
              method_string: unquote(method_string),
              client_options: client_options,
            })
          end

          test "will parse an xml response if accepted", %{client_options: client_options} do
            test_xml_parsed_if_accepted(%{
              protocol: unquote(protocol),
              method: unquote(method),
              method_string: unquote(method_string),
              client_options: client_options,
            })
          end
        end
      end)
    end)
  end)

  defp test_json_unparsed_with_header(options) do
    %{
      protocol: protocol,
      method: method,
      method_string: method_string,
      client_options: client_options,
    } = options

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

    assert {:ok, %{protocol: ^protocol, status_code: 200}, {:unaccepted, _}} =
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
      client_options: client_options,
    } = options

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

    assert {:ok, %{protocol: ^protocol, status_code: 200}, {:json, _}} =
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
      client_options: client_options,
    } = options

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
    assert {:ok, %{protocol: ^protocol, status_code: 200}, {:json, doc}} =
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
      client_options: client_options,
    } = options

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

    assert {:ok, %{protocol: ^protocol, status_code: 200}, {:unaccepted, _}} =
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
      client_options: client_options,
    } = options

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

    assert {:ok, %{protocol: ^protocol, status_code: 200}, {:xml, _}} =
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
      client_options: client_options,
    } = options

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
    assert {:ok, %{protocol: ^protocol, status_code: 200}, {:xml, _}} =
      ContentClient.request(
        method,
        "http://localhost:#{bypass.port}/path/to/xml",
        @no_query_params,
        headers,
        @no_body,
        client_options
      )

    # normalized xml
    assert {:ok, %{protocol: ^protocol, status_code: 200}, {:xmldoc, doc}} =
      ContentClient.request(
        method,
        "http://localhost:#{bypass.port}/path/to/xml",
        @no_query_params,
        headers,
        @no_body,
        Keyword.put(client_options, :normalize_xml, true)
      )

    assert [%{
      "Response" => [%{
        "Status" => ["OK"]
      }]
    }] = doc
  end
end
