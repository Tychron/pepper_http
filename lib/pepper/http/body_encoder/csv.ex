defmodule Pepper.HTTP.BodyEncoder.CSV do
  def encode_body({csv_headers, rows}, _options) when is_list(rows) do
    blob =
      rows
      |> CSV.encode(headers: csv_headers)
      |> Enum.to_list()

    headers = [{"content-type", "application/csv"}]
    {:ok, {headers, blob}}
  end

  def encode_body(rows, _options) when is_list(rows) do
    blob =
      rows
      |> CSV.encode()
      |> Enum.to_list()

    headers = [{"content-type", "application/csv"}]
    {:ok, {headers, blob}}
  end
end
