defmodule TcgSimulator.MatchSupervisor do
  @moduledoc """
  DynamicSupervisor that starts one MatchServer per match when the match has two players.
  """
  use DynamicSupervisor

  alias TcgSimulator.MatchServer

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_match(match_id) when is_binary(match_id) do
    start_match(match_id, [])
  end

  def start_match(match_id, opts) do
    child_spec = {MatchServer, [match_id: match_id] ++ opts}
    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end
end
