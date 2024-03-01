defmodule Pepper.HTTP.ContentClient.Headers.Authorization do
  defmodule UnhandledAuthMethodError do
    defexception [:message, :method]
  end

  @moduledoc """
  Header module for adding an Authorization Header
  """

  @spec call(any(), headers::Proplist.t(), options::Keyword.t()) ::
    {headers::Proplist.t(), options::Keyword.t()}
  def call(_blob, headers, options) do
    {auth_method, options} = Keyword.pop(options, :auth_method, :none)
    {username, options} = Keyword.pop(options, :auth_identity)
    {password, options} = Keyword.pop(options, :auth_secret)

    headers = set_authorization_header(auth_method, username, password, headers)
    {headers, options}
  end

  def set_authorization_header(:none, _unused1, _unsued2, headers) do
    headers
  end

  def set_authorization_header(:basic, username, password, headers) do
    auth = Base.encode64("#{username}:#{password}")

    [
      {"authorization", "Basic #{auth}"}
      | headers
    ]
  end

  def set_authorization_header(:bearer, _unused, token, headers) do
    [
      {"authorization", "Bearer #{token}"}
      | headers
    ]
  end

  def set_authorization_header("none", _unused1, _unsued2, headers) do
    headers
  end

  def set_authorization_header("basic", username, password, headers) do
    set_authorization_header(:basic, username, password, headers)
  end

  def set_authorization_header("bearer", unused, token, headers) do
    set_authorization_header(:bearer, unused, token, headers)
  end

  def set_authorization_header(method, _username, _password, _headers) do
    raise UnhandledAuthMethodError, method: method, message: "unhandled auth method"
  end
end
