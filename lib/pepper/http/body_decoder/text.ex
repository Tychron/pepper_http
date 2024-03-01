defmodule Pepper.HTTP.BodyDecoder.Text do
  def decode_body(body, _options) do
    {:text, body}
  end
end
