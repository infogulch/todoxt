# Smoke tests for todoxt. Identity defaults to "anonymous" when no auth headers
# are present (CLI / plain Caddy without GitHub). The harness may remap the host.
#
# Assertions tolerate HTML minification (attribute quotes may be dropped when
# the value does not require them).

GET http://localhost:8080/
HTTP 200
[Asserts]
body contains "todoxt"
body contains "Live multi-tab sync"

GET http://localhost:8080/todos
HTTP 200
[Asserts]
body contains "Todos"
body contains "id=todos-app"

# Add a todo
POST http://localhost:8080/todos
Content-Type: application/x-www-form-urlencoded
[FormParams]
label: Buy milk
HTTP 200
[Asserts]
body contains "Buy milk"
body contains "todo-item"

# Panel fragment
GET http://localhost:8080/todos/app
HTTP 200
[Asserts]
body contains "Buy milk"
body contains "id=todos-app"

# Assets
GET http://localhost:8080/assets/app.css
HTTP 200
[Asserts]
header "Content-Type" contains "text/css"

GET http://localhost:8080/assets/htmx.min.js
HTTP 200
