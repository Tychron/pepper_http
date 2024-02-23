defmodule Pepper.HTTP.BodyDecoder.XML do
  import Pepper.HTTP.Utils

  def decode_body(body, options) do
    # Parse XML
    {:ok, doc} = Saxy.SimpleForm.parse_string(body)
    if options[:normalize_xml] do
      {:xmldoc, handle_xml_body(doc)}
    else
      {:xml, doc}
    end
  end
end
