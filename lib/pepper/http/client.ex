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

  @type method :: Pepper.HTTP.Utils.http_method()

  @typedoc """
  By default ALL http requests are one-off requests, meaning the connection is opened and closed
  in a single session.

  It works well for infrequent requests but is not suited for large quantities of request.
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
                        | {:connection_manager, connection_manager()}
                        | {:connection_manager_id, term()}
                        | {:response_body_handler, module()}
                        | {:response_body_handler_options, any()}
                        | {:attempts, non_neg_integer()}
                        | {:connect_options, [connect_option()]}

  @type uri_or_url :: URI.t() | String.t()

  @type headers :: [{String.t(), String.t()}]

  @type response_error :: Pepper.HTTP.URIError.t() | term()

  @spec request(method(), uri_or_url(), headers(), iodata(), [request_option()]) ::
          {:ok, Response.t()}
          | {:error, response_error()}
  def request(method, url, headers, body, options \\ []) when is_list(options) do
    method = normalize_http_method(method)
    headers = normalize_headers(headers)

    options = Keyword.put_new(options, :attempts, 1)

    case URI.new(url) do
      {:ok, %URI{scheme: scheme, host: host} = uri} when is_binary(host) ->
        request =
          %Request{
            method: method,
            url: URI.to_string(uri),
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

          _scheme ->
            error =
              %Pepper.HTTP.URIError{
                message: "the provided uri has an invalid scheme, try http or https",
                uri: uri,
                reason: :unexpected_scheme,
              }

            {:error, error}
        end

      {:ok, %URI{host: nil} = uri} ->
        error =
          %Pepper.HTTP.URIError{
            message: "the provided uri is invalid",
            url: url,
            uri: uri,
            reason: :bad_uri,
          }

        {:error, error}

      {:error, reason} ->
        error =
          %Pepper.HTTP.URIError{
            message: "the provided uri is invalid",
            url: url,
            reason: reason,
          }

        {:error, error}
    end
  end

  defp do_request(%Request{} = request) do
    options =
      request.options
      |> Keyword.put_new(:connect_timeout, 30_000) # 30 seconds
      |> Keyword.put_new(:recv_timeout, 30_000) # 30 seconds
      |> Keyword.put_new(:recv_size, 8 * 1024 * 1024) # 8 megabytes
      |> Keyword.put_new(:response_body_handler, Pepper.HTTP.ResponseBodyHandler.Default)
      |> Keyword.put_new(:response_body_handler_options, [])
      |> Keyword.put_new(:connection_manager, :one_off)
      |> Keyword.put_new(:connection_manager_id, :default)
      |> validate_options!()

    recv_size = Keyword.fetch!(options, :recv_size)
    response_body_handler = Keyword.fetch!(options, :response_body_handler)
    response_body_handler_options = Keyword.fetch!(options, :response_body_handler_options)
    connection_manager = Keyword.fetch!(options, :connection_manager)
    connection_manager_id = Keyword.fetch!(options, :connection_manager_id)

    request = %{request | options: options}

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
      %Request{
        request
        | path: path,
          recv_size: recv_size,
          response_body_handler: response_body_handler,
          response_body_handler_options: response_body_handler_options,
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

  @allowed_keys [
    :response_body_handler,
    :response_body_handler_options,
    :attempts,
    :connection_manager,
    :connection_manager_id,
    :recv_size,
    :recv_timeout,
    :connect_timeout,
    :connect_options
  ]

  defp validate_options!(
    [{key, _} = pair | rest], acc
  ) when key in @allowed_keys do
    validate_options!(rest, [pair | acc])
  end

  defp validate_options!([{key, _} = pair | rest], acc) do
    Logger.warning "unexpected option key=#{inspect key}"
    validate_options!(rest, [pair | acc])
  end
end
