defmodule Pepper.HTTP.BodyDecoder.JSON do
  def decode_body(body, _options) do
    case Jason.decode(body) do
      {:ok, doc} ->
        {:json, doc}

      {:error, _} ->
        {{:malformed, :json}, body}
    end
  end
end
