defmodule Pepper.HTTP.BodyDecoder.CSV do
  def decode_body(body, _options) do
    {:csv, body}
  end
end
