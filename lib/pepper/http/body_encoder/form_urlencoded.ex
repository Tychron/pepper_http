defmodule Pepper.HTTP.BodyEncoder.FormUrlencoded do
  import Pepper.HTTP.Utils

  def encode_body(term, _options) when is_list(term) or is_map(term) do
    blob = encode_query_params(term)
    headers = [{"content-type", "application/x-www-form-urlencoded"}]
    {:ok, {headers, blob}}
  end
end
