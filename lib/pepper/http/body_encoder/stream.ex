defmodule Pepper.HTTP.BodyEncoder.Stream do
  def encode_body(stream, _options) do
    {:ok, {[], {:stream, stream}}}
  end
end
