defmodule Pepper.HTTP.BodyEncoder.XML do
  def encode_body(term, _options) do
    blob = XmlBuilder.generate(term, format: :none)
    headers = [{"content-type", "application/xml"}]
    {:ok, {headers, blob}}
  end
end
