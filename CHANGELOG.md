# 0.2.0

* Changed undocumented error tuples on request

```elixir
{:error, {:unexpected_scheme, schema}} #=> {:error, %Pepper.HTTP.URIError{reason: :unexpected_scheme}}

# ** (CaseClauseError) no case clause matching: %URI{} is now handled as
{:error, %Pepper.HTTP.URIError{reason: :bad_uri}}
```

* Added `Pepper.HTTP.ConnectionManager.Pooled.start/2`
