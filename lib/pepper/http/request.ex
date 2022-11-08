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
    options: Keyword.t(),
  }
end
