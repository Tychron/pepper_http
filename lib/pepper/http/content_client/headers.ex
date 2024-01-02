defmodule Pepper.HTTP.ContentClient.Headers do
  @moduledoc """
  ContentClient additional headers module, will add additional headers based on the options.
  """
  header_modules =
    Application.compile_env(:pepper_http, :base_additional_header_modules, [
      Pepper.HTTP.ContentClient.Headers.Authorization,
    ]) ++ Application.compile_env(:pepper_http, :additional_header_modules, [])

  def add_additional_headers(blob, headers, options) do
    Enum.reduce(unquote(header_modules), {headers, options}, fn module, {headers, options} ->
      module.call(blob, headers, options)
    end)
  end
end
