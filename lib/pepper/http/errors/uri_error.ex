defmodule Pepper.HTTP.URIError do
  defexception [
    :message,
    :url,
    :uri,
    :reason,
  ]

  @type t :: %__MODULE__{
    message: String.t(),
    url: String.t(),
    uri: URI.t(),
    reason: atom(),
  }
end
