defmodule TcgSimulatorWeb.GameLive do
  @moduledoc """
  Game board: hand, board, life, mana, turn/phase. Subscribes to match topic for updates.
  """
  use TcgSimulatorWeb, :live_view

  alias TcgSimulator.Game.Match
  alias TcgSimulator.MatchServer

  @impl true
  def mount(%{"id" => raw_id}, _session, socket) do
    match_id = to_string(raw_id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(TcgSimulator.PubSub, "match:#{match_id}")
      send(self(), :fetch_state)
    end

    player_id = get_player_id(socket)

    case Match.get_by_id(match_id) do
      {:ok, nil} ->
        {:ok,
         socket
         |> put_flash(:error, "Match not found")
         |> push_navigate(to: ~p"/")}

      {:ok, match} ->
        is_player = match.player1_id == player_id || match.player2_id == player_id

        if not is_player do
          {:ok,
           socket
           |> put_flash(:error, "You are not in this match")
           |> push_navigate(to: ~p"/")}
        else
          side = if match.player1_id == player_id, do: :player1, else: :player2

          socket =
            socket
            |> assign(:page_title, "Match")
            |> assign(:match_id, match_id)
            |> assign(:player_id, player_id)
            |> assign(:side, side)
            |> assign(:game_state, nil)
            |> assign(:error_toast, nil)

          {:ok, socket}
        end
    end
  end

  @impl true
  def handle_info(:fetch_state, socket) do
    match_id = socket.assigns.match_id
    state = MatchServer.get_state(match_id)
    {:noreply, assign(socket, :game_state, state)}
  catch
    :exit, _ ->
      {:noreply,
       assign(socket, :error_toast, "Game session unavailable. Please return to the lobby.")}
  end

  def handle_info({:game_updated, state}, socket) do
    {:noreply,
     socket
     |> assign(:game_state, state)
     |> assign(:error_toast, nil)}
  end

  def handle_info({:game_error, message}, socket) do
    {:noreply, assign(socket, :error_toast, message)}
  end

  @impl true
  def handle_event("end_turn", _params, socket) do
    match_id = socket.assigns.match_id
    case MatchServer.end_turn(match_id, socket.assigns.player_id) do
      :ok -> {:noreply, assign(socket, :error_toast, nil)}
      {:error, msg} -> {:noreply, assign(socket, :error_toast, msg)}
    end
  end

  def handle_event("play_card", %{"index" => index}, socket) do
    hand_index = if is_binary(index), do: String.to_integer(index), else: index
    match_id = socket.assigns.match_id

    case MatchServer.play_card(match_id, socket.assigns.player_id, hand_index, 0) do
      :ok ->
        {:noreply, assign(socket, :error_toast, nil)}

      {:error, msg} ->
        {:noreply, assign(socket, :error_toast, msg)}
    end
  catch
    :exit, {:noproc, _} ->
      {:noreply,
       assign(socket, :error_toast, "Game session unavailable. Please return to the lobby and start a new match.")}

    :exit, reason ->
      {:noreply,
       assign(socket, :error_toast, "Connection to game failed: #{inspect(reason)}")}
  end

  def handle_event("attack", %{"attacker_index" => ai, "target" => target}, socket) do
    attacker_index = if is_binary(ai), do: String.to_integer(ai), else: ai
    t = if target == "" or target == "player", do: nil, else: target
    match_id = socket.assigns.match_id

    case MatchServer.attack(match_id, socket.assigns.player_id, attacker_index, t) do
      :ok -> {:noreply, assign(socket, :error_toast, nil)}
      {:error, msg} -> {:noreply, assign(socket, :error_toast, msg)}
    end
  catch
    :exit, {:noproc, _} ->
      {:noreply,
       assign(socket, :error_toast, "Game session unavailable. Please return to the lobby and start a new match.")}

    :exit, reason ->
      {:noreply,
       assign(socket, :error_toast, "Connection to game failed: #{inspect(reason)}")}
  end

  defp get_player_id(socket) do
    case get_connect_params(socket) do
      %{"player_id" => id} when is_binary(id) -> id
      _ -> Ecto.UUID.generate()
    end
  end

  defp me(state, side), do: state[side]
  defp opponent(state, side), do: state[if(side == :player1, do: :player2, else: :player1)]
  defp my_turn?(state, side), do: state.current_turn == side

  defp card_emoji(name) when is_binary(name) do
    n = String.downcase(name)
    cond do
      String.contains?(n, "dragon") -> "🐉"
      String.contains?(n, "goblin") -> "👺"
      String.contains?(n, "knight") -> "⚔️"
      String.contains?(n, "flame") or String.contains?(n, "fire") -> "🔥"
      String.contains?(n, "frost") or String.contains?(n, "ice") -> "❄️"
      String.contains?(n, "stone") or String.contains?(n, "treant") or String.contains?(n, "guardian") -> "🪨"
      String.contains?(n, "berserker") or String.contains?(n, "war") -> "⚡"
      String.contains?(n, "mage") or String.contains?(n, "whelp") -> "✨"
      String.contains?(n, "elemental") -> "🌋"
      String.contains?(n, "imp") -> "😈"
      true -> "👹"
    end
  end
  defp card_emoji(_), do: "🃏"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <div class="min-h-screen bg-base-200 p-4 flex flex-col">
      <h1 class="text-xl font-bold mb-2">Match</h1>
      <p :if={@error_toast} class="text-error text-sm mb-2"><%= @error_toast %></p>

      <div :if={@game_state == nil} class="flex-1">
        <p>Loading game...</p>
      </div>

      <div :if={@game_state != nil} class="flex-1 flex flex-col gap-4">
        <% me = me(@game_state, @side) %>
        <% opp = opponent(@game_state, @side) %>
        <% my_turn = my_turn?(@game_state, @side) %>

        <% # Opponent area (top) %>
        <div class="bg-base-100 rounded-lg p-4 shadow">
          <p class="text-sm opacity-70">Opponent — Life: <%= opp.life %> ❤️ Mana: <%= opp.current_mana %>/<%= opp.max_mana %> ⬡</p>
          <div class="flex gap-3 mt-2 flex-wrap">
            <%= for {card, i} <- Enum.with_index(opp.board) do %>
              <div class="tcg-card flex-shrink-0 w-24 aspect-[5/7] rounded-xl border-2 border-base-content/20 bg-base-100 shadow-md overflow-hidden flex flex-col" title={card.name}>
                <div class="px-1.5 py-1 bg-base-300/80 border-b border-base-content/10 min-h-0">
                  <p class="text-[0.65rem] font-bold truncate text-center leading-tight"><%= card.name %></p>
                </div>
                <div class="flex-1 flex items-center justify-center bg-gradient-to-b from-base-200 to-base-300 text-3xl min-h-0">
                  <%= card_emoji(card.name) %>
                </div>
                <div class="px-1.5 py-1 bg-base-300/80 border-t border-base-content/10 flex justify-between items-center text-[0.65rem] font-semibold">
                  <span>⬡<%= card.cost %></span>
                  <span>⚔<%= card.attack %> ❤<%= card.current_health || card.health %></span>
                </div>
                <%= if my_turn && @game_state.phase == :attack do %>
                  <p class="text-[0.6rem] text-center text-primary font-medium py-0.5">(target)</p>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>

        <% # Turn / phase and actions %>
        <div class="flex items-center gap-4 flex-wrap">
          <span class="font-medium">
            <%= if my_turn do %>
              Your turn — Phase: <%= @game_state.phase %>
            <% else %>
              Opponent's turn
            <% end %>
          </span>
          <button
            :if={my_turn}
            phx-click="end_turn"
            class="btn btn-sm btn-primary"
          >
            <%= if @game_state.phase == :main, do: "Go to attack", else: "End turn" %>
          </button>
        </div>

        <% # My area (bottom) %>
        <div class="bg-base-100 rounded-lg p-4 shadow mt-auto">
          <p class="text-sm opacity-70">You — Life: <%= me.life %> ❤️ Mana: <%= me.current_mana %>/<%= me.max_mana %> ⬡</p>
          <p class="text-xs opacity-70 mt-1">Board:</p>
          <div class="flex gap-3 mt-1 flex-wrap">
            <%= for {card, i} <- Enum.with_index(me.board) do %>
              <div class="flex flex-col items-center gap-1">
                <div class="tcg-card flex-shrink-0 w-24 aspect-[5/7] rounded-xl border-2 border-base-content/20 bg-base-100 shadow-md overflow-hidden flex flex-col" title={card.name}>
                  <div class="px-1.5 py-1 bg-base-300/80 border-b border-base-content/10 min-h-0">
                    <p class="text-[0.65rem] font-bold truncate text-center leading-tight"><%= card.name %></p>
                  </div>
                  <div class="flex-1 flex items-center justify-center bg-gradient-to-b from-base-200 to-base-300 text-3xl min-h-0">
                    <%= card_emoji(card.name) %>
                  </div>
                  <div class="px-1.5 py-1 bg-base-300/80 border-t border-base-content/10 flex justify-between items-center text-[0.65rem] font-semibold">
                    <span>⬡<%= card.cost %></span>
                    <span>⚔<%= card.attack %> ❤<%= card.current_health || card.health %></span>
                  </div>
                </div>
                <%= if my_turn && @game_state.phase == :attack do %>
                  <div class="flex flex-wrap gap-1 justify-center">
                    <button
                      phx-click="attack"
                      phx-value-attacker_index={i}
                      phx-value-target="player"
                      class="btn btn-xs btn-primary"
                    >
                      ⚔️ Player
                    </button>
                    <%= for {_opp_card, ti} <- Enum.with_index(opp.board) do %>
                      <button
                        phx-click="attack"
                        phx-value-attacker_index={i}
                        phx-value-target={ti}
                        class="btn btn-xs btn-ghost"
                      >
                        Creature
                      </button>
                    <% end %>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
          <p class="text-xs opacity-70 mt-3">Hand:</p>
          <div class="flex gap-2 mt-1 flex-wrap">
            <%= for {card, i} <- Enum.with_index(me.hand) do %>
              <% playable = my_turn && @game_state.phase == :main && card.cost <= me.current_mana %>
              <%= if playable do %>
                <button
                  phx-click="play_card"
                  phx-value-index={i}
                  class="tcg-card flex-shrink-0 w-20 aspect-[5/7] rounded-xl border-2 border-primary/50 bg-base-100 shadow-md overflow-hidden flex flex-col hover:shadow-lg hover:scale-[1.02] hover:border-primary transition-all cursor-pointer text-left"
                  title={"Play #{card.name}"}
                >
                  <div class="px-1 py-0.5 bg-base-300/80 border-b border-base-content/10 min-h-0">
                    <p class="text-[0.6rem] font-bold truncate text-center leading-tight"><%= card.name %></p>
                  </div>
                  <div class="flex-1 flex items-center justify-center bg-gradient-to-b from-base-200 to-base-300 text-2xl min-h-0">
                    <%= card_emoji(card.name) %>
                  </div>
                  <div class="px-1 py-0.5 bg-base-300/80 border-t border-base-content/10 flex justify-between items-center text-[0.6rem] font-semibold">
                    <span>⬡<%= card.cost %></span>
                    <span>⚔<%= card.attack %> ❤<%= card.health %></span>
                  </div>
                </button>
              <% else %>
                <div class="tcg-card flex-shrink-0 w-20 aspect-[5/7] rounded-xl border-2 border-base-content/20 bg-base-100 shadow overflow-hidden flex flex-col opacity-75" title={card.name}>
                  <div class="px-1 py-0.5 bg-base-300/80 border-b border-base-content/10 min-h-0">
                    <p class="text-[0.6rem] font-bold truncate text-center leading-tight"><%= card.name %></p>
                  </div>
                  <div class="flex-1 flex items-center justify-center bg-gradient-to-b from-base-200 to-base-300 text-2xl min-h-0">
                    <%= card_emoji(card.name) %>
                  </div>
                  <div class="px-1 py-0.5 bg-base-300/80 border-t border-base-content/10 flex justify-between items-center text-[0.6rem] font-semibold">
                    <span>⬡<%= card.cost %></span>
                    <span>⚔<%= card.attack %> ❤<%= card.health %></span>
                  </div>
                </div>
              <% end %>
            <% end %>
          </div>
        </div>

        <p :if={@game_state.winner} class="text-lg font-bold text-center mt-4">
          <%= if @game_state.winner == @side, do: "You win!", else: "You lose!" %>
        </p>
      </div>
    </div>
    """
  end
end
