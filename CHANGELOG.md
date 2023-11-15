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
