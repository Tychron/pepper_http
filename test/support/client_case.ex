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

  setup tags do
    tags =
      case Map.get(tags, :with_connection_pool, false) do
        true ->
          {:ok, pid} =
            start_supervised({Pepper.HTTP.ConnectionManager.Pooled, [
              Keyword.merge(
                [{:pool_size, 10}],
                Map.get(tags, :connection_pool_options, [])
              ),
              []
            ]})

          Map.put(tags, :connection_pool_pid, pid)

        false ->
          tags
      end

    protocol = String.to_existing_atom(Map.fetch!(tags, :protocol))

    client_options = [
      connect_options: [
        protocols: [protocol]
      ]
    ]

    client_options =
      case tags[:connection_pool_pid] do
        nil ->
          client_options

        pid ->
          Keyword.merge(client_options, [
            connection_manager: :pooled,
            connection_manager_id: pid,
          ])
      end

    Map.put(tags, :client_options, client_options)
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
