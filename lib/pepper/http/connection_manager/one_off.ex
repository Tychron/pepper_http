defmodule Pepper.HTTP.ConnectionManager.OneOff do
  @moduledoc """
  ConnectionManager for one off requests, which is the default.
  """
  alias Pepper.HTTP.Request
  alias Pepper.HTTP.Response
  alias Pepper.HTTP.ConnectError

  import Pepper.HTTP.ConnectionManager.Utils

  @spec request(term(), Request.t()) :: {:ok, Response.t()} | {:error, term()}
  def request(_id, %Request{} = request) do
    connect_options = Keyword.merge(
      [
        {:timeout, request.options[:connect_timeout]},
        {:mode, request.options[:mode]}
      ],
      Keyword.get(request.options, :connect_options, [])
    )

    case Mint.HTTP.connect(request.scheme, request.uri.host, request.uri.port, connect_options) do
      {:ok, conn} ->
        {request, is_stream?, body} =
          determine_if_body_should_stream(conn, request)

        case Mint.HTTP.request(conn, request.method, request.path, request.headers, body) do
          {:ok, conn, ref} ->
            response = %Response{protocol: Mint.HTTP.protocol(conn)}
            result = maybe_stream_body(conn, ref, request, is_stream?, [])

            case result do
              {:ok, conn, responses} ->
                case read_responses(request.options[:mode], conn, ref, response, request, responses) do
                  {:ok, conn, response} ->
                    Mint.HTTP.close(conn)
                    {:ok, response}

                  {:error, conn, reason} ->
                    Mint.HTTP.close(conn)
                    {:error, {:recv_error, reason}}
                end

              {:error, conn, reason} ->
                Mint.HTTP.close(conn)
                {:error, {:send_error, reason}}
            end

          {:error, conn, reason} ->
            Mint.HTTP.close(conn)
            {:error, {:request_error, reason}}
        end

      {:error, reason} ->
        {:error, %ConnectError{message: "could not connect", request: request, reason: reason}}
    end
  end
end
