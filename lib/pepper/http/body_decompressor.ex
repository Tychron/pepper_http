defmodule Pepper.HTTP.BodyDecompressor do
  alias Pepper.HTTP.Response
  alias Pepper.HTTP.Proplist

  def decompress_response(%Response{} = response, options) do
    accepted_content_encoding = determine_accepted_content_encoding(response, options)

    encoding =
      case accepted_content_encoding do
        nil ->
          # no content-encoding, assume identity
          :identity

        value ->
          content_encoding_to_encoding(value)
      end


    decode_body_by_encoding(encoding, response, options)
  end

  defp determine_accepted_content_encoding(%Response{
    request: %{
      headers: req_headers,
    },
    headers: res_headers,
  }, _options) do
    accept_encodings = case Proplist.get(req_headers, "accept-encoding") do
      nil ->
        :any

      value ->
        Enum.map(:accept_encoding_header.parse(value), fn {:content_coding, name, _, _} ->
          to_string(name)
        end)
    end

    content_encoding =
      case Proplist.get(res_headers, "content-encoding") do
        nil ->
          "identity"

        value ->
          [{:content_coding, name, _, _}] = :accept_encoding_header.parse(value)
          to_string(name)
      end

    # ensure that we only parse content for the given accept-encoding header to avoid parsing bodies we
    # didn't want or even expect
    if accept_encodings == :any or content_encoding in accept_encodings or "*" in accept_encodings do
      content_encoding
    else
      {:unaccepted, content_encoding}
    end
  end

  decoder_content_types =
    Application.compile_env(:pepper_http, :base_decompressor_types, [
      {"identity", :identity},
      {"deflate", :deflate},
      {"gzip", :gzip},
    ]) ++ Application.compile_env(:pepper_http, :decompressor_types, [])

  Enum.each(decoder_content_types, fn {encoding, value} ->
    def content_encoding_to_encoding(unquote(encoding)) do
      unquote(value)
    end
  end)

  def content_encoding_to_encoding({_, _} = res) do
    res
  end

  def content_encoding_to_encoding(encoding) when is_binary(encoding) do
    {:unk, encoding}
  end

  decoders =
    Application.compile_env(:pepper_http, :base_decompressors, [
      identity: Pepper.HTTP.BodyDecompressor.Identity,
      deflate: Pepper.HTTP.BodyDecompressor.Deflate,
      gzip: Pepper.HTTP.BodyDecompressor.GZip,
    ]) ++ Application.compile_env(:pepper_http, :decompressors, [])

  Enum.each(decoders, fn {type, module} ->
    def decode_body_by_encoding(unquote(type), %Response{} = response, options) do
      unquote(module).decompress_response(response, options)
    end
  end)

  def decode_body_by_encoding({:unaccepted, content_encoding}, response, _options) do
    {:error, {:unaccepted_content_encoding, content_encoding, response}}
  end

  def decode_body_by_encoding({:unk, content_encoding}, response, _options) do
    {:error, {:unknown_content_encoding, content_encoding, response}}
  end

  def decode_body_by_encoding(encoding, response, _options) do
    {:error, {:unhandled_content_encoding, encoding, response}}
  end
end
