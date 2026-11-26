# ahu.ignore

`.gitignore` and `.ignore` semantics, and a directory walk that applies
them, following Rust's `ignore` crate.

```kai
import ahu.ignore

fn main() : Int / Stdout + File + Env {
  let found = ignore.walk(".")
  list.each(found.files, f => Stdout.print(f))
  list.each(found.errors, e => Stdout.print("#{e.dir}: #{e.reason}"))
  0
}
```

## The walk

`walk(root)` returns the files under `root` that no ignore file hides:

- depth first, each directory's entries sorted by name;
- hidden files included, `.git` left out;
- an ignored directory is never read, so a rule cannot re-include a file
  inside it;
- symbolic links and special files are not followed or listed;
- a directory that cannot be read is reported in `errors`;
- `root` itself is never filtered, and a `root` that is a file is the one
  file found.

`walk_skipping(root, skip)` also leaves out what `skip(path, is_dir)`
accepts. A skipped directory is never read.

## Precedence

From highest to lowest, the first source with a matching rule decides:

1. `.ignore`
2. `.gitignore`
3. the repository's `.git/info/exclude`
4. the global excludes file: `core.excludesFile` from the user's git
   configuration, else `git/ignore` under `$XDG_CONFIG_HOME` (or
   `~/.config`)

Within one source, the file in the deepest directory wins. The three git
sources apply only inside a git or jj repository. Ignore files in the
directories above `root` apply too, looked up from its canonical path.

## Rules

- Blank lines and lines that start with `#` are skipped; `\#` and `\!`
  are the characters themselves.
- Trailing spaces are dropped unless escaped.
- `!` re-includes. The last matching line of a file decides.
- A leading or inner `/` anchors the pattern to the file's directory; a
  pattern without one matches at any depth.
- A trailing `/` matches directories only.
- A trailing `/**` matches what is inside the directory.
- Globs are [`ahu.glob`](glob.md) with a literal separator. An unclosed
  `[` is the character itself; a line that still does not compile is
  skipped.

## Matching one file's rules

`parse(root, text)` reads the text of an ignore file that sits in `root`.
`matched(m, path, is_dir)` answers `Ignored`, `Whitelisted` or
`Unmatched`, and `is_empty(m)` says whether the file holds no rules.
