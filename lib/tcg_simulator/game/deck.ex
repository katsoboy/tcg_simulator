defmodule TcgSimulator.Game.Deck do
  @moduledoc """
  Named deck: a collection of card templates (via DeckCard) used as default decks for matches.
  """
  use Ash.Resource,
    domain: TcgSimulator.Game,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "decks"
    repo TcgSimulator.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :deck_cards, TcgSimulator.Game.DeckCard
    many_to_many :card_templates, TcgSimulator.Game.CardTemplate,
      through: TcgSimulator.Game.DeckCard,
      source_attribute_on_join_resource: :deck_id,
      destination_attribute_on_join_resource: :card_template_id
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name]
      primary? true
    end

    update :update do
      accept [:name]
      primary? true
    end
  end
end
