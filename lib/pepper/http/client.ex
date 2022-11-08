defmodule Pepper.HTTP.Client do
  @moduledoc """
  HTTP Client implemented using Mint.

  This is a simple base client and doesn't handle any special content-types on request or response.

  Use the Pepper.HTTP.ContentClient instead if you need content-type handling.
  """
  require Logger

  alias Pepper.HTTP.Request
  alias Pepper.HTTP.Response
  alias Pepper.HTTP.ConnectionManager

  import Pepper.HTTP.Utils

  @type method :: String.t() | :head | :get | :post | :put | :patch | :delete | :options

  @typedoc """
  By default ALL http requests are one-off requests, meaning the connection is opened and closed
  in a single session.

  It works well for infrequent requests.
  """
  @type connection_manager :: :one_off | :pooled | module()

  @type transport_option :: {:verify, :verify_peer | :verify_none}

  @type connect_option :: {:transport_opts, [transport_option()]}

  @typedoc """
  All the options supported by the request function.
  """
  @type request_option :: {:connect_timeout, timeout()}
                        | {:recv_timeout, timeout()}
                        | {:recv_size, non_neg_integer()}
                        | {:mode, :active | :passive}
                        | {:connection_manager, connection_manager()}
                        | {:connection_manager_id, term()}
                        | {:attempts, non_neg_integer()}
                        | {:connect_options, [connect_option()]}

  @type path :: String.t()

  @type headers :: [{String.t(), String.t()}]

  @spec request(method(), path(), headers(), iodata(), [request_option()]) ::
          {:ok, Response.t()}
          | {:error, reason::term()}
  def request(method, url, headers, body, options \\ []) when is_binary(url) and is_list(options) do
    options = Keyword.put_new(options, :attempts, 1)

    case URI.parse(url) do
      %{scheme: scheme, host: host} = uri when is_binary(host) ->
        request =
          %Request{
            method: method,
            url: url,
            uri: uri,
            body: body,
            headers: headers,
            options: options,
          }

        case scheme do
          "http" ->
            do_request(%{request | scheme: :http})

          "https" ->
            do_request(%{request | scheme: :https})

          scheme ->
            {:error, {:unexpected_scheme, scheme}}
        end
    end
  end

  defp do_request(request) do
    options =
      request.options
      |> Keyword.put_new(:connect_timeout, 30_000) # 30 seconds
      |> Keyword.put_new(:recv_timeout, 30_000) # 30 seconds
      |> Keyword.put_new(:recv_size, 8 * 1024 * 1024) # 8 megabytes
      |> Keyword.put_new(:mode, :passive) # passive will pull bytes off, safer for inline process
      |> validate_options!()

    request = %{request | options: options}

    connection_manager = Keyword.get(request.options, :connection_manager, :one_off)
    connection_manager_id = Keyword.get(request.options, :connection_manager_id, :default)

    method = normalize_http_method(request.method)
    headers = normalize_headers(request.headers)

    path = request.uri.path || "/"

    path =
      case request.uri.query do
        nil ->
          path

        "" ->
          path

        query_params ->
          path <> "?" <> query_params
      end

    request =
      %{
        request
        | method: method,
          headers: headers,
          path: path,
      }

    connection_manager_module =
      case connection_manager do
        :one_off ->
          ConnectionManager.OneOff

        :pooled ->
          ConnectionManager.Pooled

        other ->
          other
      end

    do_connection_request(connection_manager_module, connection_manager_id, request)
  end

  defp do_connection_request(connection_manager_module, connection_manager_id, request) do
    case connection_manager_module.request(connection_manager_id, request) do
      {:ok, _} = resp ->
        resp

      {:error, _} = err ->
        attempts = request.options[:attempts] -1

        if attempts > 0 do
          Process.sleep 100
          request = put_in(request.options[:attempts], attempts)
          do_connection_request(connection_manager_module, connection_manager_id, request)
        else
          err
        end
    end
  end

  defp validate_options!(options, acc \\ [])

  defp validate_options!([], acc) do
    Enum.reverse(acc)
  end

  defp validate_options!(
    [{key, _} = pair | rest], acc
  ) when key in [:attempts, :mode, :connection_manager, :connection_manager_id, :recv_size, :recv_timeout, :connect_timeout, :connect_options] do
    validate_options!(rest, [pair | acc])
  end

  defp validate_options!([{key, _} = pair | rest], acc) do
    Logger.warning "unexpected option key=#{inspect key}"
    validate_options!(rest, [pair | acc])
  end
end
