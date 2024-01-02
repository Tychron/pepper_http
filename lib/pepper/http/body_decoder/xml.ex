defmodule Pepper.HTTP.BodyDecoder.XML do
  import Pepper.HTTP.Utils

  def decode_body(body, options) do
    data = SweetXml.parse(body)
    # Parse XML
    if options[:normalize_xml] do
      {:xmldoc, handle_xml_body(data)}
    else
      {:xml, data}
    end
  end
end
