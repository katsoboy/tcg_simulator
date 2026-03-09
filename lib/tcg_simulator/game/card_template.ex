defmodule TcgSimulator.Game.CardTemplate do
  @moduledoc """
  Static card definition. No game state — used to build decks and runtime card instances.
  """
  use Ash.Resource,
    domain: TcgSimulator.Game,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "card_templates"
    repo TcgSimulator.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :cost, :integer, allow_nil?: false, default: 0
    attribute :attack, :integer, allow_nil?: false, default: 0
    attribute :health, :integer, allow_nil?: false, default: 0
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :cost, :attack, :health]
      primary? true
    end

    update :update do
      accept [:name, :cost, :attack, :health]
      primary? true
    end
  end
end
