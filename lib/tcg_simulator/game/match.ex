defmodule TcgSimulator.Game.Match do
  @moduledoc """
  A 1v1 match: has a unique code for joining, two player slots, and status.
  Runtime game state lives in MatchServer GenServer, not here.
  """
  use Ash.Resource,
    domain: TcgSimulator.Game,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "matches"
    repo TcgSimulator.Repo
  end

  identities do
    identity :unique_code, [:code]
  end

  attributes do
    uuid_primary_key :id
    attribute :code, :string, allow_nil?: false
    attribute :status, :atom, allow_nil?: false, default: :waiting, constraints: [one_of: [:waiting, :in_progress, :finished]]
    attribute :player1_id, :string, allow_nil?: false
    attribute :player2_id, :string, allow_nil?: true
    attribute :winner_id, :string, allow_nil?: true
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:player1_id]
      change TcgSimulator.Game.Changes.GenerateMatchCode
      change set_attribute(:status, :waiting)
      primary? true
    end

    update :update do
      accept [:status, :player2_id, :winner_id]
      primary? true
    end

    read :by_code do
      get? true
      argument :code, :string, allow_nil?: false

      filter expr(code == ^arg(:code))
    end
  end

  code_interface do
    define :create_match, action: :create, args: [:player1_id]
    define :get_by_id, action: :read, get_by: [:id]
    define :get_by_code, action: :by_code, args: [:code]
    define :update_match, action: :update
  end
end
