defmodule Pepper.HTTP.BodyEncoder.FormStream do
  alias Pepper.HTTP.Proplist

  import Pepper.HTTP.Utils

  def encode_body(items, _options) do
    boundary = generate_boundary()
    boundary = "------------#{boundary}"

    request_headers = [
      {"content-type", "multipart/form-data; boundary=#{boundary}"}
    ]

    stream =
      Stream.resource(
        fn ->
          {:next_item, boundary, items}
        end,
        &form_data_stream/1,
        fn _ ->
          :ok
        end
      )

    {:ok, {request_headers, {:stream, stream}}}
  end

  defp form_data_stream(:end) do
    {:halt, :end}
  end

  defp form_data_stream({:next_item, boundary, []}) do
    {["--", boundary, "--\r\n"], :end}
  end

  defp form_data_stream({:next_item, boundary, [item | items]}) do
    form_data_stream({:send_item_start, boundary, item, items})
  end

  defp form_data_stream(
    {:send_item_start, boundary, {name, headers, body}, items}
  ) when is_binary(body) or is_list(body) do
    headers = Proplist.merge([
      {"content-disposition", "form-data; name=\"#{name}\""},
      {"content-length", to_string(IO.iodata_length(body))},
    ], headers)

    iolist = [
      "--",boundary,"\r\n",
      encode_headers(headers),
      "\r\n"
    ]

    {iolist, {:send_item_body, boundary, {name, headers, body}, items}}
  end

  defp form_data_stream(
    {:send_item_start, boundary, {name, headers, stream}, items}
  ) do
    headers = Proplist.merge([
      {"content-disposition", "form-data; name=\"#{name}\""},
      {"transfer-encoding", "chunked"},
    ], headers)

    iolist = [
      "--",boundary,"\r\n",
      encode_headers(headers),
      "\r\n"
    ]

    {iolist, {:send_item_body, boundary, {name, headers, stream}, items}}
  end

  defp form_data_stream(
    {:send_item_body, boundary, {_name, _headers, body}, items}
  ) when is_binary(body) do
    {[body, "\r\n"], {:next_item, boundary, items}}
  end

  defp form_data_stream(
    {:send_item_body, boundary, {_name, _headers, stream} = item, items}
  ) do
    {stream, {:end_current_item, boundary, item, items}}
  end

  defp form_data_stream(
    {:end_current_item, boundary, {_name, _headers, _stream}, items}
  ) do
    {["\r\n"], {:next_item, boundary, items}}
  end
end
