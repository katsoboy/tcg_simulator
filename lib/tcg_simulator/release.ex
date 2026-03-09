defmodule TcgSimulator.Release do
  @moduledoc """
  Used for executing DB release tasks when starting the app in production.
  """
  @app :tcg_simulator

  def migrate do
    load_app()
    Application.ensure_all_started(:ssl)

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def seed do
    load_app()
    Application.ensure_all_started(@app)
    TcgSimulator.Release.Seeds.run()
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end

defmodule TcgSimulator.Release.Seeds do
  @moduledoc """
  Seeds the database (card templates and default decks). Safe to run multiple times.
  """
  alias TcgSimulator.Game

  def run do
    case Ash.read(Game.CardTemplate) do
      {:ok, []} ->
        seed_templates_and_decks()

      _ ->
        :ok
    end
  end

  defp seed_templates_and_decks do
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

    created =
      Enum.map(templates, fn {name, cost, attack, health} ->
        {:ok, t} =
          Ash.Changeset.for_create(Game.CardTemplate, :create, %{
            name: name,
            cost: cost,
            attack: attack,
            health: health
          })
          |> Ash.create()

        t
      end)

    template_ids = Enum.map(created, & &1.id)

    # Starter Red deck
    {:ok, red} =
      Ash.Changeset.for_create(Game.Deck, :create, %{name: "Starter Red"})
      |> Ash.create()

    red_cards = Enum.take_random(template_ids, 25)
    for tid <- red_cards do
      Ash.Changeset.for_create(Game.DeckCard, :create, %{
        deck_id: red.id,
        card_template_id: tid,
        quantity: 1
      })
      |> Ash.create()
    end

    # Starter Blue deck
    {:ok, blue} =
      Ash.Changeset.for_create(Game.Deck, :create, %{name: "Starter Blue"})
      |> Ash.create()

    blue_cards = Enum.take_random(template_ids, 25)
    for tid <- blue_cards do
      Ash.Changeset.for_create(Game.DeckCard, :create, %{
        deck_id: blue.id,
        card_template_id: tid,
        quantity: 1
      })
      |> Ash.create()
    end

    :ok
  end
end
