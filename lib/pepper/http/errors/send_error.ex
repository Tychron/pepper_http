defmodule Pepper.HTTP.SendError do
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
