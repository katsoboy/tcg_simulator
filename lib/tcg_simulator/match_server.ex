defmodule TcgSimulator.MatchServer do
  @moduledoc """
  GenServer holding runtime game state for one match. Handles draw, play, attack, end turn.
  Broadcasts state to PubSub on every change.
  """
  use GenServer

  alias TcgSimulator.Game.{Match, Deck}
  alias TcgSimulator.PubSub

  @initial_life 20
  @max_mana 10
  @initial_hand_size 5

  def start_link(opts) do
    match_id = opts |> Keyword.fetch!(:match_id) |> to_string()
    GenServer.start_link(__MODULE__, [match_id: match_id], name: via_tuple(match_id))
  end

  def via_tuple(match_id) do
    key = to_string(match_id)
    {:via, Registry, {TcgSimulator.MatchRegistry, key}}
  end

  def get_state(match_id) do
    GenServer.call(via_tuple(match_id), :get_state)
  end

  def end_turn(match_id, player_id) do
    GenServer.call(via_tuple(match_id), {:end_turn, player_id})
  end

  def play_card(match_id, player_id, hand_index, board_position) do
    GenServer.call(via_tuple(match_id), {:play_card, player_id, hand_index, board_position})
  end

  def attack(match_id, attacker_id, attacker_board_index, target \\ nil) do
    GenServer.call(via_tuple(match_id), {:attack, attacker_id, attacker_board_index, target})
  end

  @impl true
  def init(opts) do
    match_id = opts |> Keyword.fetch!(:match_id) |> to_string()

    case load_match_and_decks(match_id) do
      {:ok, match, deck1_cards, deck2_cards} ->
        state = build_initial_state(match_id, match, deck1_cards, deck2_cards)
        broadcast(match_id, state)
        {:ok, state}

      {:error, _} ->
        {:stop, :load_failed}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:end_turn, player_id}, _from, state) do
    if state.winner do
      {:reply, {:error, "Game over"}, state}
    else
      case do_end_turn(state, player_id) do
        {:ok, new_state} ->
          broadcast(state.match_id, new_state)
          {:reply, :ok, new_state}

        {:error, msg} ->
          {:reply, {:error, msg}, state}
      end
    end
  end

  def handle_call({:play_card, player_id, raw_hand_index, _board_position}, _from, state) do
    hand_index = normalize_index(raw_hand_index)
    if state.winner do
      {:reply, {:error, "Game over"}, state}
    else
      case do_play_card(state, player_id, hand_index) do
        {:ok, new_state} ->
          broadcast(state.match_id, new_state)
          {:reply, :ok, new_state}

        {:error, msg} ->
          {:reply, {:error, msg}, state}
      end
    end
  end

  def handle_call({:attack, attacker_id, raw_attacker_index, target}, _from, state) do
    attacker_board_index = normalize_index(raw_attacker_index)
    if state.winner do
      {:reply, {:error, "Game over"}, state}
    else
      case do_attack(state, attacker_id, attacker_board_index, target) do
        {:ok, new_state} ->
          broadcast(state.match_id, new_state)
          {:reply, :ok, new_state}

        {:error, msg} ->
          {:reply, {:error, msg}, state}
      end
    end
  end

  defp load_match_and_decks(match_id) do
    with {:ok, match} <- Match.get_by_id(match_id),
         {:ok, [deck1, deck2]} <- load_two_decks() do
      deck1_cards = deck_cards_with_templates(deck1)
      deck2_cards = deck_cards_with_templates(deck2)
      {:ok, match, deck1_cards, deck2_cards}
    else
      _ -> {:error, :load_failed}
    end
  end

  defp load_two_decks do
    case Ash.read(Deck) do
      {:ok, decks} when length(decks) >= 2 ->
        {:ok, Enum.take(decks, 2)}

      _ ->
        {:error, :no_decks}
    end
  end

  defp deck_cards_with_templates(deck) do
    deck
    |> Ash.load!(:deck_cards)
    |> Map.get(:deck_cards, [])
    |> Ash.load!(:card_template)
    |> Enum.flat_map(fn dc ->
      template = dc.card_template
      List.duplicate(template, dc.quantity || 1)
    end)
  end

  defp build_initial_state(match_id, match, deck1_cards, deck2_cards) do
    deck1 = shuffle(Enum.map(deck1_cards, &template_to_card/1))
    deck2 = shuffle(Enum.map(deck2_cards, &template_to_card/1))

    {p1_hand, p1_deck} = draw_n(deck1, @initial_hand_size)
    {p2_hand, p2_deck} = draw_n(deck2, @initial_hand_size)

    # Player 1 gets 1 mana on their first turn
    %{
      match_id: match_id,
      player1_id: match.player1_id,
      player2_id: match.player2_id,
      current_turn: :player1,
      phase: :main,
      turn_number: 1,
      winner: nil,
      player1: %{
        life: @initial_life,
        max_mana: 1,
        current_mana: 1,
        hand: p1_hand,
        board: [],
        deck: p1_deck,
        discard: []
      },
      player2: %{
        life: @initial_life,
        max_mana: 0,
        current_mana: 0,
        hand: p2_hand,
        board: [],
        deck: p2_deck,
        discard: []
      }
    }
  end

  defp template_to_card(template) do
    %{
      id: Ecto.UUID.generate(),
      template_id: template.id,
      name: template.name,
      cost: template.cost,
      attack: template.attack,
      health: template.health,
      current_health: template.health
    }
  end

  defp shuffle(list), do: Enum.shuffle(list)

  defp draw_n(deck, n) do
    {draw, rest} = Enum.split(deck, n)
    {draw, rest}
  end

  defp do_end_turn(state, player_id) do
    current = current_player_key(state)
    player_key = if state.player1_id == player_id, do: :player1, else: :player2
    if player_key != current do
      {:error, "Not your turn"}
    else
      if state.phase == :main do
        # Go to attack phase
        {:ok, Map.put(state, :phase, :attack)}
      else
        # End turn: switch player, draw 1, gain max mana
        next_key = if current == :player1, do: :player2, else: :player1
        next_state =
          state
          |> Map.put(:current_turn, next_key)
          |> Map.put(:phase, :main)
          |> Map.put(:turn_number, state.turn_number + 1)

        next_state =
          case next_state[next_key].deck do
            [h | t] ->
              next_state
              |> put_in([next_key, :hand], next_state[next_key].hand ++ [h])
              |> put_in([next_key, :deck], t)
            [] ->
              next_state
          end

        new_max = min(next_state[next_key].max_mana + 1, @max_mana)
        next_state =
          next_state
          |> put_in([next_key, :max_mana], new_max)
          |> put_in([next_key, :current_mana], new_max)

        {:ok, next_state}
      end
    end
  end

  defp current_player_key(state), do: state.current_turn

  defp normalize_index(idx) when is_binary(idx) do
    case Integer.parse(idx) do
      {n, _} -> n
      :error -> -1
    end
  end
  defp normalize_index(idx) when is_integer(idx), do: idx
  defp normalize_index(_), do: -1

  defp do_play_card(state, player_id, hand_index) do
    player_key = if state.player1_id == player_id, do: :player1, else: :player2
    if state.current_turn != player_key do
      {:error, "Not your turn"}
    else
      if state.phase != :main do
        {:error, "Can only play creatures in main phase"}
      else
        hand = state[player_key].hand
        if hand_index < 0 or hand_index >= length(hand) do
          {:error, "Invalid card"}
        else
          card = Enum.at(hand, hand_index)
          if card.cost > state[player_key].current_mana do
            {:error, "Not enough mana"}
          else
            new_hand = List.delete_at(hand, hand_index)
            new_board = state[player_key].board ++ [Map.put(card, :current_health, card.health)]
            new_mana = state[player_key].current_mana - card.cost
            new_state =
              state
              |> put_in([player_key, :hand], new_hand)
              |> put_in([player_key, :board], new_board)
              |> put_in([player_key, :current_mana], new_mana)
            {:ok, new_state}
          end
        end
      end
    end
  end

  defp do_attack(state, attacker_id, attacker_board_index, target) do
    attacker_key = if state.player1_id == attacker_id, do: :player1, else: :player2
    if state.current_turn != attacker_key do
      {:error, "Not your turn"}
    else
      if state.phase != :attack do
        {:error, "Can only attack in attack phase"}
      else
        board = state[attacker_key].board
        if attacker_board_index < 0 or attacker_board_index >= length(board) do
          {:error, "Invalid attacker"}
        else
          attacker = Enum.at(board, attacker_board_index)
          defender_key = if attacker_key == :player1, do: :player2, else: :player1
          defender_board = state[defender_key].board

          if target == nil or target == "" do
            # Attack opponent directly
            new_life = state[defender_key].life - attacker.attack
            new_state = put_in(state, [defender_key, :life], new_life)
            new_state = maybe_set_winner(new_state)
            if new_state.winner, do: persist_winner(new_state)
            {:ok, new_state}
          else
            # Target creature (target is board index on defender)
            target_index = normalize_index(target)
            if target_index < 0 or target_index >= length(defender_board) do
              {:error, "Invalid target"}
            else
              target_creature = Enum.at(defender_board, target_index)
              new_attacker_health = attacker.current_health - target_creature.attack
              new_target_health = target_creature.current_health - attacker.attack

              new_state = state
              new_state = update_in(new_state, [attacker_key, :board, attacker_board_index], &Map.put(&1, :current_health, new_attacker_health))
              new_state = update_in(new_state, [defender_key, :board, target_index], &Map.put(&1, :current_health, new_target_health))

              # Remove dead creatures
              new_state = remove_dead_creatures(new_state, attacker_key)
              new_state = remove_dead_creatures(new_state, defender_key)
              {:ok, new_state}
            end
          end
        end
      end
    end
  end

  defp remove_dead_creatures(state, player_key) do
    board = state[player_key].board
    {alive, dead} = Enum.split_with(board, fn c -> (c.current_health || c.health) > 0 end)
    discard = state[player_key].discard ++ dead
    put_in(state, [player_key], state[player_key]
      |> Map.put(:board, alive)
      |> Map.put(:discard, discard))
  end

  defp maybe_set_winner(state) do
    p1_life = state.player1.life
    p2_life = state.player2.life
    cond do
      p1_life <= 0 -> Map.put(state, :winner, :player2)
      p2_life <= 0 -> Map.put(state, :winner, :player1)
      true -> state
    end
  end

  defp broadcast(match_id, state) do
    topic = "match:#{to_string(match_id)}"
    Phoenix.PubSub.broadcast(PubSub, topic, {:game_updated, state})
  end

  defp persist_winner(state) do
    winner_id = if state.winner == :player1, do: state.player1_id, else: state.player2_id

    case Match.get_by_id(state.match_id) do
      {:ok, match} when not is_nil(match) ->
        Ash.Changeset.for_update(match, :update, %{status: :finished, winner_id: winner_id})
        |> Ash.update()

      _ ->
        :ok
    end
  end
end
