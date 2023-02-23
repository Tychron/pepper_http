defmodule Pepper.HTTP.ResponseError do
  defexception [
    :req_scheme,
    :req_method,
    :req_url,
    :req_query_params,
    :req_headers,
    #
    :res_headers,
    :res_status_code,
    :res_body,
  ]

  def message(%__MODULE__{} = err) do
    IO.iodata_to_binary [
      """
      #{__MODULE__}

      Request:
        scheme: #{err.req_scheme}
        method: #{err.req_method}
        url: #{err.req_url}
        query_params: #{inspect err.req_query_params}
        headers:
      """,
      Enum.map(err.req_headers || [], fn {key, value} ->
        ["    ", to_string(key), ": ", to_string(value), "\n"]
      end),
      "\n",
      """
      Response:
        status: #{err.res_status_code}
        headers: #{err.res_status_code}
      """,
      Enum.map(err.res_headers || [], fn {key, value} ->
        ["    ", to_string(key), ": ", to_string(value), "\n"]
      end),
      "\n",
      """
        body:
          #{inspect err.res_body}
      """
    ]
  end

  def from_response(%Pepper.HTTP.Response{} = resp) do
    req = resp.request

    %Pepper.HTTP.ResponseError{
      req_scheme: req.scheme,
      req_method: req.method,
      req_url: req.url,
      req_query_params: req.query_params,
      req_headers: req.headers,

      res_headers: resp.headers,
      res_status_code: resp.status_code,
      res_body: resp.body,
    }
  end
end
