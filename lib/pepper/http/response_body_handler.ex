defmodule Pepper.HTTP.ResponseBodyHandler do
  alias Pepper.HTTP.Request
  alias Pepper.HTTP.Response

  @callback init(Request.t(), Response.t()) :: {:ok, Response.t()}

  @callback handle_data(size::non_neg_integer(), data::binary(), Response.t()) :: {:ok, Response.t()}

  @callback cancel(Response.t()) :: {:ok, Response.t()}

  @callback finalize(Response.t()) :: {:ok, Response.t()}
end
