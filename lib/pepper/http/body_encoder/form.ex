defmodule Pepper.HTTP.BodyEncoder.Form do
  import Pepper.HTTP.Utils

  def encode_body(items, _options) do
    boundary = generate_boundary()
    boundary = "------------#{boundary}"

    request_headers = [
      {"content-type", "multipart/form-data; boundary=#{boundary}"}
    ]

    blob =
      [
        Enum.map(items, fn {name, headers, blob} ->
          [
            "--",boundary,"\r\n",
            encode_item(name, headers, blob),"\r\n",
          ]
        end),
        "--",boundary, "--\r\n"
      ]

    {:ok, {request_headers, blob}}
  end

  defp encode_item(name, headers, blob) when (is_atom(name) or is_binary(name)) and
                                              is_list(headers) and
                                              is_binary(blob) do
    headers = [
      {"content-disposition", "form-data; name=\"#{name}\""},
      {"content-length", to_string(byte_size(blob))}
      | headers
    ]

    [
      encode_headers(headers),
      "\r\n",
      blob,
    ]
  end
end
