# Smoke + multi-step tests for todoxt.
# Identity: Caddyfile injects "dev"; CLI defaults to "anonymous" without headers.
# Prefer a clean todos.db for deterministic behavior.
#
# Assertions tolerate HTML minification (attribute quotes may be dropped when
# the value does not require them).

# Home is the lists index (creates default "My Todos" when empty)
GET http://localhost:8080/
HTTP 200
[Asserts]
body contains "todoxt"
body contains "id=lists-index"
body contains "My Todos"
body contains "/list/my-todos/"

# About page holds the tech-demo writeup
GET http://localhost:8080/about
HTTP 200
[Asserts]
body contains "About todoxt"
body contains "Live multi-tab sync"
body contains "CrossOriginProtection"

# Create a list (htmx)
POST http://localhost:8080/lists
Content-Type: application/x-www-form-urlencoded
HX-Request: true
[FormParams]
name: Groceries
HTTP 200
[Captures]
groceries_path: header "HX-Redirect"
list_id: regex "/list/groceries/([0-9a-fA-F-]+)/"
[Asserts]
header "HX-Redirect" contains "/list/groceries/"
body contains "Groceries"

# Canonical list page
GET http://localhost:8080{{groceries_path}}
HTTP 200
[Asserts]
body contains "Groceries"
body contains "id=todos-app"

# Wrong slug → 302 to canonical path
GET http://localhost:8080/list/not-the-slug/{{list_id}}/
HTTP 302
[Asserts]
header "Location" contains "/list/groceries/"
header "Location" contains "{{list_id}}"

# Add a todo (htmx fragment)
POST http://localhost:8080/list/groceries/{{list_id}}/todos
Content-Type: application/x-www-form-urlencoded
HX-Request: true
[FormParams]
label: Buy milk
HTTP 200
[Captures]
todo_id: regex "id=\"todo-([^\"]+)\""
[Asserts]
body contains "Buy milk"
body contains "id=todos-app"

# Toggle the todo
POST http://localhost:8080/list/groceries/{{list_id}}/todos/{{todo_id}}/toggle
HX-Request: true
HTTP 200
[Asserts]
body contains "Buy milk"
body contains "todo-item--done"

# Delete the todo
DELETE http://localhost:8080/list/groceries/{{list_id}}/todos/{{todo_id}}
HX-Request: true
HTTP 200
[Asserts]
body contains "No todos yet"

# Empty label → 400
POST http://localhost:8080/list/groceries/{{list_id}}/todos
Content-Type: application/x-www-form-urlencoded
HX-Request: true
[FormParams]
label:
HTTP 400
[Asserts]
body contains "label is required"

# Missing list → 404
GET http://localhost:8080/list/my-todos/00000000-0000-0000-0000-000000000000/
HTTP 404
[Asserts]
body contains "List not found"

# SSE without Accept → 406 (streaming body is not practical in hurl)
GET http://localhost:8080/list/groceries/{{list_id}}/events
HTTP 406

# Create a disposable list, then delete it (other lists remain)
POST http://localhost:8080/lists
Content-Type: application/x-www-form-urlencoded
HX-Request: true
[FormParams]
name: Temp Delete Me
HTTP 200
[Captures]
temp_id: regex "/list/temp-delete-me/([0-9a-fA-F-]+)/"
[Asserts]
header "HX-Redirect" contains "/list/temp-delete-me/"

DELETE http://localhost:8080/list/temp-delete-me/{{temp_id}}
HX-Request: true
HX-Target: #lists-index
HTTP 200
[Asserts]
body contains "id=lists-index"
body not contains "Temp Delete Me"

# Cannot delete last list: leave only one list then expect 409.
# Home still has My Todos; delete Groceries first, then attempt My Todos.
DELETE http://localhost:8080/list/groceries/{{list_id}}
HX-Request: true
HX-Target: #lists-index
HTTP 200
[Asserts]
body contains "id=lists-index"

# Capture remaining My Todos id and try to delete it
GET http://localhost:8080/
HTTP 200
[Captures]
my_todos_id: regex "/list/my-todos/([0-9a-fA-F-]+)/"
[Asserts]
body contains "My Todos"

DELETE http://localhost:8080/list/my-todos/{{my_todos_id}}
HX-Request: true
HTTP 409
[Asserts]
body contains "cannot delete the last list"

# Progressive enhancement: no-JS create list → 303 redirect
# kebabcase("NoJS List") → no-js-list
POST http://localhost:8080/lists
Content-Type: application/x-www-form-urlencoded
[FormParams]
name: NoJS List
HTTP 303
[Captures]
nojs_path: header "Location"
nojs_id: header "Location" regex "/list/no-js-list/([0-9a-fA-F-]+)/"
[Asserts]
header "Location" contains "/list/no-js-list/"

# Progressive enhancement: no-JS add todo → 303 back to list
POST http://localhost:8080/list/no-js-list/{{nojs_id}}/todos
Content-Type: application/x-www-form-urlencoded
[FormParams]
label: From form post
HTTP 303
[Asserts]
header "Location" contains "/list/no-js-list/"
header "Location" contains "{{nojs_id}}"

GET http://localhost:8080{{nojs_path}}
HTTP 200
[Asserts]
body contains "From form post"

# Assets
GET http://localhost:8080/assets/app.css
HTTP 200
[Asserts]
header "Content-Type" contains "text/css"

GET http://localhost:8080/assets/htmx.min.js
HTTP 200
