defmodule TcgSimulator.Game do
  @moduledoc """
  Ash domain for TCG game data: card templates, decks, and matches.
  """
  use Ash.Domain, otp_app: :tcg_simulator

  resources do
    resource TcgSimulator.Game.CardTemplate
    resource TcgSimulator.Game.Deck
    resource TcgSimulator.Game.DeckCard
    resource TcgSimulator.Game.Match
  end
end
