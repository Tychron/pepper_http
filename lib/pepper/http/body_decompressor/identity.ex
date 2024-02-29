defmodule Pepper.HTTP.BodyDecompressor.Identity do
  alias Pepper.HTTP.Response

  def decompress_response(%Response{} = response, _options) do
    {:ok, response}
  end
end
