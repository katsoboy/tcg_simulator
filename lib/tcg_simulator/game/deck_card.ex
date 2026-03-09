defmodule TcgSimulator.Game.DeckCard do
  @moduledoc """
  Join resource: links a deck to card templates with a quantity (how many of that card in the deck).
  """
  use Ash.Resource,
    domain: TcgSimulator.Game,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "deck_cards"
    repo TcgSimulator.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :quantity, :integer, allow_nil?: false, default: 1
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :deck, TcgSimulator.Game.Deck, allow_nil?: false
    belongs_to :card_template, TcgSimulator.Game.CardTemplate, allow_nil?: false
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:quantity]
      argument :deck_id, :uuid, allow_nil?: false
      argument :card_template_id, :uuid, allow_nil?: false
      change manage_relationship(:deck_id, :deck, type: :append)
      change manage_relationship(:card_template_id, :card_template, type: :append)
      primary? true
    end
  end
end
