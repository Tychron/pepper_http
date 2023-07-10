defmodule Pepper.HTTP.CheckoutError do
  defexception [
    :message,
    :request,
    :reason,
  ]

  @type t :: %__MODULE__{
    message: String.t(),
    request: Pepper.HTTP.Request.t(),
    reason: atom(),
  }
end
