# How Elixir Concurrency Works in the TCG Simulator

This guide explains the concurrency model in your app using the code you actually have.

---

## 1. The Big Idea: One Process Per Match

In Elixir, **concurrency = many processes**. Your app runs **one process per active match**.

- Match A has its own process (GenServer).
- Match B has its own process.
- They run **at the same time** and **do not block each other**.

So when Player 1 in Match A plays a card, that work happens in Match A’s process. Match B’s process is untouched. That’s why you can have many games running in parallel without one game slowing down another.

```
┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐
│  MatchServer    │   │  MatchServer    │   │  MatchServer    │
│  (match abc)    │   │  (match xyz)    │   │  (match 123)    │
└────────┬────────┘   └────────┬────────┘   └────────┬────────┘
         │                     │                     │
         │  Each process has   │  its own state      │
         │  (hands, board,     │  and runs            │
         │   life, turn...)    │  independently      │
         └─────────────────────┴─────────────────────┘
```

---

## 2. Where Processes Come From: The Supervision Tree

When the app starts, `Application.start/2` starts a **supervision tree**: a list of long‑lived processes. If a child crashes, the supervisor can restart it.

Your tree (from `lib/tcg_simulator/application.ex`):

```elixir
children = [
  TcgSimulatorWeb.Telemetry,
  TcgSimulator.Repo,
  {Phoenix.PubSub, name: TcgSimulator.PubSub},   # ← message bus (see below)
  {Registry, keys: :unique, name: TcgSimulator.MatchRegistry},  # ← names for match processes
  TcgSimulator.MatchSupervisor,   # ← starts one MatchServer per match
  TcgSimulatorWeb.Endpoint
]
```

- **PubSub**: process that delivers messages to subscribers (used for “broadcast to both players”).
- **Registry**: lets you find a match process by name (e.g. `"match_id_here"`) instead of by PID.
- **MatchSupervisor**: a **DynamicSupervisor**. It doesn’t start any match processes at boot; it **starts a new MatchServer when a match actually begins** (when the second player joins).

So: **concurrency in your app = many MatchServer processes**, each started on demand by `MatchSupervisor`.

---

## 3. Naming and Finding a Match Process: Registry

You need to talk to “the process for match X” without storing its PID everywhere. That’s what **Registry** is for.

In `MatchServer`:

```elixir
def via_tuple(match_id) do
  key = to_string(match_id)
  {:via, Registry, {TcgSimulator.MatchRegistry, key}}
end

def start_link(opts) do
  match_id = opts |> Keyword.fetch!(:match_id) |> to_string()
  GenServer.start_link(__MODULE__, [match_id: match_id], name: via_tuple(match_id))
end
```

- When a match starts, the GenServer is **registered** under the key `match_id` (e.g. `"5957331a-203a-4e45-93a0-e9e9c1a243db"`).
- When the LiveView wants to play a card, it calls `MatchServer.play_card(match_id, ...)`.
- Under the hood, that uses `GenServer.call(via_tuple(match_id), {:play_card, ...})`, which **looks up the process by that name** and sends the message to it.

So: **one name (match_id) → one process**. That’s how “concurrency per match” is wired: each match_id has its own process, and you always reach it by name.

---

## 4. Talking to the Match: GenServer.call (Request–Response)

When a player clicks “Play card”, the LiveView process sends a **synchronous request** to that match’s process and waits for a reply. That’s **GenServer.call**.

Flow:

1. **LiveView process** (one per browser tab): handles the click, calls `MatchServer.play_card(match_id, player_id, hand_index, 0)`.
2. **MatchServer** (one per match): receives `{:play_card, player_id, hand_index, 0}` in `handle_call/3`, updates its state, replies `:ok` or `{:error, msg}`.
3. **LiveView** gets the reply and updates the socket (e.g. clear error or show message).

```elixir
# In GameLive – the caller (LiveView process)
case MatchServer.play_card(match_id, socket.assigns.player_id, hand_index, 0) do
  :ok -> {:noreply, assign(socket, :error_toast, nil)}
  {:error, msg} -> {:noreply, assign(socket, :error_toast, msg)}
end
```

```elixir
# In MatchServer – the callee (match process)
def handle_call({:play_card, player_id, raw_hand_index, _board_position}, _from, state) do
  # ... validate, update state ...
  broadcast(state.match_id, new_state)   # tell BOTH players (see below)
  {:reply, :ok, new_state}
end
```

So: **concurrency is preserved** because only that match’s process does the work; other matches’ processes are not involved. The LiveView “waits” only for that one match’s process to answer.

