defmodule Pepper.HTTP.BodyEncoder do
  def encode_body(body, options \\ [])

  def encode_body(nil, _options) do
    {:ok, {[], ""}}
  end

  def encode_body(binary, _options) when is_binary(binary) do
    {:ok, {[], binary}}
  end

  def encode_body(list, _options) when is_list(list) do
    {:ok, {[], list}}
  end

  encoders =
    Application.compile_env(:pepper_http, :base_encoders, [
      csv: Pepper.HTTP.BodyEncoder.CSV,
      form: Pepper.HTTP.BodyEncoder.Form,
      form_stream: Pepper.HTTP.BodyEncoder.FormStream,
      form_urlencoded: Pepper.HTTP.BodyEncoder.FormUrlencoded,
      json: Pepper.HTTP.BodyEncoder.JSON,
      stream: Pepper.HTTP.BodyEncoder.Stream,
      text: Pepper.HTTP.BodyEncoder.Text,
      xml: Pepper.HTTP.BodyEncoder.XML,
    ]) ++ Application.compile_env(:pepper_http, :encoders, [])

  Enum.each(encoders, fn {name, module} ->
    def encode_body({unquote(name), value}, options) do
      unquote(module).encode_body(value, options)
    end
  end)
end
