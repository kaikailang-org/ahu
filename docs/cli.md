# Ao

Ao is a declarative, self-documenting command-line application library for
Kaikai. It is inspired by [Thor](https://github.com/rails/thor), translated into
Kaikai's own idioms: immutable specifications, explicit handlers, typed values,
`Result`, and effect rows instead of Ruby classes, annotations, and reflection.

Ao 0.1 includes:

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

## Dependency

```toml
[dependencies]
ao = { path = "../ao" }
```

## Define an application

```kai
import ao

fn greet(context: ao.Context) : Result[Unit, String] / Stdout = match ao.argument(context, "NAME") {
  None -> Err("missing NAME")
  Some(name) -> {
    let greeting = option.unwrap_or(ao.text(context, "greeting"), "Hello")
    let message = "#{greeting}, #{name}!"
    Stdout.print(if ao.boolean(context, "loud") { "#{message.to_upper()}\n" } else { "#{message}\n" })
    Ok(())
  }
}

fn main() : Int / Env + Stdout + Stderr = {
  let application = ao.app("greeter", "Friendly greetings")
    |> ao.versioned("0.1.0")
    |> ao.add_command(
      ao.command("greet", "Greet one person", greet)
        |> ao.command_alias("hello")
        |> ao.with_argument(ao.required_argument("NAME", "Person to greet."))
        |> ao.with_option(ao.text_option("greeting", "Words before the name.") |> ao.short("g"))
        |> ao.with_option(ao.boolean_option("loud", "Use uppercase.") |> ao.short("l"))
    )
  ao.run(application)
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

Ao validates the complete invocation before calling the handler. Handlers read
their values by canonical declaration name:

```kai
ao.argument(context, "NAME")       # Option[String]
ao.arguments(context, "FILES")    # [String]
ao.text(context, "output")        # Option[String]
ao.integer(context, "jobs")       # Option[Int]
ao.boolean(context, "force")      # Bool
ao.texts(context, "tag")          # [String]
ao.option_present(context, "jobs") # Bool
```

`option_present` distinguishes an explicit option from a defaulted value.

## Interactive actions

`ao.actions` provides Thor-style interaction without hiding effects:

```kai
import ao.actions

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
import ao.actions

let bindings = [
  actions.binding("module", "Accounts"),
  actions.binding("author", "Ana")
]

let rendered = actions.render_template("module {{module}} # {{author}}", bindings)
let change = actions.template_file(
  "templates/module.kai.ao",
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

Use `ao.resolve(application, argv)` to test or embed the parser without reading
the process environment or printing. It returns `ApplicationHelp`,
`CommandHelp`, `ApplicationVersion`, or `Invoke`. `ao.run` adds only the effects
it honestly uses: `Env`, `Stdout`, `Stderr`, and the handler's effect row.

## Why Ao is not a Thor port

Thor discovers Ruby methods and metadata through class-level DSL calls. Kaikai
has no reflection and does not need implicit mutable class state. Ao instead
builds an immutable `App[e]` containing typed `Command[e]` values and explicit
handler functions. The user experience remains Thor-like while the
implementation stays native to Kaikai.

## Development

```sh
./scripts/check.sh
```

The check verifies canonical formatting, typechecking, linting, tests, the
example, and public documentation extraction.

Runnable examples live in [`examples/greeter.kai`](examples/greeter.kai) and
[`examples/generator.kai`](examples/generator.kai). The generator combines Ao's
command parser, `ask_with_default`, status output, recursive directory creation,
and template rendering in one small program.
