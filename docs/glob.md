# ahu.glob

Compile a glob, or a set of globs, and ask which match a path. The
semantics are those of Rust's `globset`.

```kai
import ahu.glob

fn sources(paths: [String]) : Result[[String], String] {
  let logs = glob.compile("**/*.log", true)!
  let vendor = glob.compile("vendor/**", true)!
  let excluded = glob.set([logs, vendor])
  Ok(paths |? (p => not glob.is_match(excluded, p)))
}
```

## Syntax

| Pattern | Matches |
|---|---|
| `*` | any run of characters |
| `?` | any one character |
| `[a-z]`, `[!a-z]` | one character in, or outside, the class |
| `{a,b}` | either alternative; alternatives may nest |
| `\x` | the character `x` itself |
| `**/x` | `x` at any depth, the top included |
| `x/**` | everything inside `x`, not `x` itself |
| `a/**/b` | `a/b`, or `b` any number of directories below `a` |
| `**` | every path |

`**` is recursive only next to a separator or the pattern's ends;
anywhere else it is two `*`.

A glob matches the whole path, never a part of it. Paths use `/`.

## API

| Function | Result |
|---|---|
| `compile(pattern, literal_separator)` | `Ok(Glob)`, or a message naming the pattern and what is wrong |
| `matches(g, path)` | whether one glob matches |
| `set(globs)` | a `GlobSet` |
| `matching(s, path)` | positions in `globs` of those that match, ascending |
| `is_match(s, path)` | whether any matches |

With `literal_separator`, `*`, `?` and classes stop at `/`, as in
ignore files. Without it they cross directories, so `*.min.js` matches
`a/b/c.min.js`.

## Performance

Each pattern is classified when it is compiled. A literal, a base name
(`**/node_modules`), a suffix (`**/*.log`) or a prefix (`src/**`) is
answered with one string comparison; other patterns run a backtracking
matcher, after rejecting paths that lack a literal the pattern requires.
A set looks literals and extensions up in maps, so asking it does not
visit every pattern.
