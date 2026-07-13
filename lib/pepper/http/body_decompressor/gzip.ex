defmodule Pepper.HTTP.BodyDecompressor.GZip do
  alias Pepper.HTTP.Response

  def decompress_response(%Response{} = response, _options) do
    blob = :zlib.gunzip(response.body)
    {:ok, %{response | original_body: response.body, body: blob}}
  end
end
