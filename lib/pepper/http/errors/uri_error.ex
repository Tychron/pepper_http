defmodule Pepper.HTTP.URIError do
  defexception [
    :message,
    :uri,
    :reason,
  ]

  @type t :: %__MODULE__{
    message: String.t(),
    uri: URI.t(),
    reason: atom(),
  }
end