---

## 5. Telling Both Players: PubSub (One-to-Many Messages)

After the match process updates state, **both** players’ UIs must update. That’s not a request–response; it’s “notify everyone interested.” That’s **PubSub**.

In `MatchServer`, after any state change:

```elixir
defp broadcast(match_id, state) do
  topic = "match:#{to_string(match_id)}"
  Phoenix.PubSub.broadcast(PubSub, topic, {:game_updated, state})
end
```

- **Topic**: `"match:#{match_id}"` (e.g. `"match:5957331a-203a-4e45-93a0-e9e9c1a243db"`).
- **Message**: `{:game_updated, state}`.
- **Effect**: Every process that **subscribed** to that topic gets that message in its mailbox.

In `GameLive.mount/3` (each player’s LiveView):

```elixir
Phoenix.PubSub.subscribe(TcgSimulator.PubSub, "match:#{match_id}")
```

So when the match process calls `broadcast(match_id, new_state)`:

1. PubSub sends `{:game_updated, new_state}` to **both** LiveView processes (Player 1 and Player 2).
2. Each LiveView has a `handle_info({:game_updated, state}, socket)` that updates the socket and re-renders.
3. Both browsers get the new board at the same time.

So: **one sender (MatchServer), many receivers (both LiveViews)**. That’s the concurrency pattern for “push” updates: one process broadcasts, many processes react.

---

## 6. LiveView as a Process

Each browser connection has its own **LiveView process**. So:

- Player 1’s tab = process A.
- Player 2’s tab = process B.
- Match 1’s game state = process C (MatchServer).

When Player 1 clicks “Play card”:

- **Process A** (Player 1’s LiveView) runs `handle_event("play_card", ...)`.
- It does `GenServer.call(process C, {:play_card, ...})` → **process C** runs the game logic and broadcasts.
- **Process A** gets the `:ok` from the call and can update its socket.
- **Process A and B** both receive `{:game_updated, state}` via PubSub and re-render.

So: **concurrency again** — each client is its own process; the match is another process; they coordinate via **call** (to the match) and **broadcast** (from the match to the LiveViews).

---

## 7. Putting It Together: One “Play Card” in Terms of Processes

1. **Player 1’s LiveView** (process A): receives `"play_card"` with `index`.
2. **Process A** calls `MatchServer.play_card(match_id, ...)` → message goes to **MatchServer** (process C) via Registry.
3. **Process C** runs `handle_call({:play_card, ...})`: updates state, calls `broadcast(match_id, new_state)`.
4. **PubSub** sends `{:game_updated, new_state}` to every subscriber of `"match:#{match_id}"` → **process A** and **Player 2’s LiveView** (process B).
5. **Process C** replies `:ok` to the `GenServer.call` → **process A** gets the reply and can clear errors etc.
6. **Process A** and **process B** handle `{:game_updated, state}` in `handle_info/2` and re-render.

So in one “play card” action you see:

- **Synchronous**: LiveView → MatchServer (call/reply).
- **Asynchronous**: MatchServer → both LiveViews (broadcast → handle_info).

---

## 8. Summary Table

| Concept | In your app |
|--------|--------------|
| **Process** | Each match = one MatchServer; each browser = one LiveView. |
| **Supervision** | MatchSupervisor starts MatchServers on demand; Application starts PubSub, Registry, etc. |
| **Naming** | Registry maps `match_id` → MatchServer process so LiveViews can call it. |
| **Request–response** | `GenServer.call` from LiveView to MatchServer (play card, end turn, attack). |
| **One-to-many** | `PubSub.broadcast` from MatchServer to topic; both LiveViews subscribe and get `{:game_updated, state}`. |
| **Concurrency** | Many matches = many MatchServer processes; many users = many LiveView processes; they don’t block each other. |

---

## 9. Quick Mental Model

- **MatchServer** = the “game engine” for one match; it holds state and enforces rules.
- **Registry** = the “phone book” from match ID to that game engine process.
- **GenServer.call** = “ask that game engine to do something and give me the result.”
- **PubSub** = “shout the new state to everyone watching this match,” so both players’ LiveViews update.

If you want to go deeper, the next steps are: reading the [GenServer docs](https://hexdocs.pm/elixir/GenServer.html), the [Registry docs](https://hexdocs.pm/elixir/Registry.html), and [Phoenix.PubSub](https://hexdocs.pm/phoenix_pubsub/Phoenix.PubSub.html), and tracing one action (e.g. “play card”) from the LiveView click through `handle_call` and `broadcast` to `handle_info` in both LiveViews.
