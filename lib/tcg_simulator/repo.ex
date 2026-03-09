defmodule TcgSimulator.Repo do
  use Ecto.Repo,
    otp_app: :tcg_simulator,
    adapter: Ecto.Adapters.Postgres

  use AshPostgres.Repo, otp_app: :tcg_simulator, define_ecto_repo?: false

  def installed_extensions do
    ["ash-functions"]
  end

  def min_pg_version do
    %Version{major: 14, minor: 0, patch: 0}
  end
end
