defmodule Pepper.HTTP.Response do
  defstruct [
    request: nil,
    headers: [],
    protocol: :unknown,
    body: "",
    data: [],
    status_code: nil,
  ]

  @type t :: %__MODULE__{
    request: Pepper.HTTP.Request.t(),
    headers: [{String.t(), String.t()}],
    protocol: :unknown | :http1 | :http2,
    body: binary(),
    data: list(),
    status_code: non_neg_integer() | nil,
  }
end
