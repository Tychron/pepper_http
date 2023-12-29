defmodule Pepper.HTTP.ResponseBodyHandler.File do
  @moduledoc """
  File handlers will write a response's body to a specified file by :filename

  Usage:

      options = [
        response_body_handler: Pepper.HTTP.ResponseBodyHandler.File,
        response_body_handler_options: [
          filename: "path/to/file"
        ]
      ]

      {:ok, resp} = Pepper.HTTP.Client.request(method, url, headers, body, options)

      resp.body # => {:file, "path/to/file"}

  """
  alias Pepper.HTTP.Request
  alias Pepper.HTTP.Response

  @behaviour Pepper.HTTP.ResponseBodyHandler

  @impl true
  def init(
    %Request{} = _request,
    %Response{body_handler_options: options} = response
  ) do
    filename = Keyword.fetch!(options, :filename)
    file_options = Keyword.get(options, :file_options, [])

    case File.open(filename, [:write | file_options]) do
      {:ok, file} ->
        {:ok, %{response | data: {filename, file}}}

      {:error, reason} ->
        {:error, {:file_handler_error, reason}}
    end
  end

  @impl true
  def handle_data(_size, data, %Response{data: {_filename, file}} = response) do
    case IO.binwrite(file, data) do
      :ok ->
        {:ok, response}
    end
  end

  @impl true
  def cancel(%Response{data: nil} = response) do
    {:ok, response}
  end

  @impl true
  def cancel(%Response{data: {_filename, file}} = response) do
    :ok = File.close(file)
    {:ok, %{response | data: nil}}
  end

  @impl true
  def finalize(%Response{data: nil} = response) do
    {:ok, response}
  end

  def finalize(%Response{data: {filename, file}} = response) do
    :ok = File.close(file)
    response = %{response | data: nil, body: {:file, filename}}
    {:ok, response}
  end
end
