defmodule Pepper.HTTP.ConnectionManager.Pooled do
  defmodule State do
    defstruct [
      busy_connections: nil,
      available_connections: nil,
      default_lifespan: nil,
      pool_size: nil,
      busy_size: 0,
      available_size: 0,
    ]
  end

  @moduledoc """
  Connection pool implementation
  """

  require Logger

  use GenServer

  alias Pepper.HTTP.ConnectionManager.PooledConnection
  alias Pepper.HTTP.Request
  alias Pepper.HTTP.Response

  @type conn_key :: {scheme::atom(), host::String.t(), port::integer()}

  @type connection_id :: GenServer.server()

  @type start_option :: {:pool_size, integer()}
                      | {:default_lifespan, non_neg_integer()}

  @type start_options :: [start_option()]

  def child_spec([opts]) do
    child_spec([opts, []])
  end

  def child_spec([_opts, _process_options] = args) do
    Supervisor.child_spec(%{
      id: __MODULE__,
      start: {__MODULE__, :start_link, args},
      type: :worker,
      restart: :permanent,
      shutdown: 15000
    }, %{})
  end

  @spec request(connection_id(), Request.t()) :: {:ok, Response.t()} | {:error, term()}
  def request(server, request) do
    connect_timeout = Keyword.fetch!(request.options, :connect_timeout)
    recv_timeout = Keyword.fetch!(request.options, :recv_timeout)
    timeout = connect_timeout + recv_timeout + 100
    case GenServer.call(server, {:request, request}, timeout) do
      {:ok, _resp} = res ->
        res

      {:error, _reason} = err ->
        err

      {:exception, ex, stacktrace} ->
        reraise ex, stacktrace
    end
  end

  def get_stats(server, timeout \\ 15_000) do
    GenServer.call(server, :get_stats, timeout)
  end

  defdelegate stop(pid, reason \\ :normal), to: GenServer

  @spec start_link(start_options(), Keyword.t()) :: GenServer.on_start()
  def start_link(opts, process_options \\ []) do
    opts = Keyword.put_new(opts, :pool_size, 100)
    opts = Keyword.put_new(opts, :default_lifespan, 30_000)
    GenServer.start_link(__MODULE__, opts, process_options)
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    available_connections = :ets.new(:available_connections, [:duplicate_bag, :private])
    busy_connections = :ets.new(:busy_connections, [:duplicate_bag, :private])

    state =
      %State{
        busy_connections: busy_connections,
        available_connections: available_connections,
        default_lifespan: Keyword.fetch!(opts, :default_lifespan), # 30 seconds
        pool_size: Keyword.fetch!(opts, :pool_size)
      }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_stats, _from, %State{} = state) do
    stats = %{
      pool_size: state.pool_size,
      busy_size: state.busy_size,
      available_size: state.available_size,
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call({:request, request}, from, %State{} = state) do
    connect_options = Keyword.get(request.options, :connect_options, [])

    key = {request.scheme, request.uri.host, request.uri.port, connect_options}
    case checkout_connection(key, state) do
      {:empty, state} ->
        {:reply, {:error, :no_available_connections}, state}

      {:ok, {^key, pid}, state} when is_pid(pid) ->
        # submit the request to the pooled connection
        :ok = PooledConnection.request(pid, request, from)
        #
        state = add_busy_connection({key, {pid, from}}, state)
        {:noreply, state}

      {:error, reason, state} ->
        {:reply, {:error, {:checkout_error, reason}}, state}
    end
  end

  @impl true
  def handle_cast({:connection_expired, pid}, %State{} = state) do
    case get_available_connection_by_pid(pid, state) do
      {[{_key, ^pid}], _continuation} ->
        :ok = PooledConnection.schedule_stop(pid)
        {:noreply, state}

      :'$end_of_table' ->
        case get_busy_connection_by_pid(pid, state) do
          {[{_key, {^pid, _from}}], _continuation} ->
            :ok = PooledConnection.schedule_stop(pid)
            {:noreply, state}

          :'$end_of_table' ->
            {:noreply, state}
        end
    end
  end

  @impl true
  def handle_cast({:checkin, pid, reason}, %State{} = state) do
    case get_busy_connection_by_pid(pid, state) do
      {[{key, {^pid, _from}} = pair], _continuation} ->
        state = remove_busy_connection(pair, state)
        case reason do
          :ok ->
            state = add_available_connection({key, pid}, state)
            {:noreply, state}

          {:error, _reason} ->
            {:noreply, state}

          {:exception, _ex, _stacktrace} ->
            {:noreply, state}
        end

      :'$end_of_table' ->
        Logger.warning "unexpected checkin", [pid: inspect(pid), reason: inspect(reason)]
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, %State{} = state) do
    case get_busy_connection_by_pid(pid, state) do
      {[{_key, {^pid, _from}} = pair], _continuation} ->
        state = remove_busy_connection(pair, state)
        {:noreply, state}

      :'$end_of_table' ->
        case get_available_connection_by_pid(pid, state) do
          {[{_key, ^pid} = pair], _continuation} ->
            state = remove_available_connection(pair, state)
            {:noreply, state}

          :'$end_of_table' ->
            Logger.error "an unknown process has terminated", [reason: inspect(reason)]
            #{:stop, {:unexpected_exit, pid}, state}
            {:noreply, state}
        end
    end
  end

  defp checkout_connection(key, %State{} = state) do
    if state.available_size > 0 do
      # check if there are any available connections
      case checkout_available_connection(key, state) do
        {:empty, state} ->
          # try checking out a new connection instead
          case checkout_new_connection(key, state) do
            {:empty, state} ->
              # try reclaiming an existing connection as a last resort
              reclaim_available_connection(key, state)
              # if the above fails, then there are no connections which can be used

            {:error, _reason, _state} = err ->
              # pass the error through
              err

            {:ok, {^key, _pid}, _state} = res ->
              res
          end

        {:ok, {^key, _pid}, _state} = res ->
          res
      end
    else
      checkout_new_connection(key, state)
    end
  end

  defp checkout_available_connection(key, %State{} = state) do
    case get_available_connection_by_key(key, state) do
      {[{^key, _pid} = pair], _continuation} ->
        state = remove_available_connection(pair, state)
        {:ok, pair, state}

      :'$end_of_table' ->
        # there are no available connections
        {:empty, state}
    end
  end

  defp checkout_new_connection(key, %State{} = state) do
    if state.pool_size > calc_used_connections(state) do
      # there are new connections still available
      case PooledConnection.start_link(self(), [lifespan: state.default_lifespan]) do
        {:ok, pid} ->
          {:ok, {key, pid}, state}

        {:error, reason} ->
          {:error, reason, state}
      end
    else
      {:empty, state}
    end
  end

  defp reclaim_available_connection(key, %State{} = state) do
    match_spec = [
      {
        {:'$1', :_},
        [],
        [:'$_']
      }
    ]

    # grab any random connection in the pool
    case :ets.select(state.available_connections, match_spec, 1) do
      {[{_old_key, pid} = pair], _continuation} ->
        state = remove_available_connection(pair, state)
        {:ok, {key, pid}, state}

      :'$end_of_table' ->
        {:empty, state}
    end
  end

  defp calc_used_connections(%State{} = state) do
    state.busy_size + state.available_size
  end

  def get_available_connection_by_pid(pid, %State{} = state) do
    match_spec = [
      {
        {:_, :'$1'},
        [
          {:==, :'$1', {:const, pid}}
        ],
        [:'$_']
      }
    ]

    :ets.select(state.available_connections, match_spec, 1)
  end

  def get_available_connection_by_key(key, %State{} = state) do
    match_spec = [
      {
        {:'$1', :_},
        [
          {:==, :'$1', {:const, key}}
        ],
        [:'$_']
      }
    ]

    :ets.select(state.available_connections, match_spec, 1)
  end

  def get_busy_connection_by_pid(pid, %State{} = state) do
    match_spec = [
      {
        {:_, {:'$1', :_}},
        [
          {:==, :'$1', {:const, pid}}
        ],
        [:'$_']
      }
    ]

    :ets.select(state.busy_connections, match_spec, 1)
  end

  def remove_busy_connection(pair, %State{} = state) do
    true = :ets.delete_object(state.busy_connections, pair)
    %{state | busy_size: state.busy_size - 1}
  end

  defp add_busy_connection(pair, %State{} = state) do
    true = :ets.insert(state.busy_connections, pair)
    %{state | busy_size: state.busy_size + 1}
  end

  def remove_available_connection(pair, %State{} = state) do
    true = :ets.delete_object(state.available_connections, pair)
    %{state | available_size: state.available_size - 1}
  end

  defp add_available_connection(pair, %State{} = state) do
    true = :ets.insert(state.available_connections, pair)
    %{state | available_size: state.available_size + 1}
  end
end
