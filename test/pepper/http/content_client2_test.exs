defmodule Pepper.HTTP.ContentClient2Test do
  use Pepper.HTTP.Support.ClientCase

  for protocol <- [:http1, :http2] do
    for {method, method_string} <- [{:post, "POST"}, {:patch, "PATCH"}, {:put, "PUT"}] do
      describe "request/6 [protocol:#{protocol}, method:#{method}, body:text]" do
        test "can send a large text blob (without server reading body)" do
          client_options = [
            connect_options: [
              protocols: [unquote(protocol)]
            ]
          ]

          blob = Pepper.HTTP.Utils.generate_random_base32(0x100_0000)

          bypass = Bypass.open()

          Bypass.expect bypass, unquote(method_string), "/path/to/text", fn conn ->
            conn
            |> send_resp(204, "")
          end

          headers = [
            {"accept", "*/*"},
            {"user-agent", @user_agent}
          ]

          query_params = []

          body = {:text, blob}

          assert {:ok, %{status_code: 204}, {:unk, ""}} =
            ContentClient.request(
              unquote(method),
              "http://localhost:#{bypass.port}/path/to/text",
              query_params,
              headers,
              body,
              Keyword.merge([
                recv_timeout: 5000,
              ], client_options)
            )
        end

        test "can send a large text blob (with server reading body)" do
          client_options = [
            connect_options: [
              protocols: [unquote(protocol)]
            ]
          ]

          blob = Pepper.HTTP.Utils.generate_random_base32(0x100_0000)

          bypass = Bypass.open()

          Bypass.expect bypass, unquote(method_string), "/path/to/text", fn conn ->
            {:ok, body, conn} = read_all_body(conn)

            assert blob == body

            conn
            |> send_resp(204, "")
          end

          headers = [
            {"accept", "*/*"},
            {"user-agent", @user_agent}
          ]

          query_params = []

          body = {:text, blob}

          assert {:ok, %{status_code: 204}, {:unk, ""}} =
            ContentClient.request(
              unquote(method),
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

      describe "request/6 [protocol:#{protocol}, method:#{method}, body:form-data]" do
        # test "can send a form-data" do
        # end
      end
    end

    for {method, method_string} <- [{:get, "GET"}, {:delete, "DELETE"}] do
      describe "request/6 [protocol:#{protocol}, method:#{method}, body:json]" do
        test "will not parse an json response if not accepted" do
          bypass = Bypass.open()

          Bypass.expect bypass, unquote(method_string), "/path/to/json", fn conn ->
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
              unquote(method),
              "http://localhost:#{bypass.port}/path/to/json",
              @no_query_params,
              headers,
              @no_body,
              @no_options
            )
        end

        test "will parse an json response if no accept header is given" do
          bypass = Bypass.open()

          Bypass.expect bypass, unquote(method_string), "/path/to/json", fn conn ->
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
              unquote(method),
              "http://localhost:#{bypass.port}/path/to/json",
              @no_query_params,
              @no_headers,
              @no_body,
              @no_options
            )
        end

        test "will parse an json response if accepted" do
          bypass = Bypass.open()

          Bypass.expect bypass, unquote(method_string), "/path/to/json", fn conn ->
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
              unquote(method),
              "http://localhost:#{bypass.port}/path/to/json",
              @no_query_params,
              headers,
              @no_body,
              @no_options
            )

          assert %{
            "response" => %{
              "status" => "ok"
            }
          } = doc
        end
      end

      describe "request/6 [protocol:#{protocol}, method:#{method}, body:xml]" do
        test "will not parse an xml response if not accepted" do
          bypass = Bypass.open()

          Bypass.expect bypass, unquote(method_string), "/path/to/xml", fn conn ->
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
              unquote(method),
              "http://localhost:#{bypass.port}/path/to/xml",
              @no_query_params,
              headers,
              @no_body,
              @no_options
            )
        end

        test "will parse an xml response if no accept header is given" do
          bypass = Bypass.open()

          Bypass.expect bypass, unquote(method_string), "/path/to/xml", fn conn ->
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
              unquote(method),
              "http://localhost:#{bypass.port}/path/to/xml",
              @no_query_params,
              @no_headers,
              @no_body,
              @no_options
            )
        end

        test "will parse an xml response if accepted" do
          bypass = Bypass.open()

          Bypass.expect bypass, unquote(method_string), "/path/to/xml", fn conn ->
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
              unquote(method),
              "http://localhost:#{bypass.port}/path/to/xml",
              @no_query_params,
              headers,
              @no_body,
              @no_options
            )

          # normalized xml
          assert {:ok, %{status_code: 200}, {:xmldoc, doc}} =
            ContentClient.request(
              unquote(method),
              "http://localhost:#{bypass.port}/path/to/xml",
              @no_query_params,
              headers,
              @no_body,
              normalize_xml: true
            )

          assert [%{
            :Response => [%{
              :Status => ["OK"]
            }]
          }] = doc
        end
      end
    end
  end
end
