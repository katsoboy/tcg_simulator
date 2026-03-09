# Script for populating the database. Run with: mix run priv/repo/seeds.exs
#
# Seeds default card templates and two default decks (Starter Red, Starter Blue)
# for the TCG simulator.

alias TcgSimulator.Game

# Only seed if no card templates exist
case Ash.read(Game.CardTemplate) do
  {:ok, []} ->
    # Card templates: name, cost, attack, health
    templates = [
      {"Goblin Scout", 1, 1, 1},
      {"Fire Elemental", 2, 2, 2},
      {"Stone Guardian", 2, 1, 3},
      {"Flame Imp", 2, 3, 1},
      {"Knight Errant", 3, 2, 3},
      {"Berserker", 3, 4, 2},
      {"Dragon Whelp", 4, 3, 3},
      {"Ancient Treant", 4, 2, 5},
      {"War Golem", 5, 4, 4},
      {"Frost Mage", 3, 2, 2},
      {"Water Spirit", 2, 2, 1},
      {"Ice Guardian", 4, 2, 4},
      {"Storm Caller", 3, 3, 2},
      {"Tidal Wave", 5, 3, 4},
      {"Arcane Owl", 1, 1, 2}
    ]

    created_templates =
      for {name, cost, attack, health} <- templates do
        {:ok, card} =
          Game.CardTemplate
          |> Ash.Changeset.for_create(:create, %{name: name, cost: cost, attack: attack, health: health})
          |> Ash.create()

        card
      end

    # Create two default decks using the first 10 and last 10 templates (overlapping in the middle)
    red_templates = Enum.take(created_templates, 10)
    blue_templates = Enum.take(created_templates, -10)

    {:ok, red_deck} =
      Game.Deck
      |> Ash.Changeset.for_create(:create, %{name: "Starter Red"})
      |> Ash.create()

    {:ok, blue_deck} =
      Game.Deck
      |> Ash.Changeset.for_create(:create, %{name: "Starter Blue"})
      |> Ash.create()

    for card <- red_templates do
      Game.DeckCard
      |> Ash.Changeset.for_create(:create, %{
        quantity: 2,
        deck_id: red_deck.id,
        card_template_id: card.id
      })
      |> Ash.create!()
    end

    for card <- blue_templates do
      Game.DeckCard
      |> Ash.Changeset.for_create(:create, %{
        quantity: 2,
        deck_id: blue_deck.id,
        card_template_id: card.id
      })
      |> Ash.create!()
    end

    IO.puts("Seeded #{length(created_templates)} card templates and 2 default decks (Starter Red, Starter Blue).")

  {:ok, _existing} ->
    IO.puts("Card templates already exist, skipping seeds.")

  {:error, e} ->
    IO.warn("Seeds error: #{inspect(e)}")
end
