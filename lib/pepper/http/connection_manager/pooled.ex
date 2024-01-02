defmodule Pepper.HTTP.ConnectionManager.Pooled do
  defmodule State do
    defstruct [
      busy_connections: nil,
      available_connections: nil,
      default_lifespan: nil,
      pool_size: nil,
      total_size: 0,
      busy_size: 0,
      available_size: 0,
    ]

    @type t :: %__MODULE__{
      busy_connections: :ets.table(),
      available_connections: :ets.table(),
      total_size: non_neg_integer(),
      busy_size: non_neg_integer(),
      available_size: non_neg_integer(),
    }
  end

  @moduledoc """
  Connection pool implementation

  Usage:

      # Add the manager to your supervision tree:
      children = [
        ...
        {Pepper.HTTP.ConnectionManager.Pooled, [
          # Pool Options
          [pool_size: 10],

          # Process Options - see GenServer for process options
          [name: :my_pool_name],
        ]},
      ]
  """

  require Logger

  use GenServer

  alias Pepper.HTTP.ConnectionManager.PooledConnection
  alias Pepper.HTTP.Request
  alias Pepper.HTTP.Response
  alias Pepper.HTTP.CheckoutError
  alias Pepper.HTTP.ReceiveError
  alias Pepper.HTTP.RequestError
  alias Pepper.HTTP.SendError
  alias Pepper.HTTP.ConnectError

  @type conn_key :: {scheme::atom(), host::String.t(), port::integer(), Keyword.t()}

  @type connection_id :: GenServer.server()

  @type start_option :: {:pool_size, integer()}
                      | {:default_lifespan, non_neg_integer()}

  @type start_options :: [start_option()]

  @type error_reasons :: ReceiveError.t()
                       | RequestError.t()
                       | SendError.t()
                       | ConnectError.t()
                       | CheckoutError.t()

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

  @spec request(connection_id(), Request.t()) :: {:ok, Response.t()} | {:error, error_reasons()}
  def request(server, %Pepper.HTTP.Request{} = request) do
    connect_timeout = Keyword.fetch!(request.options, :connect_timeout)
    recv_timeout = Keyword.fetch!(request.options, :recv_timeout)
    timeout = connect_timeout + recv_timeout + 1000
    case GenServer.call(server, {:request, request}, timeout) do
      {:ok, _resp} = res ->
        res

      {:error, _reason} = err ->
        err

      {:exception, ex, stacktrace} ->
        reraise ex, stacktrace
    end
  end

  def close_all(server, reason \\ :normal, timeout \\ :infinity) do
    GenServer.call(server, {:close_all, reason}, timeout)
  end

  @spec get_stats(connection_id(), timeout()) :: map()
  def get_stats(server, timeout \\ 15_000) do
    GenServer.call(server, :get_stats, timeout)
  end

  defdelegate stop(pid, reason \\ :normal), to: GenServer

  defp patch_start_options(options) when is_list(options) do
    options
    |> Keyword.put_new(:pool_size, 100)
    |> Keyword.put_new(:default_lifespan, 30_000)
    |> validate_start_options([])
  end

  defp validate_start_options([], acc) do
    {:ok, Enum.reverse(acc)}
  end

  defp validate_start_options(
    [{:pool_size, pool_size} = pair | rest],
    acc
  ) when is_integer(pool_size) and pool_size > 0 do
    validate_start_options(rest, [pair | acc])
  end

  defp validate_start_options(
    [{:default_lifespan, lifespan} = pair | rest],
    acc
  ) when is_integer(lifespan) and lifespan > 0 do
    validate_start_options(rest, [pair | acc])
  end

  defp validate_start_options([value | _rest], _acc) do
    {:error, {:unexpected_start_option, value}}
  end

  @spec start(start_options(), GenServer.options()) :: GenServer.on_start()
  def start(opts, process_options \\ []) when is_list(opts) and is_list(process_options) do
    case patch_start_options(opts) do
      {:ok, opts} ->
        GenServer.start(__MODULE__, opts, process_options)

      {:error, _} = err ->
        err
    end
  end

  @spec start_link(start_options(), GenServer.options()) :: GenServer.on_start()
  def start_link(opts, process_options \\ []) when is_list(opts) and is_list(process_options) do
    case patch_start_options(opts) do
      {:ok, opts} ->
        GenServer.start_link(__MODULE__, opts, process_options)

      {:error, _} = err ->
        err
    end
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    available_connections = :ets.new(:available_connections, [:bag, :private])
    busy_connections = :ets.new(:busy_connections, [:bag, :private])

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
  def terminate(_reason, %State{} = state) do
    # Process.flag(:trap_exit, false)

    :ets.delete(state.busy_connections)
    :ets.delete(state.available_connections)
    :ok
  end

  @impl true
  def handle_call(:get_stats, _from, %State{} = state) do
    stats = %{
      total_size: state.total_size,
      pool_size: state.pool_size,
      busy_size: state.busy_size,
      available_size: state.available_size,
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call({:request, %Pepper.HTTP.Request{} = request}, from, %State{} = state) do
    start_time = System.monotonic_time(:microsecond)
    request = %{request | time: start_time}
    connect_options = Keyword.get(request.options, :connect_options, [])

    key = {request.scheme, request.uri.host, request.uri.port, connect_options}
    case checkout_connection(key, state) do
      {:empty, state} ->
        ex = %CheckoutError{
          message: "Could not checkout connection",
          reason: :no_available_connections,
        }
        {:reply, {:error, ex}, state}

      {:ok, {^key, pid}, state} when is_pid(pid) ->
        # submit the request to the pooled connection
        :ok = PooledConnection.request(pid, request, from)
        #
        state = add_busy_connection({key, {pid, from}}, state)
        {:noreply, state}

      {:error, reason, state} ->
        ex = %CheckoutError{
          message: "Could not checkout connection",
          reason: reason,
        }
        {:reply, {:error, ex}, state}
    end
  end

  @impl true
  def handle_call({:close_all, reason}, _from, %State{} = state) do
    %State{} = state = do_close_all(reason, state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:checkin, pid, reason}, %State{} = state) do
    case get_busy_connection_by_pid(pid, state) do
      {[{key, {^pid, _from}} = pair], _continuation} ->
        state = remove_busy_connection(pair, state)
        state = add_available_connection({key, pid}, state)
        case reason do
          :ok ->
            {:noreply, state}

          {:error, _reason} ->
            {:noreply, state}

          {:exception, _ex, _stacktrace} ->
            {:noreply, state}
        end

      :'$end_of_table' ->
        Logger.warning "unexpected checkin", pid: inspect(pid), reason: inspect(reason)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, %State{} = state) do
    case get_busy_connection_by_pid(pid, state) do
      {[{_key, {^pid, from}} = pair], _continuation} ->
        state = remove_busy_connection(pair, state)
        state = %{state | total_size: state.total_size - 1}
        GenServer.reply(from, {:error, reason})
        {:noreply, state}

      :'$end_of_table' ->
        case get_available_connection_by_pid(pid, state) do
          {[{_key, ^pid} = pair], _continuation} ->
            state = %{state | total_size: state.total_size - 1}
            state = remove_available_connection(pair, state)
            {:noreply, state}

          :'$end_of_table' ->
            Logger.error "an unknown process has terminated", reason: inspect(reason)
            #{:stop, {:unexpected_exit, pid}, state}
            {:noreply, state}
        end
    end
  end

  @spec checkout_connection(conn_key(), State.t()) ::
    {:ok, any(), State.t()}
    | {:error, any(), State.t()}
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
      case PooledConnection.start_link(self(), make_ref(), [lifespan: state.default_lifespan]) do
        {:ok, pid} ->
          {:ok, {key, pid}, %{state | total_size: state.total_size + 1}}

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

  defp do_close_all(reason, %State{} = state) do
    state = close_all_busy_connections(reason, state)
    state = close_all_available_connections(reason, state)
    state
  end

  defp close_all_busy_connections(reason, state) do
    reduce_ets_table(state.busy_connections, state, fn {_key, {pid, _from}}, state ->
      :ok = PooledConnection.schedule_stop(pid, reason)
      state
    end)
  end

  defp close_all_available_connections(reason, state) do
    reduce_ets_table(state.available_connections, state, fn {_key, pid}, state ->
      :ok = PooledConnection.schedule_stop(pid, reason)
      state
    end)
  end

  defp reduce_ets_table(table, acc, callback) do
    true = :ets.safe_fixtable(table, true)
    try do
      do_reduce_ets_table(:ets.first(table), table, acc, callback)
    after
      true = :ets.safe_fixtable(table, false)
    end
  end

  defp do_reduce_ets_table(:"$end_of_table", _table, acc, _callback) do
    acc
  end

  defp do_reduce_ets_table(key, table, acc, callback) do
    acc =
      case :ets.lookup(table, key) do
        [] ->
          acc

        [{^key, _value} = pair] ->
          callback.(pair, acc)
      end

    do_reduce_ets_table(:ets.next(table, key), table, acc, callback)
  end
end
