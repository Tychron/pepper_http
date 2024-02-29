defmodule Pepper.HTTP.BodyDecompressor.Deflate do
  alias Pepper.HTTP.Response

  def decompress_response(%Response{} = response, _options) do
    stream = :zlib.open()
    try do
      :ok = :zlib.inflateInit(stream)
      blob = :zlib.inflate(stream, response.body)
      :ok = :zlib.inflateEnd(stream)
      {:ok, %{response | original_body: response.body, body: IO.iodata_to_binary(blob)}}
    after
      :zlib.close(stream)
    end
  end
end
