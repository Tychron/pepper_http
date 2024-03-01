defmodule Pepper.HTTP.ConnectionManager.Utils do
  alias Pepper.HTTP.Response
  alias Pepper.HTTP.Request

  import Pepper.HTTP.Utils

  @spec timespan(function()) :: {{tstart::integer(), tend::integer()}, result::any()}
  def timespan(callback) do
    tstart = :erlang.monotonic_time(:microsecond)
    result = callback.()
    tend = :erlang.monotonic_time(:microsecond)
    {{tstart, tend}, result}
  end

  def read_responses(mode, conn, ref, response, %Request{} = request, []) do
    case read_response(mode, conn, ref, request) do
      {:ok, conn, http_responses} ->
        read_responses(mode, conn, ref, response, request, http_responses)

      {:error, conn, reason} ->
        {:error, conn, reason, []}

      {:error, _conn, _reason, _responses} = err ->
        err
    end
  end

  def read_responses(
    mode,
    conn,
    ref,
    %Response{} = response,
    %Request{} = request,
    [http_response | http_responses]
  ) do
    case handle_response(conn, ref, response, request, http_response) do
      {:next, response} ->
        read_responses(mode, conn, ref, response, request, http_responses)

      {:done, response} ->
        {:ok, conn, response}

      {:error, conn, reason} ->
        {:error, conn, reason, http_responses}
    end
  end

  @spec read_response(:passive | :active, Mint.Conn.t(), reference(), Pepper.HTTP.Request.t()) ::
    {:ok, Mint.Conn.t(), [any()]}
    | {:error, Mint.Conn.t(), reasonn::any(), responses::list()}
  def read_response(:passive, conn, _ref, %Request{} = request) do
    recv_timeout = Keyword.fetch!(request.options, :recv_timeout)
    case Mint.HTTP.recv(conn, 0, recv_timeout) do
      {:ok, _conn, _responses} = res ->
        res

      {:error, conn, reason} ->
        {:error, conn, reason, []}

      {:error, _conn, _reason, _responses} = err ->
        err
    end
  end

  def read_response(:active, conn, _ref, %Request{} = request) do
    recv_timeout = Keyword.fetch!(request.options, :recv_timeout)
    receive do
      message ->
        case Mint.HTTP.stream(conn, message) do
          {:ok, _conn, _responses} = res ->
            res

          {:error, _conn, _reason} = err ->
            err
        end
    after recv_timeout ->
      {:error, conn, :timeout}
    end
  end

  def handle_response(
    conn,
    ref,
    %Response{} = response,
    %Request{} = request,
    http_response
  ) do
    case http_response do
      {:status, ^ref, status_code} ->
        {:next, %{response | status_code: status_code}}

      {:headers, ^ref, headers} ->
        {:next, %{response | headers: normalize_headers(headers)}}

      {:data, ^ref, data} ->
        try do
          handle_data_response(conn, ref, response, request, data)
        rescue ex ->
          response.body_handler.cancel(response)
          reraise ex, __STACKTRACE__
        end

      {:done, ^ref} ->
        case response.body_handler.finalize(response) do
          {:ok, response} ->
            {:done, %{response | request: request}}
        end
    end
  end

  defp handle_data_response(conn, _ref, %Response{} = response, %Request{} = request, data) do
    response =
      case response.body_state do
        :none ->
          case response.body_handler.init(request, response) do
            {:ok, response} ->
              %{response | body_state: :initialized}

            {:error, _} = err ->
              throw err
          end

        _other ->
          response
      end

    segment_size = byte_size(data)
    next_recv_size = response.recv_size + segment_size

    size_exceeded? =
      case request.recv_size do
        :infinity ->
          false

        recv_size when is_integer(recv_size) ->
          next_recv_size > recv_size
      end

    if size_exceeded? do
      case response.body_handler.cancel(response) do
        {:ok, _response} ->
          throw {:error, :recv_size_exceeded}
      end
    else
      case response.body_handler.handle_data(segment_size, data, response) do
        {:ok, response} ->
          response = %{response | recv_size: next_recv_size}
          {:next, response}

        {:error, _reason} = err ->
          throw err
      end
    end
  catch {:error, reason} ->
    {:error, conn, {:handle_data_error, reason}}
  end

  def maybe_stream_request_body(mode, conn, ref, %Request{} = request, is_stream?, responses) do
    if is_stream? do
      stream_request_body(mode, conn, ref, request, responses)
    else
      {:ok, conn, responses}
    end
  end

  defp stream_request_body(mode, conn, ref, %Request{} = request, responses) do
    {:stream, stream} = request.body

    protocol = Mint.HTTP.protocol(conn)
    result =
      stream
      |> Enum.reduce_while(
        {:ok, conn, responses},
        &do_stream_request_body(mode, protocol, &1, &2, ref, request)
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

  defp do_stream_request_body(_mode, :http1, blob, {:ok, conn, responses}, ref, _request) do
    case Mint.HTTP.stream_request_body(conn, ref, blob) do
      {:ok, conn} ->
        {:cont, {:ok, conn, responses}}

      {:error, _conn, _reason} = err ->
        {:halt, err}
    end
  end

  defp do_stream_request_body(_mode, :http2, <<>>, {:ok, _conn, _responses} = res, _ref, _request) do
    {:cont, res}
  end

  defp do_stream_request_body(mode, :http2, blob, {:ok, conn, responses}, ref, request) do
    conn_window_size = Mint.HTTP2.get_window_size(conn, :connection)
    window_size = Mint.HTTP2.get_window_size(conn, {:request, ref})

    if conn_window_size <= 0 or window_size <= 0 do
      case read_response(mode, conn, ref, request) do
        {:ok, conn, []} ->
          do_stream_request_body(mode, :http2, blob, {:ok, conn, responses}, ref, request)

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
          do_stream_request_body(mode, :http2, rest, {:ok, conn, responses}, ref, request)

        {:error, _conn, _reason} = err ->
          {:halt, err}
      end
    end
  end

  def determine_if_body_should_stream(conn, request) do
    case request.body do
      nil ->
        {request, false, ""}

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
