# Smoke tests for todoxt. Identity defaults to "anonymous" when no auth headers
# are present (CLI / plain Caddy without GitHub). The harness may remap the host.
#
# Assertions tolerate HTML minification (attribute quotes may be dropped when
# the value does not require them).

# Home is the lists index
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

# Create a list (also ensures default exists)
POST http://localhost:8080/lists
Content-Type: application/x-www-form-urlencoded
[FormParams]
name: Groceries
HTTP 200
[Asserts]
header "HX-Redirect" contains "/list/groceries/"
body contains "Groceries"

# Assets
GET http://localhost:8080/assets/app.css
HTTP 200
[Asserts]
header "Content-Type" contains "text/css"

GET http://localhost:8080/assets/htmx.min.js
HTTP 200
