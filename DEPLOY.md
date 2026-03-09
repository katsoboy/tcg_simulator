# Deploying TCG Simulator to Fly.io

## If your deploy was failing before

The project now includes everything Fly.io needs:

- **Dockerfile** – builds the Phoenix release (Elixir + Node for assets)
- **fly.toml** – app config, release command for migrations, port 8080
- **Release module** – `TcgSimulator.Release.migrate` and `TcgSimulator.Release.seed`
- **rel/overlays/bin** – `migrate` and `server` scripts used in the release

## 1. Repo root vs app directory

- If your **Git repo root** is the Phoenix app (you have `mix.exs`, `lib/`, `config/` at the top level): use the repo root as the Fly app directory. No change needed.
- If your **repo root** is the parent folder and the app lives in **`tcg_simulator/`**:
  - In [Fly.io Dashboard](https://fly.io/dashboard) → your app → **Settings** → set **Source** / **Root directory** to `tcg_simulator`.
  - Or when using `fly launch`, run it from inside the app: `cd tcg_simulator && fly launch`.

## 2. Required secrets / env (Fly Postgres)

After attaching Fly Postgres, Fly sets `DATABASE_URL` for you. You must set:

- **SECRET_KEY_BASE** – generate with `mix phx.gen.secret` and set in Fly:
  ```bash
  fly secrets set SECRET_KEY_BASE="$(mix phx.gen.secret)"
  ```
- **PHX_HOST** – must match your app hostname, e.g. `your-app-name.fly.dev`:
  ```bash
  fly secrets set PHX_HOST="your-app-name.fly.dev"
  ```
  Or in **fly.toml** under `[env]`: `PHX_HOST = "your-app-name.fly.dev"` (match the `app` name in fly.toml).

## 3. App name in fly.toml

In **fly.toml**, `app = "tcg-simulator"` is the Fly app name. If you created the app with another name in the dashboard, either:

- Rename to match: change the first line of **fly.toml** to `app = "your-actual-app-name"`, or  
- Set **PHX_HOST** to `your-actual-app-name.fly.dev` (see above).

## 4. Deploy

From the directory that contains **fly.toml** and **Dockerfile** (usually `tcg_simulator/`):

```bash
fly deploy
```

This will:

1. Build the image (compile, assets, release).
2. Run **release_command**: `/app/bin/migrate` (runs Ecto migrations).
3. Start the app with **CMD** `/app/bin/server` (Phoenix on PORT 8080).

## 5. Seed the database (optional)

To load default card templates and decks (only needed once):

```bash
fly ssh console -C "/app/bin/tcg_simulator eval 'TcgSimulator.Release.seed()'"
```

## 6. Useful commands

- **Logs:** `fly logs`
- **Status:** `fly status`
- **Open app:** `fly open`
- **Secrets:** `fly secrets list` / `fly secrets set KEY=value`

## 7. If build still fails

- Check **fly logs** for the failing step (compile, assets, release, or migrate).
- Ensure the **build context** is the directory that contains **mix.exs** and **Dockerfile** (set Root directory in the dashboard if the app is in a subfolder).
- Ensure **SECRET_KEY_BASE** and **PHX_HOST** are set; **DATABASE_URL** is set automatically when Postgres is attached.
