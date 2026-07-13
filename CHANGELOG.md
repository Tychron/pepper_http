# 0.8.0

## Breaking Changes

* Changed underlying XML encoding and decoder library to `saxy`, while encoding should remain the same, those handling XML responses must change their code to accept Saxy's "simple" format.
  * If you use the `normalize_xml` option, keys are no longer atoms but strings.
* Removed `:jsonapi` response body type, it will just report as `:json` instead
* Remove `mode` option, do not use it the respective connection manager will set the mode for itself
* ContentClient will now return `:unaccepted` and `{:malformed, term}`` in addition to :unk to differentiate response bodies.
  * `:unaccepted` will be returned when the response `content-type` was not acceptable from the request's accept header
  * `:malformed` will be returned whenever the response body could not be parsed (or the `content-type` header was malformed)
  * `:unk` will be returned for all other cases

## Changes

* Pepper.HTTP.ConnectionManager.PooledConnection is always in active mode

# 0.7.0

* `Pepper.HTTP.Client` and `Pepper.HTTP.ContentClient` can now accept a URI struct in place of a URL string

# 0.6.0

* Bugfix `recv_size` was not respected allowing a response to be completely read into memory, an error is now returned when the `recv_size` is exceeded, discarding the entire currently read body in the process.
* Added `Pepper.HTTP.ResponseBodyHandler` modules:
  * `Default` - read response from server and store as binary
  * `File` - read response to a file
* Added `docs/*.md` which contains documentation on the libraries usage for most common cases

# 0.2.0

* Changed undocumented error tuples on request

```elixir
{:error, {:unexpected_scheme, schema}} #=> {:error, %Pepper.HTTP.URIError{reason: :unexpected_scheme}}

# ** (CaseClauseError) no case clause matching: %URI{} is now handled as
{:error, %Pepper.HTTP.URIError{reason: :bad_uri}}
```

* Added `Pepper.HTTP.ConnectionManager.Pooled.start/2`
