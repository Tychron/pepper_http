defmodule Pepper.HTTP.ConnectError do
  defexception [
    :message,
    :request,
    :reason,
  ]
end
