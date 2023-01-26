defmodule Pepper.HTTP.ConnectionManager.Utils do
  import Pepper.HTTP.Utils

  @spec read_response(:passive | :active, Mint.Conn.t(), reference(), Pepper.HTTP.Request.t()) ::
    {:ok, Mint.Conn.t(), [any()]}
    | {:error, Mint.Conn.t(), reasonn::any(), responses::list()}
  def read_response(:passive, conn, _ref, request) do
    case Mint.HTTP.recv(conn, 0, request.options[:recv_timeout]) do
      {:ok, _conn, _responses} = res ->
        res

      {:error, conn, reason} ->
        {:error, conn, reason, []}

      {:error, conn, reason, responses} ->
        {:error, conn, reason, responses}
    end
  end

  def read_response(:active, conn, _ref, request) do
    receive do
      message ->
        case Mint.HTTP.stream(conn, message) do
          {:ok, _conn, _responses} = res ->
            res

          {:error, _conn, _reason} = err ->
            err
        end
    after
      request.options[:recv_timeout] ->
        {:error, conn, :timeout}
    end
  end

  def read_responses(:passive, conn, ref, response, request, []) do
    case read_response(:passive, conn, ref, request) do
      {:ok, conn, responses} ->
        read_responses(:passive, conn, ref, response, request, responses)

      {:error, conn, reason} ->
        {:error, conn, reason}

      {:error, conn, reason, responses} ->
        {:error, conn, reason, responses}
    end
  end

  def read_responses(:passive, conn, ref, response, request, [row | rest]) do
    case handle_response(:passive, conn, ref, response, request, row) do
      {:next, response} ->
        read_responses(:passive, conn, ref, response, request, rest)

      {:done, response} ->
        {:ok, conn, response}
    end
  end

  def read_responses(:active, conn, ref, response, request, []) do
    case read_response(:active, conn, ref, request) do
      {:ok, conn, responses} ->
        read_responses(:active, conn, ref, response, request, responses)

      {:done, response} ->
        {:ok, conn, response}
    end
  end

  def read_responses(:active, conn, ref, response, request, [_row | rest] = rows) do
    case handle_responses(:active, conn, ref, response, request, rows) do
      {:next, response} ->
        read_responses(:active, conn, ref, response, request, rest)

      {:done, response} ->
        {:ok, conn, response}
    end
  end

  def handle_responses(mode, conn, ref, response, request, [row | rest]) do
    case handle_response(mode, conn, ref, response, request, row) do
      {:next, response} ->
        handle_responses(mode, conn, ref, response, request, rest)

      {:done, response} ->
        {:done, response}
    end
  end

  def handle_response(_mode, _conn, ref, response, request, row) do
    case row do
      {:status, ^ref, status_code} ->
        {:next, %{response | status_code: status_code}}

      {:headers, ^ref, headers} ->
        {:next, %{response | headers: normalize_headers(headers)}}

      {:data, ^ref, data} ->
        {:next, %{response | data: [data | response.data]}}

      {:done, ^ref} ->
        result_body =
          response.data
          |> Enum.reverse()
          |> IO.iodata_to_binary()

        response =
          %{
            response
            | data: [],
              body: result_body,
              request: request
          }

        {:done, response}
    end
  end

  def maybe_stream_body(conn, ref, request, is_stream?, responses) do
    if is_stream? do
      send_body_stream(conn, ref, request, responses)
    else
      {:ok, conn, responses}
    end
  end

  defp send_body_stream(conn, ref, request, responses) do
    {:stream, stream} = request.body

    protocol = Mint.HTTP.protocol(conn)
    result =
      stream
      |> Enum.reduce_while(
        {:ok, conn, responses},
        &stream_request_body(protocol, &1, &2, ref, request)
      )

    case result do
      {:ok, conn, responses} ->
        case Mint.HTTP.stream_request_body(conn, ref, :eof) do
          {:ok, conn} ->
            {:ok, conn, responses}

          {:error, _conn, _reason} = err ->
            err
        end

      {:unexpected_responses, conn, responses} ->
        {:ok, conn, responses}

      {:error, _conn, _reason} = err ->
        err
    end
  end

  defp stream_request_body(:http1, blob, {:ok, conn, responses}, ref, _request) do
    case Mint.HTTP.stream_request_body(conn, ref, blob) do
      {:ok, conn} ->
        {:cont, {:ok, conn, responses}}

      {:error, _conn, _reason} = err ->
        {:halt, err}
    end
  end

  defp stream_request_body(:http2, <<>>, {:ok, _conn, _responses} = res, _ref, _request) do
    {:cont, res}
  end

  defp stream_request_body(:http2, blob, {:ok, conn, responses}, ref, request) do
    conn_window_size = Mint.HTTP2.get_window_size(conn, :connection)
    window_size = Mint.HTTP2.get_window_size(conn, {:request, ref})

    if conn_window_size <= 0 or window_size <= 0 do
      case read_response(request.options[:mode], conn, ref, request) do
        {:ok, conn, []} ->
          stream_request_body(:http2, blob, {:ok, conn, responses}, ref, request)

        {:ok, conn, next_responses} ->
          {:halt, {:unexpected_responses, conn, responses ++ next_responses}}

        {:error, _conn, _reason} = err ->
          {:halt, err}
      end
    else
      blob = IO.iodata_to_binary(blob)
      min_window_size = min(conn_window_size, window_size)

      {next_blob, rest} =
        case blob do
          <<next_blob::binary-size(min_window_size), rest::binary>> ->
            {next_blob, rest}

          <<next_blob::binary>> ->
            {next_blob, <<>>}
        end

      case Mint.HTTP.stream_request_body(conn, ref, next_blob) do
        {:ok, conn} ->
          stream_request_body(:http2, rest, {:ok, conn, responses}, ref, request)

        {:error, _conn, _reason} = err ->
          {:halt, err}
      end
    end
  end

  def determine_if_body_should_stream(conn, request) do
    case request.body do
      {:stream, _stream} ->
        {request, true, :stream}

      iodata when is_list(iodata) ->
        maybe_setup_stream_body(conn, request, IO.iodata_to_binary(iodata))

      blob when is_binary(blob) ->
        maybe_setup_stream_body(conn, request, blob)
    end
  end

  defp maybe_setup_stream_body(conn, request, blob) do
    case Mint.HTTP.protocol(conn) do
      :http1 ->
        {request, false, blob}

      :http2 ->
        window_size = Mint.HTTP2.get_window_size(conn, :connection)

        if byte_size(blob) >= window_size and window_size > 0 do
          stream = stream_binary_chunks(blob, window_size)
          {%{request | body: {:stream, stream}}, true, :stream}
        else
          {request, false, blob}
        end
    end
  end
end
