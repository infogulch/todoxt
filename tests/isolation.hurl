# Per-user isolation. Requires a server that does NOT rewrite X-Token-Subject.
# `mise test` generates such a Caddyfile in .scratch/runs/. For a manual run:
#
#   # Use config.json (no header rewrite), not the local Caddyfile (injects "dev")
#   rm -f todos.db todos.db-shm todos.db-wal
#   xtemplate -f config.json
#   hurl --test tests/isolation.hurl

# First action is create list (no prior GET) → exactly that list, no auto "My Todos"
POST http://localhost:8080/lists
X-Token-Subject: carol
Content-Type: application/x-www-form-urlencoded
HX-Request: true
[FormParams]
name: Carol Only
HTTP 200
[Captures]
carol_path: header "HX-Redirect"
carol_list_id: header "HX-Redirect" regex "/list/carol-only/([0-9a-fA-F-]+)/"
[Asserts]
header "HX-Redirect" contains "/list/carol-only/"

GET http://localhost:8080/
X-Token-Subject: carol
HTTP 200
[Asserts]
body contains "Carol Only"
body contains "{{carol_list_id}}"
body not contains "My Todos"

# Alice gets a default list on first GET
GET http://localhost:8080/
X-Token-Subject: alice
HTTP 200
[Captures]
alice_list_id: regex "/list/my-todos/([0-9a-fA-F-]+)/"
[Asserts]
body contains "My Todos"
body contains "/list/my-todos/"

# Bob cannot open Alice's list by id
GET http://localhost:8080/list/my-todos/{{alice_list_id}}/
X-Token-Subject: bob
HTTP 404
[Asserts]
body contains "List not found"

# Alice adds a todo; capture id
POST http://localhost:8080/list/my-todos/{{alice_list_id}}/todos
X-Token-Subject: alice
Content-Type: application/x-www-form-urlencoded
HX-Request: true
[FormParams]
label: Alice only
HTTP 200
[Captures]
alice_todo_id: regex "id=\"todo-([^\"]+)\""
[Asserts]
body contains "Alice only"

# Bob cannot toggle Alice's todo (list ownership fails first)
POST http://localhost:8080/list/my-todos/{{alice_list_id}}/todos/{{alice_todo_id}}/toggle
X-Token-Subject: bob
HX-Request: true
HTTP 404
[Asserts]
body contains "List not found"

# Bob's index does not list Alice's list id
GET http://localhost:8080/
X-Token-Subject: bob
HTTP 200
[Asserts]
body not contains "{{alice_list_id}}"
body contains "My Todos"
