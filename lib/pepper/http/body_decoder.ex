defmodule Pepper.HTTP.BodyDecoder do
  alias Pepper.HTTP.Response
  alias Pepper.HTTP.Proplist

  def decode_body(%Response{body: body} = response, options) do
    accepted_content_type = determine_accepted_content_type(response, options)

    type =
      case accepted_content_type do
        nil ->
          # no content-type
          :unk

        :unaccepted ->
          # mismatched content-type and accept, return unk(nown)
          :unaccepted

        accepted_content_type ->
          case Plug.Conn.Utils.content_type(accepted_content_type) do
            {:ok, type, subtype, _params} ->
              content_type_to_type(type, subtype)

            :error ->
              {:malformed, :content_type}
          end
      end

    decode_body_by_type(type, body, options)
  end

  defp determine_accepted_content_type(%Response{
    request: %{
      headers: req_headers,
    },
    headers: res_headers,
  }, _options) do
    # retrieve the original request accept header, this will be used to "allow" the content-type
    # to be parsed
    accept = Proplist.get(req_headers, "accept")
    # retrieve the response content-type
    content_type = Proplist.get(res_headers, "content-type")

    # ensure that we only parse content for the given accept header to avoid parsing bodies we
    # didn't want or even expect
    case accept do
      nil ->
        # no accept header was given, expect to parse anything, this is dangerous
        # but allows the default behaviour to continue
        # you should ALWAYS specify an accept header
        content_type

      "*/*" ->
        content_type

      _ ->
        if content_type do
          # a content-type was returned, try negotiate with the accept header and content-type
          case :accept_header.negotiate(accept, [content_type]) do
            :undefined ->
              # mismatch accept and content-type, refuse to parse the content and return
              # nil for the accepted_content_type
              :unaccepted

            name when is_binary(name) ->
              # return the matched content_type
              name
          end
        else
          # there was no content-type, return nil
          nil
        end
    end
  end

  decoder_content_types =
    Application.compile_env(:pepper_http, :base_decoder_content_types, [
      {{"application", "json"}, :json},
      {{"application", "vnd.api+json"}, :json},
      {{"application", "xml"}, :xml},
      {{"application", "vnd.api+xml"}, :xml},
      {{"text", "xml"}, :xml},
      {{"text", "plain"}, :text},
      {{"application", "csv"}, :csv},
      {{"text", "csv"}, :csv},
    ]) ++ Application.compile_env(:pepper_http, :decoder_content_types, [])

  Enum.each(decoder_content_types, fn {{type, subtype}, value} ->
    def content_type_to_type(unquote(type), unquote(subtype)) do
      unquote(value)
    end
  end)

  def content_type_to_type(_type, _subtype) do
    :unk
  end

  decoders =
    Application.compile_env(:pepper_http, :base_decoders, [
      csv: Pepper.HTTP.BodyDecoder.CSV,
      json: Pepper.HTTP.BodyDecoder.JSON,
      xml: Pepper.HTTP.BodyDecoder.XML,
      text: Pepper.HTTP.BodyDecoder.Text,
    ]) ++ Application.compile_env(:pepper_http, :decoders, [])

  Enum.each(decoders, fn {type, module} ->
    def decode_body_by_type(unquote(type), body, options) do
      unquote(module).decode_body(body, options)
    end
  end)

  def decode_body_by_type(:unaccepted, body, _options) do
    {:unaccepted, body}
  end

  def decode_body_by_type(:unk, body, _options) do
    {:unk, body}
  end

  def decode_body_by_type({:malformed, _} = res, body, _options) do
    {res, body}
  end
end
