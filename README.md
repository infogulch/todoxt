# todoxt

A multi-user todo list demo for
[xtemplate](https://github.com/infogulch/xtemplate) — Go `html/template` as a
hypertext server, with SQLite, Server-Sent Events, and htmx 4.

Open two tabs of a list, edit one, and the other updates immediately over SSE.
A default **My Todos** list is created automatically on the lists index. Tech-demo
notes live on `/about`.

### URL shape

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/` | Your lists |
| `POST` | `/lists` | Create a list |
| `GET` | `/list/{slug}/{id}/` | View & edit one list (lookup by **id**) |
| `GET` | `/list/{slug}/{id}/app` | List card fragment (SSE multi-tab refresh) |
| `DELETE` | `/list/{slug}/{id}` | Delete a list |
| `POST` | `/list/{slug}/{id}/todos` | Add a todo |
| `POST` | `/list/{slug}/{id}/todos/{todoId}/toggle` | Toggle a todo |
| `DELETE` | `/list/{slug}/{id}/todos/{todoId}` | Delete a todo |
| `POST` | `/list/{slug}/{id}/toggle-all` | Toggle all in the list |
| `SSE` | `/list/{slug}/{id}/events` | Live updates for that list |

The **slug** is a kebab-case decoration from the list name (`My Todos` →
`my-todos`). Queries always use the GUID; a mismatched slug 302s to the
canonical path (with trailing slash). The page URL uses a trailing slash
(file-based `index.html` route); method routes on the list resource do not.

## What it showcases

| Feature | Where |
|---|---|
| File + method routes in templates | `templates/index.html`, `list/{name}/{id}/` |
| SQLite via `sql` provider | `provider sql DB` / `.DB.*` (per-request tx) |
| Multiple lists, REST-ish URLs | `/` + `/list/{slug}/{id}/` |
| Per-user data isolation | `owner_id` + `X-Token-Subject` |
| Live multi-tab sync | `.Bus` + `SSE /list/.../events` (per list) |
| Client-facing 4xx outcomes | `.Resp.RespondWith` + shared error templates |
| Load helpers via `.Vars` | `with-owner`, `require-list` (idempotent) in `shared/.helpers.html` |
| htmx 4 progressive enhancement | pinned `templates/assets/htmx.min.js` (v4.0.0-beta5) + `hx-sse.min.js` |
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
CLI mode does **not** strip client identity headers, so you can send
`X-Token-Subject` for multi-user tests.

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

Persist `todos.db` on a volume. Wipe the file to reset demo data (also required
after schema changes such as foreign keys on fresh installs).

### Localhost OAuth (optional)

Add a second callback URL on the same OAuth App for
`http://localhost:8080/auth/oauth2/github/authorization-code-callback`, point the
site block at `:8080`, set `cookie domain localhost` (or omit domain), and add
`http://localhost:8080` to `crossorigin.trusted_origins`.

## Transactions

The `sql` provider opens a **per-request transaction** on first use, commits on
success, and rolls back on template error. Multi-statement handlers (e.g. insert
then re-render) are therefore atomic without manual `BEGIN`/`COMMIT` in templates.

## Live sync design

1. Each mutation writes SQLite **and** publishes `"updated"` on bus topic
   `todos:{owner}:{listId}`.
2. The list card uses htmx 4’s built-in SSE extension: `hx-sse:connect` on
   `#todos-app` GETs `/list/{slug}/{id}/events`, which ranges `.Bus.Subscribe`
   for that owner+list.
3. The stream sends **named** events (`connected`, `updated`). Named events are
   dispatched as DOM events (not swapped). A hidden listener on the card
   `hx-get`s `/list/{slug}/{id}/app` on `updated` and outerHTML-swaps `#todos-app`.

Topics are per-list so a mutation on list A does not refresh list B’s open tabs.
Users never receive each other’s HTML. The in-process `bus` provider is
single-process only (fine for one Caddy instance).

### Fine-grained mutations

Local edits do **not** re-render the whole card:

| Action | Main swap | OOB |
|---|---|---|
| Add todo | `beforeend` on `#todo-list` (one `<li>`) | footer, toggle-all, delete empty placeholder |
| Toggle todo | `outerHTML` on that `<li>` | footer, toggle-all |
| Delete todo | `delete` on that `<li>` | footer, toggle-all; empty list restores `#todo-empty` |
| Toggle all | `innerHTML` on `#todo-list` | footer, toggle-all |

Multi-tab sync still refreshes the full `#todos-app` (we only know “something changed”).

**SSE ownership note:** HTML routes use `require-list` → real **404** when the list
is missing or not yours. The SSE handler cannot: xtemplate commits
`text/event-stream` headers before the template runs, and `.Resp.RespondWith` is
buffered-only. An unowned stream aborts with `failf` (logged) but the client still
sees **200** and a short body; `hx-sse` may reconnect. Do not treat SSE status
as the isolation boundary — topics are still scoped to `owner:listId`, and HTML
mutations always go through `require-list`.

## CSRF / cross-origin

xtemplate enables Go’s `CrossOriginProtection` by default for browser mutations.
todoxt does **not** invent CSRF tokens. In production, set
`crossorigin.trusted_origins` in the Caddyfile (see `Caddyfile.github`) and do
not disable cross-origin checks.

## Progressive enhancement

Compose forms include both native `method`/`action` and htmx attributes. With JS
disabled, creating a list or todo still works via full-page POST + redirect.
Toggle/delete controls remain htmx-oriented for the demo.

## Project layout

```
Caddyfile           # local dev (fixed identity headers)
Caddyfile.github    # todo.xtemplate.dev + GitHub OAuth
config.json         # plain xtemplate CLI config
templates/
  index.html                 # GET / page (lists-index block) + POST /lists
  list/{name}/{id}/
    index.html               # list page (todos-app + nested blocks) + GET …/app + mutations + SSE
  about.html                 # tech-demo writeup
  assets/
    app.css
    htmx.min.js              # htmx 4.0.0-beta5
    hx-sse.min.js            # htmx 4 SSE extension (hx-sse:connect)
  shared/
    .head.html               # partial (no route)
    .nav.html
    .schema.html             # INIT SQLite schema (FK + CASCADE)
    .helpers.html            # with-owner, ensure-lists, require-list, notify, list-base/path
    .404.html                # RespondWith body for missing list
    .error.html              # RespondWith body for 400/409 client errors
tests/
  todos.hurl                 # smoke + multi-step CRUD + SSE
  isolation.hurl             # per-user isolation (CLI; no header rewrite)
```

### Template layout convention

Main pages embed their HTML with `{{block "name" .}}…{{end}}` (define **and**
render in place). Open `index.html` or `list/…/index.html` to see the page
source; shared chrome (`nav`, `.head.html`) and pure helpers stay in `shared/`.
Mutations and fragment routes re-invoke the same names with `{{template}}`.
Row-level fragments (`todo-item`, `todo-empty`) use `{{define}}` because they
appear in a `range`, not as a single fixed slot in the skeleton.

## Smoke tests

Prefer a clean DB for a deterministic suite:

```sh
rm -f todos.db todos.db-shm todos.db-wal
./caddy run --config Caddyfile   # or xtemplate -f config.json
hurl --test tests/todos.hurl
```

Per-user isolation (different `X-Token-Subject` values) needs the CLI or any
setup that does not rewrite identity headers — the local Caddyfile always
injects `dev`:

```sh
# separate process: xtemplate -f config.json
hurl --test tests/isolation.hurl
```

## Notes

- **Not for secrets.** This is a public demo; data may be wiped.
- **htmx 4** is currently a beta line; the pin is intentional for the showcase.
- Dropping Tailwind keeps the demo readable: one small `app.css`, no build step.
- Fresh DBs get `todo.list_id NOT NULL REFERENCES todo_list(id) ON DELETE CASCADE`.
  Wipe `todos.db` if you still have a pre-FK schema.
