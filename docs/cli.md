# ahu.cli

`ahu.cli` is a declarative, self-documenting command-line application library for
Kaikai. It is inspired by [Thor](https://github.com/rails/thor), translated into
Kaikai's own idioms: immutable specifications, explicit handlers, typed values,
`Result`, and effect rows instead of Ruby classes, annotations, and reflection.

It supports:

- named commands and aliases;
- required, optional, defaulted, and repeated positional arguments;
- string, integer, boolean, and repeatable string options;
- long options, one-character short aliases, `--name=value`, and `--no-name`;
- required options and default values;
- generated application and command help;
- built-in `help`, `--help`, `-h`, `--version`, and `-v` handling;
- pure argument resolution separated from effectful execution;
- default commands and deterministic definition validation;
- interactive `say`, `ask`, `confirm`, `yes`, and `no` actions;
- conflict-aware file, directory, copy, injection, and template actions.

## Import

```kai
import ahu.cli
import ahu.cli.actions
```

## Define an application

```kai
import ahu.cli

fn greet(context: cli.Context) : Result[Unit, String] / Stdout = match cli.argument(context, "NAME") {
  None -> Err("missing NAME")
  Some(name) -> {
    let greeting = option.unwrap_or(cli.text(context, "greeting"), "Hello")
    let message = "#{greeting}, #{name}!"
    Stdout.print(if cli.boolean(context, "loud") { "#{message |> to_upper()}\n" } else { "#{message}\n" })
    Ok(())
  }
}

fn main() : Int / Env + Stdout + Stderr {
  let application = cli.app("greeter", "Friendly greetings")
    |> cli.versioned("0.1.0")
    |> cli.add_command(
      cli.command("greet", "Greet one person", greet)
        |> cli.command_alias("hello")
        |> cli.with_argument(cli.required_argument("NAME", "Person to greet."))
        |> cli.with_option(cli.text_option("greeting", "Words before the name.") |> cli.short("g"))
        |> cli.with_option(cli.boolean_option("loud", "Use uppercase.") |> cli.short("l"))
    )
  cli.run(application)
}
```

The resulting executable accepts:

```sh
greeter greet Ana
greeter hello Ana --greeting Hola
greeter greet Ana --loud
greeter help greet
greeter --version
```

## Handler context

`ahu.cli` validates the complete invocation before calling the handler. Handlers read
their values by canonical declaration name:

```kai
cli.argument(context, "NAME")       # Option[String]
cli.arguments(context, "FILES")    # [String]
cli.text(context, "output")        # Option[String]
cli.integer(context, "jobs")       # Option[Int]
cli.boolean(context, "force")      # Bool
cli.texts(context, "tag")          # [String]
cli.option_present(context, "jobs") # Bool
```

`option_present` distinguishes an explicit option from a defaulted value.

## Interactive actions

`cli.actions` provides Thor-style interaction without hiding effects:

```kai
import ahu.cli.actions

actions.say("Creating the project")
let name = actions.ask_with_default("Project name?", "demo")
if actions.yes("Continue?") {
  actions.say_status("create", name)
}
```

The signatures expose `Stdout + Stdin`; tests can replace those handlers in the
usual Kaikai way.

## Templates and files

Templates use deliberately small `{{name}}` placeholders. They perform string
substitution only—there is no evaluation or reflection:

```kai
import ahu.cli.actions

let bindings = [
  actions.binding("module", "Accounts"),
  actions.binding("author", "Ana")
]

let rendered = actions.render_template("module {{module}} # {{author}}", bindings)
let change = actions.template_file(
  "templates/module.kai.tmpl",
  "src/accounts.kai",
  bindings,
  OverwriteExisting
)
```

The filesystem actions return `Result[actions.Change, actions.ActionError]` and
never silently overwrite changed files. Callers choose `OverwriteExisting`,
`SkipExisting`, or `FailIfExists`. Available actions include `create_file`,
`copy_file`, `template_file`, `create_from_template`, `append_file`,
`inject_after`, `remove_file`, and recursive `ensure_directory`.

## Parsing rules

- Options may appear before, between, or after positional arguments.
- `--` stops option parsing.
- Scalar options may appear once. Repeatable text options accumulate values.
- Boolean options accept `--flag`, `--no-flag`, `--flag=true`, and
  `--flag=false`.
- Short options are intentionally not clustered: write `-f -v`, not `-fv`.
- Command and option declarations are validated before each resolution.

## Pure resolution

Use `cli.resolve(application, argv)` to test or embed the parser without reading
the process environment or printing. It returns `ApplicationHelp`,
`CommandHelp`, `ApplicationVersion`, or `Invoke`. `cli.run` adds only the effects
it honestly uses: `Env`, `Stdout`, `Stderr`, and the handler's effect row.

## Why `ahu.cli` is not a Thor port

Thor discovers Ruby methods and metadata through class-level DSL calls. Kaikai
has no reflection and does not need implicit mutable class state. `ahu.cli` instead
builds an immutable `App[e]` containing typed `Command[e]` values and explicit
handler functions. The user experience remains Thor-like while the
implementation stays native to Kaikai.

## Tests

`make tier1` runs the parser tests in `tests/unit/cli_test.kai`, the action
tests in `tests/unit/cli_actions_test.kai`, the file round-trip in
`tests/cli_actions_file_roundtrip.kai`, and the two examples.

Runnable examples live in `examples/cli_greeter/main.kai` and
`examples/cli_generator/main.kai`. The generator combines the command parser,
`ask_with_default`, status output, recursive directory creation, and template
rendering in one small program.
