defmodule Pepper.HTTP.Response do
  defstruct [
    request: nil,
    headers: [],
    protocol: :unknown,
    recv_size: 0,
    body_state: :none,
    body_handler: nil,
    body_handler_options: nil,
    body: "",
    data: nil,
    status_code: nil,
  ]

  @type t :: %__MODULE__{
    request: Pepper.HTTP.Request.t(),
    headers: [{String.t(), String.t()}],
    protocol: :unknown | :http1 | :http2,
    recv_size: 0,
    body_state: :none,
    body_handler: module(),
    body_handler_options: any(),
    body: binary(),
    data: any(),
    status_code: non_neg_integer() | nil,
  }
end
