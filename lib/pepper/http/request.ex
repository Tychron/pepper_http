defmodule Pepper.HTTP.Request do
  defstruct [
    scheme: nil,
    method: nil,
    url: nil,
    uri: nil,
    path: nil,
    query_params: nil,
    headers: nil,
    body: nil,
    blob: nil,
    recv_size: nil,
    response_body_handler: nil,
    response_body_handler_options: nil,
    options: nil,
  ]

  @type t :: %__MODULE__{
    scheme: :http | :https,
    method: String.t(),
    url: String.t(),
    uri: URI.t(),
    path: String.t(),
    query_params: list(),
    headers: list(),
    body: term(),
    blob: binary(),
    recv_size: non_neg_integer(),
    response_body_handler: module(),
    response_body_handler_options: any(),
    options: Keyword.t(),
  }
end
