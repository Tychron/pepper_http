defmodule Pepper.HTTP.Support.PlugPipelineHelpers do
  defmodule QueryParamsPipeline do
    @moduledoc false
    use Plug.Builder

    plug Plug.Parsers, parsers: [:urlencoded],
                       pass: ["*/*"]
  end

  defmodule JSONPipeline do
    @moduledoc false
    use Plug.Builder

    plug Plug.Parsers, parsers: [:json],
                       pass: ["application/json", "application/vnd.api+json"],
                       json_decoder: Jason
  end

  defmodule XMLPipeline do
    @moduledoc false
    use Plug.Builder

    plug Plug.Parsers, parsers: [],
                       pass: ["application/xml", "text/xml"]

    plug :parse_xml

    def parse_xml(conn, _) do
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      try do
        doc = Saxy.SimpleForm.parse_string(body)
        put_in(conn.params["_xml"], doc)
      rescue ex ->
        raise Plug.Parsers.ParseError, exception: ex
      catch :exit, msg ->
        case msg do
          {:fatal, {reason, _file_location, {:line, _line}, {:col, _col}}} ->
            raise Plug.Parsers.ParseError, message: "parse error #{inspect reason}"
        end
      end
    end
  end

  defmodule MultipartPipeline do
    @moduledoc false
    use Plug.Builder

    import Pepper.HTTP.Utils

    plug Plug.Parsers, parsers: [],
                       pass: ["multipart/*"]

    plug :parse_multipart

    def parse_multipart(conn, _) do
      [content_type] = get_req_header(conn, "content-type")
      {:ok, _type, _subtype, attrs} = Plug.Conn.Utils.content_type(content_type)

      {:ok, body, conn} = Plug.Conn.read_body(conn)
      parts = parse(body, Map.fetch!(attrs, "boundary"))

      put_in(conn.params["_multipart"], parts)
    end

    defp parse(body, boundary) when is_binary(body) and is_binary(boundary) do
      body
      |> blob_to_multipart_messages(boundary)
    end
  end

  defmodule RFC822Pipeline do
    @moduledoc false
    use Plug.Builder

    plug Plug.Parsers, parsers: [],
                       pass: ["message/*"]

    plug :parse_rfc822

    def parse_rfc822(conn, _) do
      {:ok, doc, conn} = Plug.Conn.read_body(conn)

      put_in(conn.params["_rfc822"], doc)
    end
  end

  @moduledoc false

  import Plug.Conn

  @doc """
  Handles a urlencoded request
  """
  @spec handle_urlencoded_request(Plug.Conn.t()) :: {:ok, map(), Plug.Conn.t()}
  def handle_urlencoded_request(conn) do
    conn = QueryParamsPipeline.call(conn, [])
    {:ok, conn.params, conn}
  end

  @doc """
  Handles a JSON request
  """
  @spec handle_json_request(Plug.Conn.t()) :: {:ok, map(), Plug.Conn.t()}
  def handle_json_request(conn) do
    conn = JSONPipeline.call(conn, [])
    {:ok, conn.params, conn}
  end

  @doc """
  Handles an XML Request
  """
  @spec handle_xml_request(Plug.Conn.t()) :: {:ok, map(), Plug.Conn.t()}
  def handle_xml_request(conn) do
    conn = XMLPipeline.call(conn, [])

    {:ok, conn.params["_xml"], conn}
  end

  @doc """
  Handles a multipart request
  """
  @spec handle_multipart_request(Plug.Conn.t()) :: {:ok, map(), Plug.Conn.t()}
  def handle_multipart_request(conn) do
    conn = MultipartPipeline.call(conn, [])
    {:ok, conn.params["_multipart"], conn}
  end

  @doc """
  Handles a RFC822 request, that is a email-formatted payload
  """
  @spec handle_rfc822_request(Plug.Conn.t()) :: {:ok, map(), Plug.Conn.t()}
  def handle_rfc822_request(conn) do
    conn = RFC822Pipeline.call(conn, [])

    {:ok, conn.params["_rfc822"], conn}
  end

  @doc """
  Reads the Authorization request header from the given Plug.Conn

  If no Authorization was set, then :none is returned, otherwise:
  * {:basic, {username, password}} for Basic
  * {:bearer, token} for Bearer
  and {:error, term} for everything else or when the authorization was incorrectly formatted
  """
  @spec read_request_auth(Plug.Conn.t()) ::
          :none
          | {:basic, {String.t(), String.t()}}
          | {:bearer, String.t()}
          | {:error, term()}
  def read_request_auth(conn) do
    case get_req_header(conn, "authorization") do
      [] ->
        :none

      [header | _] ->
        case Regex.scan(~r/\ABasic\s+(\S+)\z/i, header) do
          [[_all, digest64]] ->
            case Base.decode64(digest64) do
              {:ok, digest} ->
                [username, password] = String.split(digest, ":", parts: 2)
                {:basic, {username, password}}

              :error ->
                {:error, {:bad_basic_auth, header}}
            end

          [] ->
            case Regex.scan(~r/\ABearer\s+(.+)\z/i, header) do
              [[_all, token]] ->
                {:bearer, token}

              [] ->
                {:error, {:bad_authorization, header}}
            end
        end
    end
  end
end
