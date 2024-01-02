defmodule Pepper.HTTP.BodyEncoder.JSON do
  def encode_body(term, _options) do
    case Jason.encode(term) do
      {:ok, blob} ->
        headers = [{"content-type", "application/json"}]
        {:ok, {headers, blob}}

      {:error, _} = err ->
        err
    end
  end
end
