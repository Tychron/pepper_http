defmodule Pepper.HTTP.ConnectionManager.OneOff do
  @moduledoc """
  ConnectionManager for one off requests, which is the default.
  """
  alias Pepper.HTTP.Request
  alias Pepper.HTTP.Response
  alias Pepper.HTTP.ConnectError
  alias Pepper.HTTP.SendError
  alias Pepper.HTTP.RequestError
  alias Pepper.HTTP.ReceiveError

  import Pepper.HTTP.ConnectionManager.Utils

  @type error_reasons :: ReceiveError.t()
                       | RequestError.t()
                       | SendError.t()
                       | ConnectError.t()

  @spec request(term(), Request.t()) :: {:ok, Response.t()} | {:error, error_reasons()}
  def request(_id, %Request{} = request) do
    mode = request.options[:mode]
    connect_options =
      Keyword.merge(
        [
          mode: mode,
          transport_opts: [
            timeout: request.options[:connect_timeout],
          ],
        ],
        Keyword.get(request.options, :connect_options, [])
      )

    case Mint.HTTP.connect(request.scheme, request.uri.host, request.uri.port, connect_options) do
      {:ok, conn} ->
        {request, is_stream?, body} =
          determine_if_body_should_stream(conn, request)

        case Mint.HTTP.request(conn, request.method, request.path, request.headers, body) do
          {:ok, conn, ref} ->
            response = %Response{
              protocol: Mint.HTTP.protocol(conn),
              body_handler: request.response_body_handler,
              body_handler_options: request.response_body_handler_options,
            }
            result = maybe_stream_request_body(conn, ref, request, is_stream?, [])

            case result do
              {:ok, conn, responses} ->
                case read_responses(mode, conn, ref, response, request, responses) do
                  {:ok, conn, response} ->
                    Mint.HTTP.close(conn)
                    {:ok, response}

                  {:error, conn, reason} ->
                    Mint.HTTP.close(conn)
                    handle_receive_error(conn, reason, request)

                  {:error, conn, reason, _} ->
                    Mint.HTTP.close(conn)
                    handle_receive_error(conn, reason, request)
                end

              {:error, conn, reason} ->
                Mint.HTTP.close(conn)
                handle_send_error(conn, reason, request)
            end

          {:error, conn, reason} ->
            Mint.HTTP.close(conn)
            handle_request_error(conn, reason, request)
        end

      {:error, reason} ->
        handle_connect_error(reason, request)
    end
  end

  defp handle_receive_error(_conn, reason, request) do
    ex = %ReceiveError{
      message: "Error occured while receiving data from remote",
      reason: reason,
      request: request,
    }
    {:error, ex}
  end

  defp handle_send_error(_conn, reason, request) do
    ex = %SendError{
      message: "Error occured while sending data to remote",
      reason: reason,
      request: request,
    }
    {:error, ex}
  end

  defp handle_request_error(_conn, reason, request) do
    ex = %RequestError{
      message: "Error occured while sending request to remote",
      reason: reason,
      request: request,
    }
    {:error, ex}
  end

  defp handle_connect_error(reason, request) do
    ex = %ConnectError{
      message: "could not connect",
      request: request,
      reason: reason,
    }
    {:error, ex}
  end
end
