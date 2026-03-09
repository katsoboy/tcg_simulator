defmodule TcgSimulator.Game.Changes.GenerateMatchCode do
  @moduledoc """
  Sets a unique 6-character alphanumeric code on the match when creating.
  """
  use Ash.Resource.Change

  @chars "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" |> String.graphemes()

  @impl true
  def change(changeset, _opts, _context) do
    if Ash.Changeset.changing_attribute?(changeset, :code) do
      changeset
    else
      code = generate_code()
      Ash.Changeset.force_change_attribute(changeset, :code, code)
    end
  end

  defp generate_code do
    1..6
    |> Enum.map(fn _ -> Enum.random(@chars) end)
    |> Enum.join()
  end
end
