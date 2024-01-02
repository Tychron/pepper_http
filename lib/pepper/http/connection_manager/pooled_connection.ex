defmodule Pepper.HTTP.ConnectionManager.PooledConnection do
  defmodule State do
    defstruct [
      ref: nil,
      stage: :idle,
      lifespan: nil,
      pool_pid: nil,
      conn: nil,
      scheme: nil,
      host: nil,
      port: nil,
      status: :ok,
      just_reconnected: false,
      #
      response: nil,
      request: nil,
      active_request: nil,
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

  @connection_key :"$connection"

  def start_link(pool_pid, ref, opts, process_options \\ []) do
    GenServer.start_link(__MODULE__, {pool_pid, ref, opts}, process_options)
  end

  @doc """
  Asks the pooled connection to complete the specified request and then respond to the from with
  the result.
  """
  @spec request(GenServer.server(), Request.t(), GenServer.from()) :: :ok
  def request(pid, request, from) do
    GenServer.cast(pid, {:request, request, from})
  end

  @spec schedule_stop(GenServer.server(), reason::any()) :: :ok
  def schedule_stop(pid, reason \\ :normal) do
    GenServer.cast(pid, {:stop, reason})
  end

  @impl true
  def init({pool_pid, ref, opts}) do
    lifespan = Keyword.fetch!(opts, :lifespan)
    {:ok, %State{ref: ref, pool_pid: pool_pid, lifespan: lifespan}, lifespan}
  end

  @impl true
  def handle_continue({:handle_responses, []}, %State{} = state) do
    timeout = determine_timeout(state)
    {:noreply, state, timeout}
  end

  @impl true
  def handle_continue(
    {:handle_responses, [http_response | http_responses]},
    %State{
      conn: conn,
      request: request,
      response: response,
      active_request: %{
        from: from,
        ref: ref,
      }
    } = state
  ) do
    case handle_response(conn, ref, response, request, http_response) do
      {:next, %Response{} = response} ->
        state = %State{
          state
          | response: response
        }
        {:noreply, state, {:continue, {:handle_responses, http_responses}}}

      {:done, %Response{} = response} ->
        response =
          %{
            response
            | time: System.monotonic_time(:microsecond),
          }

        :ok = GenServer.reply(from, {:ok, response})
        state = checkin(state, :ok)
        state = %State{
          state
          | stage: :idle,
            response: nil,
            request: nil,
            active_request: nil,
        }
        {:noreply, state, state.lifespan}

      {:error, conn, reason} ->
        handle_receive_error(conn, reason, request, from, state)
    end
  end

  @impl true
  def terminate(_reason, %State{} = state) do
    if state.conn do
      Mint.HTTP.close(state.conn)
    end
    :ok
  end

  @impl true
  def handle_cast({:stop, reason}, %State{} = state) do
    {:stop, reason, state}
  end

  @impl true
  def handle_cast({:request, %Request{} = request, from}, %State{} = state) do
    do_start_request(request, from, state)
  end

  @impl true
  def handle_info(:timeout, %State{stage: :idle} = state) do
    {:stop, :normal, %{state | status: :expired}}
  end

  @impl true
  def handle_info(:timeout, %State{stage: :recv, active_request: %{from: from}} = state) do
    reason = %Pepper.HTTP.ReceiveError{reason: %Mint.TransportError{reason: :timeout}}
    err = {:error, reason}
    :ok = GenServer.reply(from, err)
    state = checkin(state, err)
    {:stop, :normal, %{state | status: :recv_timeout}}
  end

  @impl true
  def handle_info(:timeout, %State{stage: _} = state) do
    {:stop, :timeout, %{state | status: :expired}}
  end

  @impl true
  def handle_info(
    {@connection_key, :send_body},
    %State{
      conn: conn,
      request: request,
      active_request: %{
        from: from,
        ref: ref,
        is_stream?: is_stream?,
      },
    } = state
  ) do
    case maybe_stream_request_body(:active, conn, ref, request, is_stream?, []) do
      {:ok, conn, responses} ->
        state = %{
          state
          | stage: :recv,
            conn: conn,
        }
        {:noreply, state, {:continue, {:handle_responses, responses}}}

      {:error, conn, reason} ->
        handle_send_error(conn, reason, request, from, state)
    end
  end

  @impl true
  def handle_info(message, %State{conn: nil} = state) do
    {:stop, {:unexpected_message, message}, state}
  end

  @impl true
  def handle_info(message, %State{conn: conn} = state) do
    case Mint.HTTP.stream(conn, message) do
      {:error, conn, %Mint.TransportError{reason: :closed}, _rest} ->
        state = %State{state | conn: conn}
        {:stop, :normal, state}

      {:error, conn, reason, _rest} ->
        state = %State{state | conn: conn}
        {:stop, reason, state}

      {:ok, conn, []} ->
        state = %State{state | conn: conn}
        timeout = determine_timeout(state)
        {:noreply, state, timeout}

      {:ok, conn, responses} ->
        state = %State{state | conn: conn}
        {:noreply, state, {:continue, {:handle_responses, responses}}}
    end
  end

  defp do_start_request(%Request{} = request, from, %State{} = state) do
    case prepare_connection(request, state) do
      {:ok, state} ->
        {request, is_stream?, body} =
          determine_if_body_should_stream(state.conn, request)

        case Mint.HTTP.request(state.conn, request.method, request.path, request.headers, body) do
          {:ok, conn, ref} ->
            # if the request was done, then reset the just_connected state
            # it was only set initially to ensure that the request doesn't enter a reconnecting
            # loop
            send(self(), {@connection_key, :send_body})

            state = %{
              state
              | stage: :send,
                just_reconnected: false,
                conn: conn,
                request: request,
                active_request: %{
                  ref: ref,
                  from: from,
                  is_stream?: is_stream?
                },
                response: %Response{
                  ref: state.ref,
                  protocol: Mint.HTTP.protocol(conn),
                  body_handler: request.response_body_handler,
                  body_handler_options: request.response_body_handler_options
                }
            }
            {:noreply, state, state.lifespan}

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
              do_start_request(request, from, state)
            else
              # otherwise the request should not be retried and this worker will emit an error
              handle_request_error(conn, reason, request, from, state)
            end
        end

      {:error, reason, state} ->
        handle_connect_error(reason, request, from, state)
    end
  end

  defp determine_timeout(%State{request: request} = state) do
    case state.stage do
      stage when stage in [:send, :idle] ->
        state.lifespan

      :recv ->
        request.options[:recv_timeout]
    end
  end

  defp checkin(%State{} = state, reason) do
    # return the connection to its parent pool
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
      req_options = request.options
      connect_options = Keyword.merge(
        [
          mode: :active,
          transport_opts: [
            timeout: req_options[:connect_timeout],
          ],
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

  defp handle_request_error(conn, reason, request, from, %State{} = state) do
    state = %{state | conn: conn}
    ex = %RequestError{
      message: "Error occured while sending request to remote",
      reason: reason,
      request: request,
    }
    :ok = GenServer.reply(from, {:error, ex})
    state = checkin(state, {:error, ex})
    {:noreply, state, state.lifespan}
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
    {:noreply, state, state.lifespan}
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
    {:noreply, state, state.lifespan}
  end

  defp handle_connect_error(reason, request, from, %State{} = state) do
    ex = %ConnectError{
      message: "Could not establish connection",
      reason: reason,
      request: request,
    }
    :ok = GenServer.reply(from, {:error, ex})
    state = checkin(state, {:error, ex})
    {:noreply, state, state.lifespan}
  end
end
