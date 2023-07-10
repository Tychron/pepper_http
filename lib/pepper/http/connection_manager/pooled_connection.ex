defmodule Pepper.HTTP.ConnectionManager.PooledConnection do
  defmodule State do
    defstruct [
      pool_pid: nil,
      conn: nil,
      scheme: nil,
      host: nil,
      port: nil,
      status: :ok,
      just_reconnected: false,
    ]
  end

  use GenServer

  alias Pepper.HTTP.Request
  alias Pepper.HTTP.Response
  alias Pepper.HTTP.ConnectError
  alias Pepper.HTTP.SendError
  alias Pepper.HTTP.RequestError
  alias Pepper.HTTP.ReceiveError

  import Pepper.HTTP.ConnectionManager.Utils

  def start_link(pool_pid, opts, process_options \\ []) do
    GenServer.start_link(__MODULE__, {pool_pid, opts}, process_options)
  end

  @doc """
  Asks the pooled connection to complete the specified request and then respond to the from with
  the result.
  """
  @spec request(GenServer.server(), Request.t(), GenServer.from()) :: :ok
  def request(pid, request, from) do
    GenServer.cast(pid, {:request, request, from})
  end

  @spec schedule_stop(GenServer.server()) :: :ok
  def schedule_stop(pid) do
    GenServer.cast(pid, :stop)
  end

  @impl true
  def init({pool_pid, opts}) do
    {:ok, %State{pool_pid: pool_pid}, Keyword.fetch!(opts, :lifespan)}
  end

  @impl true
  def terminate(_reason, %State{} = state) do
    if state.conn do
      Mint.HTTP.close(state.conn)
    end
    :ok
  end

  @impl true
  def handle_cast(:stop, %State{} = state) do
    {:stop, :normal, state}
  end

  @impl true
  def handle_cast({:request, %Request{} = request, from}, %State{} = state) do
    do_request(request, from, state)
  end

  @impl true
  def handle_info(:timeout, %State{} = state) do
    GenServer.cast(state.pool_pid, {:connection_expired, self()})
    {:noreply, %{state | status: :expired}}
  end

  @impl true
  def handle_info(message, %State{} = state) do
    if state.conn do
      case Mint.HTTP.stream(state.conn, message) do
        {:error, conn, %Mint.TransportError{reason: :closed}, _rest} ->
          {:stop, :normal, %{state | conn: conn}}

        {:error, conn, reason, _rest} ->
          {:stop, reason, %{state | conn: conn}}

        _ ->
          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  defp do_request(%Request{} = request, from, %State{} = state) do
    case prepare_connection(request, state) do
      {:ok, state} ->
        # go passive so messages can be captured manually
        state = try_set_connection_mode(:passive, state)

        {request, is_stream?, body} =
          determine_if_body_should_stream(state.conn, request)

        case Mint.HTTP.request(state.conn, request.method, request.path, request.headers, body) do
          {:ok, conn, ref} ->
            # if the request was done, then reset the just_connected state
            # it was only set initially to ensure that the request doesn't enter a reconnecting
            # loop
            state = %{state | just_reconnected: false}
            response = %Response{protocol: Mint.HTTP.protocol(conn)}
            result = maybe_stream_body(conn, ref, request, is_stream?, [])

            case result do
              {:ok, conn, responses} ->
                case read_responses(request.options[:mode], conn, ref, response, request, responses) do
                  {:ok, conn, result} ->
                    state = %{state | conn: conn}
                    :ok = GenServer.reply(from, {:ok, result})
                    state = checkin(state, :ok)
                    {:noreply, state}

                  {:error, conn, reason} ->
                    handle_receive_error(conn, reason, request, from, state)

                  {:error, conn, reason, _} ->
                    handle_receive_error(conn, reason, request, from, state)
                end

              {:error, conn, reason} ->
                handle_send_error(conn, reason, request, from, state)
            end

          {:error, conn, reason} ->
            should_reconnect? =
              if state.just_reconnected do
                # the connection was just established, and still had an error, give up
                false
              else
                # the connection may have been sitting around for awhile, if it was 'closed'
                # unexpectedly, then try reconnecting
                case reason do
                  :closed ->
                    true

                  %Mint.TransportError{reason: :closed} ->
                    true

                  _ ->
                    false
                end
              end

            if should_reconnect? do
              # if attempting a reconnect, close the existing connection (if its open at all)
              # and try the request again
              state = close_and_clear_connection(state)
              do_request(request, from, state)
            else
              # otherwise the request should not be retried and this worker will emit an error
              handle_request_error(conn, reason, request, from, state)
            end
        end

      {:error, reason, state} ->
        handle_connect_error(reason, request, from, state)
    end
  rescue ex ->
    msg = {:exception, ex, __STACKTRACE__}
    :ok = GenServer.reply(from, msg)
    state = checkin(state, msg)
    {:noreply, state}
  end

  defp checkin(%State{} = state, reason) do
    # return to active mode to capture errors and closed messages
    state = try_set_connection_mode(:active, state)
    :ok = GenServer.cast(state.pool_pid, {:checkin, self(), reason})
    state
  end

  defp prepare_connection(%Request{} = request, %State{} = state) do
    state =
      cond do
        is_nil(state.conn) ->
          state

        Mint.HTTP.open?(state.conn) ->
          # ensure that connection's scheme, host and port matches the request
          if request.scheme == state.scheme and
             request.uri.host == state.host and
             request.uri.port == state.port do
            # it matches, so return the state as is
            state
          else
            # the states do not match, close the connection
            close_and_clear_connection(state)
          end

        true ->
          %{state | conn: nil}
      end

    if state.conn do
      {:ok, state}
    else
      connect_options = Keyword.merge(
        [
          {:timeout, request.options[:connect_timeout]},
          {:mode, request.options[:mode]}
        ],
        Keyword.get(request.options, :connect_options, [])
      )

      case Mint.HTTP.connect(request.scheme, request.uri.host, request.uri.port, connect_options) do
        {:ok, conn} ->
          {:ok, %{
            state
            | conn: conn,
              scheme: request.scheme,
              host: request.uri.host,
              port: request.uri.port,
              just_reconnected: true
            }
          }

        {:error, reason} ->
          {:error, reason, state}
      end
    end
  end

  defp close_and_clear_connection(%State{} = state) do
    Mint.HTTP.close(state.conn)
    %{state | conn: nil}
  end

  defp try_set_connection_mode(_mode, %State{conn: nil} = state) do
    state
  end

  defp try_set_connection_mode(mode, %State{} = state) do
    case Mint.HTTP.set_mode(state.conn, mode) do
      {:ok, conn} ->
        %{state | conn: conn}

      {:error, _} ->
        state
    end
  end

  defp handle_request_error(conn, reason, request, from, %State{} = state) do
    state = %{state | conn: conn}
    ex = %RequestError{
      message: "Error occured while sending request to remote",
      reason: reason,
      request: request,
    }
    :ok = GenServer.reply(from, {:error, ex})
    state = checkin(state, {:error, ex})
    {:noreply, state}
  end

  defp handle_send_error(conn, reason, request, from, %State{} = state) do
    state = %{state | conn: conn}
    ex = %SendError{
      message: "Error occured while sending data to remote",
      reason: reason,
      request: request,
    }
    :ok = GenServer.reply(from, {:error, ex})
    state = checkin(state, {:error, ex})
    {:noreply, state}
  end

  defp handle_receive_error(conn, reason, request, from, %State{} = state) do
    state = %{state | conn: conn}
    ex = %ReceiveError{
      message: "Error occured while receiving data from remote",
      reason: reason,
      request: request,
    }
    :ok = GenServer.reply(from, {:error, ex})
    state = checkin(state, {:error, ex})
    {:noreply, state}
  end

  defp handle_connect_error(reason, request, from, %State{} = state) do
    ex = %ConnectError{
      message: "Could not establish connection",
      reason: reason,
      request: request,
    }
    :ok = GenServer.reply(from, {:error, ex})
    state = checkin(state, {:error, ex})
    {:noreply, state}
  end
end
