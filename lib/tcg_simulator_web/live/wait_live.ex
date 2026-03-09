defmodule TcgSimulatorWeb.WaitLive do
  @moduledoc """
  Waiting room: show match code and wait for opponent. When both players are present,
  subscribe to match topic and redirect to game when match starts.
  """
  use TcgSimulatorWeb, :live_view

  alias TcgSimulator.Game.Match

  @impl true
  def mount(%{"id" => raw_id}, _session, socket) do
    id = to_string(raw_id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(TcgSimulator.PubSub, "match:#{id}")
    end

    case Match.get_by_id(id) do
      {:ok, nil} ->
        {:ok,
         socket
         |> put_flash(:error, "Match not found")
         |> push_navigate(to: ~p"/")}

      {:ok, match} ->
        player_id = get_player_id(socket)
        is_player = match.player1_id == player_id || match.player2_id == player_id

        if not is_player do
          {:ok,
           socket
           |> put_flash(:error, "You are not in this match")
           |> push_navigate(to: ~p"/")}
        else
          socket =
            socket
            |> assign(:page_title, "Waiting for opponent")
            |> assign(:match_id, id)
            |> assign(:match, match)
            |> assign(:code, match.code)
            |> assign(:player_id, player_id)
            |> assign(:status, match.status)

          # If match already in progress (e.g. we're player2 who just joined), go to game
          if match.status == :in_progress do
            {:ok,
             socket
             |> push_navigate(to: ~p"/matches/#{id}/play")}
          else
            {:ok, socket}
          end
        end
    end
  end

  @impl true
  def handle_event("copy_code", _params, socket) do
    {:noreply, put_flash(socket, :info, "Code copied to clipboard!")}
  end

  @impl true
  def handle_info({:game_started, _match_id}, socket) do
    {:noreply,
     push_navigate(socket, to: ~p"/matches/#{socket.assigns.match_id}/play")}
  end

  @impl true
  def handle_info({:match_updated, match}, socket) do
    if match.status == :in_progress do
      {:noreply,
       push_navigate(socket, to: ~p"/matches/#{socket.assigns.match_id}/play")}
    else
      {:noreply, assign(socket, :match, match)}
    end
  end

  defp get_player_id(socket) do
    case get_connect_params(socket) do
      %{"player_id" => id} when is_binary(id) -> id
      _ -> Ecto.UUID.generate()
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <div class="min-h-screen flex flex-col items-center justify-center bg-base-200 p-4">
      <h1 class="text-2xl font-bold mb-4">Waiting for opponent</h1>
      <p class="mb-4">Share this code with your opponent:</p>
      <div class="bg-base-100 p-6 rounded-lg shadow-lg text-center">
        <p class="text-4xl font-mono font-bold tracking-widest mb-2">{@code}</p>
        <button
          id="copy-code-btn"
          phx-hook="CopyCode"
          phx-click="copy_code"
          data-code={@code}
          class="btn btn-sm btn-ghost"
        >
          Copy code
        </button>
      </div>
      <p :if={@match.player2_id} class="mt-4 text-success">Opponent joined! Starting game...</p>
      <p :if={!@match.player2_id} class="mt-4 opacity-70">Waiting for another player to join...</p>
    </div>
    """
  end
end
