defmodule Pepper.HTTP.ResponseBodyHandler.Default do
  @moduledoc """
  Default response_body_handler, the response's body will be read into memory.

  Usage:

      {:ok, resp} = Pepper.HTTP.Client.request(method, url, headers, body, options)

      resp.body #=> binary

  """
  alias Pepper.HTTP.Response

  @behaviour Pepper.HTTP.ResponseBodyHandler

  @impl true
  def init(_request, %Response{} = response) do
    {:ok, %{response | data: []}}
  end

  @impl true
  def handle_data(_size, data, %Response{} = response) do
    response = %{
      response
      | data: [data | response.data],
    }
    {:ok, response}
  end

  @impl true
  def cancel(%Response{data: nil} = response) do
    {:ok, response}
  end

  @impl true
  def cancel(%Response{} = response) do
    response = %{response | data: nil}
    {:ok, response}
  end

  @impl true
  def finalize(%Response{data: nil} = response) do
    {:ok, response}
  end

  @impl true
  def finalize(%Response{data: data} = response) do
    response = %{response | data: nil}

    response_body =
      data
      |> Enum.reverse()
      |> IO.iodata_to_binary()

    response = %{response | body: response_body}

    {:ok, response}
  end
end
