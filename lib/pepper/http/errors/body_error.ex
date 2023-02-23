defmodule Pepper.HTTP.BodyError do
  defexception [
    :message,
    :body,
    :reason,
  ]

  @type t :: %__MODULE__{
    message: String.t(),
    body: any(),
    reason: atom(),
  }
end
