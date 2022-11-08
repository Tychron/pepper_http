defmodule Pepper.HTTP.Support.ClientCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias Pepper.HTTP.ContentClient

      import Plug.Conn
      import unquote(__MODULE__)
      import Pepper.HTTP.Support.PlugPipelineHelpers

      @no_query_params []

      @no_headers []

      @no_body nil

      @no_options []

      @user_agent "content-client-test/1.0"
    end
  end

  def bypass_for_configured_endpoint(application_name, field) do
    value = Application.get_env(application_name, field)

    bypass_for_url(value)
  end

  def bypass_for_url(url) when is_binary(url) do
    case URI.new(url) do
      {:ok, uri} ->
        Bypass.open(port: uri.port)
    end
  end

  def read_all_body(conn, acc \\ []) do
    case Plug.Conn.read_body(conn) do
      {:ok, body, conn} ->
        {:ok, IO.iodata_to_binary(Enum.reverse([body | acc])), conn}

      {:more, body, conn} ->
        read_all_body(conn, [body | acc])

      {:error, _} = err ->
        err
    end
  end
end
