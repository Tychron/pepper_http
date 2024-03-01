defmodule Pepper.HTTP.ContentClient do
  alias Pepper.HTTP.Client
  alias Pepper.HTTP.Response
  alias Pepper.HTTP.BodyDecoder
  alias Pepper.HTTP.BodyDecompressor
  alias Pepper.HTTP.BodyEncoder
  alias Pepper.HTTP.ContentClient.Headers

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
                       | {:xmldoc, term()}
                       | {:xml, term()}
                       | {:text, term()}
                       | {:csv, term()}
                       | {:unk, term()}
                       | {:unaccepted, term()}
                       | {{:malformed, term()}, term()}

  @type response_error :: Pepper.HTTP.BodyError.t() | Client.response_error()

  @type response :: {:ok, Response.t(), response_body()} | {:error, response_error()}

  @no_options []

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

  def options(url, query_params \\ [], headers \\ [], options \\ []) do
    request(:options, url, query_params, headers, nil, options)
  end

  @doc """
  Perform an HTTP Request

  * `method` - the http method, either a string or atom
  * `url` - the url to send the request to
  * `query_params` - optional list or map of query paremeters
  * `headers` - a list of http headers
  * `body` - the body of the request, see `body` type for more information
  * `options` - additional options for the request
  """
  @spec request(method(), url(), query_params(), headers(), body(), options()) :: response()
  def request(method, url, query_params, headers, body, options \\ []) do
    {encoder_options, options} = Keyword.pop(options, :encoder_options, @no_options)
    case BodyEncoder.encode_body(body, encoder_options) do
      {:ok, {body_headers, blob}} ->
        case encode_new_uri(url, query_params) do
          {:ok, new_uri} ->
            all_headers = body_headers ++ Enum.map(headers, fn {key, value} ->
              {String.downcase(key), value}
            end)

            {all_headers, options} = Headers.add_additional_headers(blob, all_headers, options)

            client_options =
              Keyword.drop(options, [:normalize_xml])

            Client.request(method, new_uri, all_headers, blob, client_options)
            |> handle_response(options)

          {:error, reason} ->
            reason = %Pepper.HTTP.URIError{
              message: "the provided uri is invalid",
              url: url,
              reason: reason,
            }

            {:error, reason}
        end

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

  defp handle_response({:ok, %Response{} = response}, options) do
    with {:ok, response} <- BodyDecompressor.decompress_response(response, options) do
      {:ok, response, BodyDecoder.decode_body(response, options)}
    else
      {:error, _} = err ->
        err
    end
  end

  defp handle_response({:error, reason}, _options) do
    {:error, reason}
  end

  @spec encode_new_uri(URI.t() | String.t(), map() | Keyword.t()) :: URI.t()
  defp encode_new_uri(url, query_params) do
    case URI.new(url) do
      {:ok, %URI{} = uri} ->
        case encode_query_params(query_params) do
          nil ->
            {:ok, uri}

          "" ->
            {:ok, uri}

          qp ->
            uri = %{uri | query: qp}
            {:ok, uri}
        end

      {:error, _} = err ->
        err
    end
  end
end
