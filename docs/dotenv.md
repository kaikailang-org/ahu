# kai-dotenv

kai-dotenv loads development and test configuration from `.env` files into a
Kaikai process environment. Parsing is available independently, so tools can
inspect or validate configuration without mutating process-wide state.

Version 0.1 supports:

- unquoted, single-quoted, double-quoted, empty, and multiline values;
- `export NAME=value`, `NAME=value`, and `NAME: value` assignments;
- full-line and trailing comments;
- `$NAME` and `${NAME}` expansion using earlier assignments and explicit
  fallback values;
- multiple files in priority order, where the first definition wins;
- preservation of existing environment variables by default;
- explicit overwrite and required-file policies;
- required-key validation and value-free load reports;
- deterministic `.env.template` generation.

Dotenv files are treated strictly as data. Shell command substitution with
`$()` is rejected and never executed.

## Dependency

```toml
[dependencies]
dotenv = { path = "../kai-dotenv" }
```

Applications import the `dotenv` module:

```kai
import dotenv
```

## Load `.env`

```kai
import dotenv

fn main() : Int / File + Env + Stderr = match dotenv.load() {
  Ok(_report) -> 0
  Err(error) -> {
    Stderr.eprint("#{dotenv.error_message(error)}\n")
    1
  }
}
```

An absent default `.env` is ignored. Existing process variables are preserved,
because deployment configuration has precedence over local files.

To run the included example from the package directory, create a `.env` file:

```dotenv
APP_NAME=Kaikai
```

Then execute:

```sh
kai run examples/load.kai
```

## Load several files

Paths are ordered from highest to lowest priority:

```kai
let report = dotenv.load_files(
  [".env.local", ".env"],
  dotenv.options() |> dotenv.with_required_files
)
```

To replace existing process variables explicitly:

```kai
let settings = dotenv.options()
  |> dotenv.with_required_files
  |> dotenv.with_overwrite

let report = dotenv.load_files([".env.test", ".env"], settings)
```

The returned `Report` contains only filenames and variable names. It never
copies secret values into logs or diagnostics.

## Parse without side effects

```kai
import dotenv
import dotenv.parser

let document = dotenv.parse("HOST=localhost\nPORT=4100\n")!
let host = parser.get(document, "HOST")
let pairs = parser.pairs(document)
```

Expansion can receive an explicit fallback environment while remaining pure:

```kai
let document = dotenv.parse_with(
  "URL=https://${HOST}/api\n",
  [("HOST", "example.test")]
)!
```

## Read and apply separately

The effect boundary can remain under application control:

```kai
let document = dotenv.read(".env")!       # / File
let report = dotenv.apply(document, dotenv.options())! # / Env
```

## Required keys

```kai
dotenv.require_keys(["DATABASE_URL", "SECRET_KEY_BASE"])
```

Empty values count as present. Failures identify missing names without exposing
any configured values.

## Syntax

```dotenv
# comments
APP_NAME=kaikai
export PORT = 4100
HOST: example.test
URL="https://${HOST}:${PORT}"
PASSWORD='literal $ value'
PRIVATE_KEY="first line
second line"
```

Names begin with a letter or underscore and may contain letters, digits,
underscores, and dots. Single quotes are literal. Unquoted and double-quoted
values expand variables. Unknown references expand to an empty string; prefix a
dollar with a backslash to keep it literal.

## Templates

```kai
let source = "HOST=localhost\nPORT=4100\n"
let document = dotenv.parse(source)!
let template = parser.template(document)
# HOST=HOST
# PORT=PORT
```

## Development

```sh
./scripts/check.sh
```

The check validates canonical formatting, typechecking, linting, pure parser
tests, a real file/environment round-trip, the example, and public docs.
