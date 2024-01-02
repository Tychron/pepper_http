defmodule Pepper.HTTP.BodyEncoder.Text do
  def encode_body(term, _options) do
    blob = IO.iodata_to_binary(term)
    headers = [{"content-type", "text/plain"}]
    {:ok, {headers, blob}}
  end
end
