# todoxt

A multi-user todo list demo for
[xtemplate](https://github.com/infogulch/xtemplate) — Go `html/template` as a
hypertext server, with SQLite, Server-Sent Events, and htmx 4.

Open two tabs of `/todos`, edit one, and the other updates immediately over SSE.

## What it showcases

| Feature | Where |
|---|---|
| File + method routes in templates | `templates/todos.html` |
| SQLite via `sql` provider | `provider sql DB` / `.DB.*` |
| Per-user data isolation | `owner_id` + `X-Token-Subject` |
| Live multi-tab sync | `.Bus` + `SSE /todos/events` |
| htmx 4 progressive enhancement | pinned `templates/assets/htmx.min.js` (v4.0.0-beta5) |
| Content-hashed static assets | `.X.StaticFileHash` |
| Auth outside the app | Caddy + [caddy-security](https://docs.authcrunch.com/) (GitHub OAuth) |

## Quickstart (local, no GitHub)

### Option A — xtemplate CLI

```sh
# from a checkout of github.com/infogulch/xtemplate
go run ./cmd -f /path/to/todoxt/config.json
# or use a built binary:
#   /path/to/xtemplate -f config.json
```

Open http://localhost:8080 — all requests share the `anonymous` owner (no auth headers).

### Option B — Caddy (recommended)

Build Caddy with the standard xtemplate module (sqlite3 + bus + other providers):

```sh
xcaddy build --with github.com/infogulch/xtemplate/caddy/standard
```

From this directory:

```sh
./caddy run --config Caddyfile
```

The local `Caddyfile` injects a fixed identity (`dev` / `Local Dev`) so SQL
scoping behaves like production without OAuth.

Open http://localhost:8080

## Production (GitHub OAuth)

Use `Caddyfile.github` and build with both modules:

```sh
xcaddy build \
  --with github.com/infogulch/xtemplate/caddy/standard \
  --with github.com/greenpau/caddy-security
```

1. Create a **GitHub OAuth App** (Settings → Developer settings → OAuth Apps), not
   a GitHub App install:
   - Homepage: `https://todo.xtemplate.dev`
   - Authorization callback URL:
     `https://todo.xtemplate.dev/auth/oauth2/github/authorization-code-callback`
2. Export secrets:

   ```sh
   export GITHUB_CLIENT_ID=...
   export GITHUB_CLIENT_SECRET=...
   export JWT_SHARED_KEY="$(openssl rand -hex 32)"
   ```

3. Run:

   ```sh
   caddy run --config Caddyfile.github
   ```

After login, caddy-security injects claim headers (`X-Token-Subject`,
`X-Token-User-Name`, …). Templates treat `X-Token-Subject` as the todo owner id
(stable per GitHub account for this portal configuration).

Persist `todos.db` on a volume. Wipe the file to reset demo data.

### Localhost OAuth (optional)

Add a second callback URL on the same OAuth App for
`http://localhost:8080/auth/oauth2/github/authorization-code-callback`, point the
site block at `:8080`, set `cookie domain localhost` (or omit domain), and add
`http://localhost:8080` to `crossorigin.trusted_origins`.

## Live sync design

1. Each mutation writes SQLite **and** publishes `"updated"` on bus topic
   `todos:{owner}`.
2. Each tab opens `EventSource("/todos/events")`, which ranges
   `.Bus.Subscribe` for that owner and streams SSE.
3. On a ping, the tab `htmx.ajax`s `GET /todos/app` and swaps `#todos-app`.

Topics are per-user so users never receive each other’s HTML. The in-process
`bus` provider is single-process only (fine for one Caddy instance).

## Project layout

```
Caddyfile           # local dev (fixed identity headers)
Caddyfile.github    # todo.xtemplate.dev + GitHub OAuth
config.json         # plain xtemplate CLI config
templates/
  index.html        # landing / feature tour
  todos.html        # UI + INIT schema + CRUD + SSE routes
  assets/
    app.css
    htmx.min.js     # htmx 4.0.0-beta5
  shared/
    .head.html      # partial (no route)
    .nav.html
tests/
  todos.hurl        # smoke tests
```

## Smoke tests

With the server on `:8080`:

```sh
hurl --test tests/todos.hurl
```

## Notes

- **Not for secrets.** This is a public demo; data may be wiped.
- **htmx 4** is currently a beta line; the pin is intentional for the showcase.
- Dropping Tailwind keeps the demo readable: one small `app.css`, no build step.
