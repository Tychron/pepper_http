defmodule Pepper.HTTP.Utils do
  defmodule Segment do
    defstruct [
      headers: [],
      body: []
    ]
  end

  import Mint.HTTP1.Parse

  require SweetXml

  def to_multipart_message(rows, state \\ {:headers, %Segment{}})

  def to_multipart_message([], {_, %Segment{} = segment}) do
    %{
      segment
      | headers: Enum.reverse(segment.headers),
        body: Enum.reverse(segment.body)
    }
  end

  def to_multipart_message(["" | rows], {:headers, %Segment{} = segment}) do
    to_multipart_message(rows, {:body, segment})
  end

  def to_multipart_message([row | rows], {:body, %Segment{} = segment}) do
    segment = %{
      segment
      | body: [row | segment.body]
    }
    to_multipart_message(rows, {:body, segment})
  end

  def to_multipart_message([row | rows], {:headers, %Segment{} = segment}) when is_binary(row) do
    [key, value] = String.split(row, ":", parts: 2)
    value = String.trim_leading(value)

    segment = %{
      segment
      | headers: [{key, value} | segment.headers]
    }
    to_multipart_message(rows, {:headers, segment})
  end

  def to_multipart_messages(rows) when is_list(rows) do
    Enum.map(rows, &to_multipart_message/1)
  end

  def blob_to_multipart_messages(blob, boundary) when is_binary(blob) do
    blob
    |> String.split("\r\n")
    |> extract_parts_with_boundary(boundary)
    |> to_multipart_messages()
  end

  @spec extract_parts_with_boundary([String.t()], String.t(), list, list | nil) :: [[String.t()]]
  def extract_parts_with_boundary(rows, boundary, acc \\ [], parts \\ nil)

  def extract_parts_with_boundary([], _boundary, [], parts) do
    Enum.reverse(parts || [])
  end

  def extract_parts_with_boundary([line | rows], {boundary, boundary_end} = boundary_pair, acc, parts) do
    case {String.trim_trailing(line), parts} do
      {^boundary, nil} ->
        # a boundary has been encoutered, initialize the lines accumulator
        extract_parts_with_boundary(rows, boundary_pair, acc, [])

      {^boundary, parts} ->
        # parts exist and a boundary has been encountered,
        # add the accumulated lines to the parts list
        # And start a new lines accumulator
        extract_parts_with_boundary(rows, boundary_pair, [], [Enum.reverse(acc) | parts])

      {^boundary_end, parts} ->
        # the boundary end, finish parsing
        # the boundary was the end, commit the accumulator and clear the tail
        extract_parts_with_boundary([], boundary_pair, [], [Enum.reverse(acc) | List.wrap(parts)])

      {_line, nil} ->
        # no valid parts, and the line is not a boundary, discard it
        extract_parts_with_boundary(rows, boundary_pair, acc, nil)

      {line, parts} ->
        # there are parts active, collect the line
        extract_parts_with_boundary(rows, boundary_pair, [line | acc], parts)
    end
  end

  def extract_parts_with_boundary(rows, boundary, acc, parts) when is_binary(boundary) do
    boundary = "--#{boundary}"
    boundary_end = "#{boundary}--"
    extract_parts_with_boundary(rows, {boundary, boundary_end}, acc, parts)
  end

  @spec generate_random_base32(non_neg_integer, Keyword.t()) :: String.t()
  def generate_random_base32(len, options \\ []) when is_integer(len) and len > 0 do
    # double characters since the length will end up being slightly shorter than needed otherwise
    # i.e. the generated bytes will not be enough to complete a base32 encoding with the desired length
    (len * 2)
    |> :crypto.strong_rand_bytes()
    |> Base.encode32(options)
    |> binary_part(0, len)
  end

  def handle_xml_body(doc) do
    doc =
      doc
      |> List.wrap()
      |> Enum.map(fn item ->
        record_type = elem(item, 0)
        xml_item_to_map(record_type, item)
      end)
      |> deflate_xml_map()

    doc
  end

  for name <- [
      :xmlDecl,
      :xmlAttribute,
      :xmlNamespace,
      :xmlNsNode,
      :xmlElement,
      :xmlText,
      :xmlComment,
      :xmlPI,
      :xmlDocument,
      :xmlObj,
    ] do
    def xml_item_to_map(unquote(name), item) do
      SweetXml.unquote(name)(item)
      |> xml_item_deep_to_map(unquote(name))
    end
  end

  def xml_item_deep_to_map(item, :xmlElement) do
    #namespace = xml_item_to_map(:xmlNamespace, item[:namespace])
    #item = put_in(item[:namespace], namespace)
    #put_in(item[:content], Enum.map(item[:content], fn item ->
    #  xml_item_to_map(elem(item, 0), item)
    #end))

    {item[:expanded_name],
      Enum.map(item[:content], fn item ->
        xml_item_to_map(elem(item, 0), item)
      end)
    }
  end

  def xml_item_deep_to_map(item, :xmlNamespace) do
    item
  end

  def xml_item_deep_to_map(item, :xmlText) do
    to_string(item[:value])
  end

  def deflate_xml_map([{_, _} | _] = list) when is_list(list) do
    [
      Enum.reduce(list, %{}, fn
        {key, value}, acc ->
          acc = Map.put_new(acc, key, [])

          Map.put(acc, key, acc[key] ++ deflate_xml_map(value))
      end)
    ]
  end

  def deflate_xml_map(list) when is_list(list) do
    list
    |> Enum.chunk_by(fn
      {_key, _value} ->
        :map

      value when is_binary(value) ->
        :text
    end)
    |> Enum.flat_map(fn
      [{_, _} | _] = list ->
        deflate_xml_map(list)

      list when is_list(list) ->
        list
    end)
  end

  def normalize_http_method(:head), do: "HEAD"
  def normalize_http_method(:get), do: "GET"
  def normalize_http_method(:patch), do: "PATCH"
  def normalize_http_method(:post), do: "POST"
  def normalize_http_method(:put), do: "PUT"
  def normalize_http_method(:delete), do: "DELETE"
  def normalize_http_method(:options), do: "OPTIONS"

  def normalize_http_method(method) when is_binary(method) do
    String.upcase(method)
  end

  def normalize_headers(headers) when is_list(headers) or is_map(headers) do
    Enum.map(headers, fn {key, value} ->
      {String.downcase(key), value}
    end)
  end

  def generate_boundary do
    time = System.system_time(:millisecond)
    # borrowed from Ecto.ULID
    timestamp = <<time::unsigned-size(48), :crypto.strong_rand_bytes(10)::binary>>
    Base.encode16(timestamp)
  end

  # Copied from https://raw.githubusercontent.com/elixir-mint/mint/b4ea6f0efc8863663b894d7501f282a85f08bc65/lib/mint/http1/request.ex
  def encode_headers(headers) do
    Enum.reduce(headers, "", fn {name, value}, acc ->
      validate_header_name!(name)
      validate_header_value!(name, value)
      [acc, name, ": ", value, "\r\n"]
    end)
  end

  # Percent-encoding is not case sensitive so we have to account for lowercase and uppercase.
  @hex_characters '0123456789abcdefABCDEF'

  def validate_target!(target), do: validate_target!(target, target)

  def validate_target!(<<?%, char1, char2, rest::binary>>, original_target)
       when char1 in @hex_characters and char2 in @hex_characters do
    validate_target!(rest, original_target)
  end

  def validate_target!(<<char, rest::binary>>, original_target) do
    if URI.char_unescaped?(char) do
      validate_target!(rest, original_target)
    else
      throw({:mint, {:invalid_request_target, original_target}})
    end
  end

  def validate_target!(<<>>, _original_target) do
    :ok
  end

  def validate_header_name!(name) do
    _ =
      for <<char <- name>> do
        unless is_tchar(char) do
          throw({:mint, {:invalid_header_name, name}})
        end
      end

    :ok
  end

  def validate_header_value!(name, value) do
    _ =
      for <<char <- value>> do
        unless is_vchar(char) or char in '\s\t' do
          throw({:mint, {:invalid_header_value, name, value}})
        end
      end

    :ok
  end

  @spec stream_binary_chunks(binary(), non_neg_integer()) :: Enum.t()
  def stream_binary_chunks(bin, chunk_size) when is_binary(bin) and is_integer(chunk_size) do
    Stream.resource(
      fn ->
        bin
      end,
      fn
        <<>> ->
          {:halt, <<>>}

        bin when is_binary(bin) ->
          case bin do
            <<chunk::binary-size(chunk_size), rest::binary>> ->
              {[chunk], rest}

            chunk when is_binary(chunk) ->
              {[chunk], <<>>}
          end
      end,
      fn _ ->
        :ok
      end
    )
  end
end
