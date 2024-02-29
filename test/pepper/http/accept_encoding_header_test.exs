defmodule Pepper.HTTP.AcceptEncodingHeaderTest do
  @moduledoc """
  This test is a sanity check of :accept_encoding_header
  """
  use ExUnit.Case

  describe "parse/1" do
    test "can correctly parse" do
      assert [
        {:content_coding, '*', 1, []}
      ] = :accept_encoding_header.parse("*")

      assert [
        {:content_coding, 'identity', 1, []}
      ] = :accept_encoding_header.parse("identity")

      assert [
        {:content_coding, 'identity', 1, []},
        {:content_coding, 'deflate', 1, []},
        {:content_coding, 'gzip', 1, []},
      ] = :accept_encoding_header.parse("identity, deflate, gzip")
    end
  end
end
