defmodule TcgSimulatorWeb.LobbyLive do
  @moduledoc """
  Lobby: create a private match or join with a code.
  """
  use TcgSimulatorWeb, :live_view

  alias TcgSimulator.Game.Match

  @impl true
  def mount(_params, _session, socket) do
    player_id = get_player_id(socket)

    socket =
      socket
      |> assign(:page_title, "TCG Simulator – Lobby")
      |> assign(:player_id, player_id)
      |> assign(:join_code, "")
      |> assign(:join_error, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("create_match", _params, socket) do
    player_id = socket.assigns.player_id

    case TcgSimulator.Game.Match
         |> Ash.Changeset.for_create(:create, %{player1_id: player_id})
         |> Ash.create() do
      {:ok, match} ->
        match_id_str = to_string(match.id)
        {:noreply,
         socket
         |> put_flash(:info, "Match created. Share the code with your opponent.")
         |> push_navigate(to: ~p"/matches/#{match_id_str}/wait")}

      {:error, error} ->
        message =
          if is_exception(error), do: Exception.message(error), else: inspect(error)

        {:noreply,
         socket
         |> put_flash(:error, "Could not create match: #{message}")
         |> assign(:join_error, "Create failed")}
    end
  end

  @impl true
  def handle_event("join_match", %{"code" => code}, socket) when is_binary(code) do
    code = String.upcase(String.trim(code))
    player_id = socket.assigns.player_id

    if code == "" do
      {:noreply,
       socket
       |> assign(:join_error, "Enter a match code")
       |> assign(:join_code, code)}
    else
      case Match.get_by_code(code) do
        {:ok, nil} ->
          {:noreply,
           socket
           |> assign(:join_error, "Match not found")
           |> assign(:join_code, code)}

        {:ok, match} ->
          if match.player2_id do
            {:noreply,
             socket
             |> assign(:join_error, "Match is full")
             |> assign(:join_code, code)}
          else
            case Ash.Changeset.for_update(match, :update, %{
                   player2_id: player_id,
                   status: :in_progress
                 })
                 |> Ash.update() do
              {:ok, updated} ->
                match_id_str = to_string(updated.id)
                # Start the game GenServer so state is ready when both redirect to /play
                _ = TcgSimulator.MatchSupervisor.start_match(match_id_str)

                Phoenix.PubSub.broadcast(
                  TcgSimulator.PubSub,
                  "match:#{match_id_str}",
                  {:game_started, updated.id}
                )

                {:noreply,
                 socket
                 |> put_flash(:info, "Joined match!")
                 |> push_navigate(to: ~p"/matches/#{match_id_str}/wait")}

              {:error, _} ->
                {:noreply,
                 socket
                 |> assign(:join_error, "Could not join")
                 |> assign(:join_code, code)}
            end
          end
      end
    end
  end

  def handle_event("join_match", _params, socket) do
    {:noreply, assign(socket, :join_error, "Enter a match code")}
  end

  defp get_player_id(socket) do
    case get_connect_params(socket) do
      %{"player_id" => id} when is_binary(id) -> id
      _ -> Ecto.UUID.generate()
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <div class="min-h-screen flex flex-col items-center justify-center bg-base-200 p-4">
      <h1 class="text-3xl font-bold mb-8">TCG Simulator</h1>

      <div class="card bg-base-100 shadow-xl w-full max-w-md">
        <div class="card-body">
          <h2 class="card-title">Create private match</h2>
          <p class="text-sm opacity-70">You'll get a code to share with your opponent.</p>
          <button
            phx-click="create_match"
            class="btn btn-primary"
          >
            Create match
          </button>
        </div>
      </div>

      <div class="divider">or</div>

      <div class="card bg-base-100 shadow-xl w-full max-w-md">
        <div class="card-body">
          <h2 class="card-title">Join with code</h2>
          <form phx-submit="join_match" class="flex flex-col gap-2">
            <input
              type="text"
              name="code"
              value={@join_code}
              placeholder="e.g. ABC123"
              class="input input-bordered w-full"
              maxlength="6"
            />
            <p :if={@join_error} class="text-error text-sm"><%= @join_error %></p>
            <button type="submit" class="btn btn-secondary">
              Join match
            </button>
          </form>
        </div>
      </div>
    </div>
    """
  end
end
