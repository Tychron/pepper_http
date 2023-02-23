defmodule Pepper.HTTP.ContentClient do
  alias Pepper.HTTP.Client
  alias Pepper.HTTP.Response
  alias Pepper.HTTP.Proplist

  import Pepper.HTTP.Utils

  @type method :: Client.method()

  @typedoc """
  A header pair

  Example:

  {"content-type", "application/json"}
  """
  @type header :: {name::String.t(), value::String.t()}

  @type headers :: [header()]

  @type form_body_item :: {name::String.t(), headers(), blob::binary()}

  @type form_body :: {:form, [form_body_item()]}

  @type body :: form_body()
              | {:json, term()}
              | {:xml, term()}
              | {:text, term()}
              | {:csv, term()}
              | {:form_urlencoded, term()}
              | {:stream, term()}
              | {:form_stream, term()}
              | nil

  @type url :: Client.url()

  @type query_params :: Keyword.t()

  @typedoc """
  Options that can be passed into the request function

  * `normalize_xml` [Boolean] - the client will normally return the parsed format directly off
                                SweetXml, with normalize_xml it will attempt to map it into a map
                                and list format that can be immediately consumed as needed.
  """
  @type request_option ::
          {:normalize_xml, boolean()}
          | {:auth_method, String.t() | :none | :basic | :bearer}
          | {:auth_identity, String.t()}
          | {:auth_secret, String.t()}
          | Client.request_option()

  @type options :: [request_option()]

  @type response_body :: {:json, term()}
                       | {:jsonapi, term()}
                       | {:xmldoc, term()}
                       | {:xml, term()}
                       | {:text, term()}
                       | {:csv, term()}
                       | {:unk, term()}

  @type response_error :: Pepper.HTTP.BodyError.t() | Client.response_error()

  @type response :: {:ok, Response.t(), response_body()} | {:error, response_error()}

  @spec request(method(), url(), query_params(), headers(), body(), options()) :: response()
  def request(method, url, query_params, headers, body, options \\ []) do
    case encode_body(body) do
      {:ok, {body_headers, blob}} ->
        new_url = encode_new_url(url, query_params)

        all_headers = body_headers ++ Enum.map(headers, fn {key, value} ->
          {String.downcase(key), value}
        end)

        {all_headers, options} = maybe_add_auth_headers(all_headers, options)

        Client.request(method, new_url, all_headers, blob, options)
        |> handle_response(options)

      {:error, reason} ->
        error =
          %Pepper.HTTP.BodyError{
            message: "body encoding failed",
            reason: reason,
            body: body,
          }

        {:error, error}
    end
  end

  def post(url, query_params, headers, body, options \\ []) do
    request(:post, url, query_params, headers, body, options)
  end

  def patch(url, query_params, headers, body, options \\ []) do
    request(:patch, url, query_params, headers, body, options)
  end

  def put(url, query_params, headers, body, options \\ []) do
    request(:put, url, query_params, headers, body, options)
  end

  def delete(url, query_params \\ [], headers \\ [], options \\ []) do
    request(:delete, url, query_params, headers, nil, options)
  end

  def get(url, query_params \\ [], headers \\ [], options \\ []) do
    request(:get, url, query_params, headers, nil, options)
  end

  defp maybe_add_auth_headers(headers, options) do
    {auth_method, options} = Keyword.pop(options, :auth_method, "none")
    {username, options} = Keyword.pop(options, :auth_identity)
    {password, options} = Keyword.pop(options, :auth_secret)

    headers =
      case to_string(auth_method) do
        "none" ->
          headers

        "basic" ->
          auth = Base.encode64("#{username}:#{password}")

          [
            {"authorization", "Basic #{auth}"}
            | headers
          ]

        "bearer" ->
          [
            {"authorization", "Bearer #{password}"}
            | headers
          ]

        _ ->
          headers
      end

    {headers, options}
  end

  defp handle_response({:ok, %Response{} = response}, options) do
    {:ok, response, decode_body(response, options)}
  end

  defp handle_response({:error, reason}, _options) do
    {:error, reason}
  end

  defp decode_body(%Response{
    request: %{
      headers: req_headers,
    },
    headers: res_headers,
    body: body
  }, options) do
    # retrieve the original request accept header, this will be used to "allow" the content-type
    # to be parsed
    accept = Proplist.get(req_headers, "accept")
    # retrieve the response content-type
    content_type = Proplist.get(res_headers, "content-type")

    # ensure that we only parse content for the given accept header to avoid parsing bodies we
    # didn't want or even expect
    accepted_content_type =
      case accept do
        nil ->
          # no accept header was given, expect to parse anything, this is dangerous
          # but allows the default behaviour to continue
          # you should ALWAYS specify an accept header
          content_type

        _ ->
          if content_type do
            # a content-type was returned, try negotiate with the accept header and content-type
            case :accept_header.negotiate(accept, [content_type]) do
              :undefined ->
                # mismatch accept and content-type, refuse to parse the content and return
                # nil for the accepted_content_type
                nil

              name when is_binary(name) ->
                # return the matched content_type
                name
            end
          else
            # there was no content-type, return nil
            nil
          end
      end

    type =
      if accepted_content_type do
        case Plug.Conn.Utils.content_type(accepted_content_type) do
          {:ok, "application", "json", _params} ->
            # parse standard json
            :json

          {:ok, "application", "vnd.api+json", _params} ->
            # parse jsonapi
            :jsonapi

          {:ok, "application", "xml", _params} ->
            # parse application xml
            :xml

          {:ok, "text", "xml", _params} ->
            # parse text xml
            :xml

          {:ok, "text", "plain", _params} ->
            # return plain text as is
            :text

          {:ok, "text", "csv", _params} ->
            # return csv as is
            :csv

          {:ok, "application", "csv", _params} ->
            # return csv as is
            :csv

          {:ok, _, _, _} ->
            # some other content-type, return it as unknown
            :unk

          :error ->
            # the content-type failed to parse, return it as unknown as well
            :unk
        end
      else
        # no content-type or mismatched content-type and accept, return unk(nown)
        :unk
      end

    case type do
      type when type in [:json, :jsonapi] ->
        case Jason.decode(body) do
          {:ok, doc} ->
            {type, doc}

          {:error, _} ->
            {:unk, body}
        end

      :xml ->
        data = SweetXml.parse(body)
        # Parse XML
        if options[:normalize_xml] do
          {:xmldoc, handle_xml_body(data)}
        else
          {type, data}
        end

      type ->
        {type, body}
    end
  end

  defp encode_query_params(nil) do
    nil
  end

  defp encode_query_params(query_params) when is_list(query_params) or is_map(query_params) do
    Plug.Conn.Query.encode(query_params)
  end

  defp encode_new_url(url, query_params) do
    case encode_query_params(query_params) do
      nil ->
        url

      "" ->
        url

      qp ->
        uri = URI.parse(url)
        uri = %{uri | query: qp}
        URI.to_string(uri)
    end
  end

  defp encode_body(nil) do
    {:ok, {[], ""}}
  end

  defp encode_body({:csv, {csv_headers, rows}}) when is_list(rows) do
    blob =
      rows
      |> CSV.encode(headers: csv_headers)
      |> Enum.to_list()

    headers = [{"content-type", "application/csv"}]
    {:ok, {headers, blob}}
  end

  defp encode_body({:csv, rows}) when is_list(rows) do
    blob =
      rows
      |> CSV.encode()
      |> Enum.to_list()

    headers = [{"content-type", "application/csv"}]
    {:ok, {headers, blob}}
  end

  defp encode_body({:form_urlencoded, term}) when is_list(term) or is_map(term) do
    blob = encode_query_params(term)
    headers = [{"content-type", "application/x-www-form-urlencoded"}]
    {:ok, {headers, blob}}
  end

  defp encode_body({:form, items}) do
    boundary = generate_boundary()
    boundary = "------------#{boundary}"

    request_headers = [
      {"content-type", "multipart/form-data; boundary=#{boundary}"}
    ]

    blob =
      [
        Enum.map(items, fn {name, headers, blob} ->
          [
            "--",boundary,"\r\n",
            encode_item(name, headers, blob),"\r\n",
          ]
        end),
        "--",boundary, "--\r\n"
      ]

    {:ok, {request_headers, blob}}
  end

  defp encode_body({:form_stream, items}) do
    boundary = generate_boundary()
    boundary = "------------#{boundary}"

    request_headers = [
      {"content-type", "multipart/form-data; boundary=#{boundary}"}
    ]

    stream =
      Stream.resource(
        fn ->
          {:next_item, boundary, items}
        end,
        &form_data_stream/1,
        fn _ ->
          :ok
        end
      )

    {:ok, {request_headers, {:stream, stream}}}
  end

  defp encode_body({:text, term}) do
    blob = IO.iodata_to_binary(term)
    headers = [{"content-type", "text/plain"}]
    {:ok, {headers, blob}}
  end

  defp encode_body({:xml, term}) do
    blob = XmlBuilder.generate(term, format: :none)
    headers = [{"content-type", "application/xml"}]
    {:ok, {headers, blob}}
  end

  defp encode_body({:json, term}) do
    case Jason.encode(term) do
      {:ok, blob} ->
        headers = [{"content-type", "application/json"}]
        {:ok, {headers, blob}}

      {:error, _} = err ->
        err
    end
  end

  defp encode_body({:stream, stream}) do
    {:ok, {[], {:stream, stream}}}
  end

  defp encode_body(binary) when is_binary(binary) do
    {:ok, {[], binary}}
  end

  defp encode_item(name, headers, blob) when (is_atom(name) or is_binary(name)) and
                                              is_list(headers) and
                                              is_binary(blob) do
    headers = [
      {"content-disposition", "form-data; name=\"#{name}\""},
      {"content-length", to_string(byte_size(blob))}
      | headers
    ]

    [
      encode_headers(headers),
      "\r\n",
      blob,
    ]
  end

  defp form_data_stream(:end) do
    {:halt, :end}
  end

  defp form_data_stream({:next_item, boundary, []}) do
    {["--", boundary, "--\r\n"], :end}
  end

  defp form_data_stream({:next_item, boundary, [item | items]}) do
    form_data_stream({:send_item_start, boundary, item, items})
  end

  defp form_data_stream(
    {:send_item_start, boundary, {name, headers, body}, items}
  ) when is_binary(body) or is_list(body) do
    headers = Proplist.merge([
      {"content-disposition", "form-data; name=\"#{name}\""},
      {"content-length", to_string(IO.iodata_length(body))},
    ], headers)

    iolist = [
      "--",boundary,"\r\n",
      encode_headers(headers),
      "\r\n"
    ]

    {iolist, {:send_item_body, boundary, {name, headers, body}, items}}
  end

  defp form_data_stream(
    {:send_item_start, boundary, {name, headers, stream}, items}
  ) do
    headers = Proplist.merge([
      {"content-disposition", "form-data; name=\"#{name}\""},
      {"transfer-encoding", "chunked"},
    ], headers)

    iolist = [
      "--",boundary,"\r\n",
      encode_headers(headers),
      "\r\n"
    ]

    {iolist, {:send_item_body, boundary, {name, headers, stream}, items}}
  end

  defp form_data_stream(
    {:send_item_body, boundary, {_name, _headers, body}, items}
  ) when is_binary(body) do
    {[body, "\r\n"], {:next_item, boundary, items}}
  end

  defp form_data_stream(
    {:send_item_body, boundary, {_name, _headers, stream} = item, items}
  ) do
    {stream, {:end_current_item, boundary, item, items}}
  end

  defp form_data_stream(
    {:end_current_item, boundary, {_name, _headers, _stream}, items}
  ) do
    {["\r\n"], {:next_item, boundary, items}}
  end
end
