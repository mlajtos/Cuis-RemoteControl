# Cuis-RemoteControl

A tiny HTTP bridge for driving a live [Cuis Smalltalk](https://cuis-smalltalk.github.io/) image from the outside — evaluate code and grab screenshots over `curl`. Built for agent / tooling workflows and remote development against a running image.

> ⚠️ **Security.** `/eval` executes arbitrary Smalltalk sent over plain HTTP with **no authentication**. This is a development tool: it listens on `localhost:2347` and must never be exposed to an untrusted network. Anyone who can reach the port has full control of your image (and machine).

## Endpoints

Served on `http://localhost:2347` (see `RemoteControl class >> port`).

### `POST /eval`

Body = Smalltalk source. The response is the `printString` of the result.

- **200** — success (result `printString`).
- **400** — `Undeclared variable: <name>` (a capitalized global / class the image doesn't have).
- **500** — a header line `ClassName: message`, then a short stack trace trimmed at your `DoIt` frame.

Benign `Notification`s are auto-resumed. Bodies are handled as UTF-8, so non-ASCII source is safe.

**Author initials must be set before compiling.** Cuis stamps every compiled method with the author's initials; if they are unset it opens a blocking dialog — invisible over the bridge, so the image appears to hang at 100% CPU. `/eval` therefore refuses requests with **400** while initials are unset, telling you exactly what to run. Ask the human operator for their name and initials, then:

```smalltalk
Utilities setAuthorInitials: 'XY' name: 'Your Name'
```

Set it once per image; it persists across snapshots.

```bash
curl -s -X POST --data-binary '3 + 4' http://localhost:2347/eval
# => 7
```

Prefer sending source from a file — it sidesteps the two compounding quoting layers (shell `'…'` and Smalltalk `''…''`):

```bash
curl -s -X POST --data-binary @snippet.st http://localhost:2347/eval
```

### `GET /screenshot`

Returns a PNG of the world.

| Query | Meaning |
|---|---|
| *(none)* | the whole world (clean re-render) |
| `?morph=ClassName` | crop to the first morph of that class |
| `?id=<identityHash>` | crop to one specific morph |
| `?x=&y=&w=&h=` | explicit crop rectangle |
| `?pad=<n>` | margin around a morph crop |
| `?raw=1` | capture the live `Display` buffer (shows drag trails / uninvalidated regions) instead of a clean re-render |

```bash
curl -s -o shot.png 'http://localhost:2347/screenshot?morph=SystemWindow&pad=8'
```

## Compiling methods: `safelyCompile:classified:`

The package adds one extension — `ClassDescription >> safelyCompile:classified:` — for installing methods over `/eval` with the safety a bridge caller wants: noisy `Notification`s resumed so they can't poison the compile, the method stamped via `Utilities changeStamp`, and `Smalltalk forceChangesToDisk` run so `#authorAndStamp` is readable immediately.

```smalltalk
Object safelyCompile: 'greeting ^ ''hello''' classified: 'demo'
```

## For agents: reflect, don't grep

The image is the source of truth — `.pck.st` and `.changes` files on disk are serialization artifacts that can lag or diverge from what's actually running. **Always interrogate the live image over `/eval`; never search or edit package files on disk unless the human explicitly asks for it.** Everything you'd grep for has a reflective query:

| You want | Ask the image |
|---|---|
| a method's source | `(Morph >> #drawOn:) sourceCode` |
| a class's selectors | `Morph selectors asSortedCollection asArray` (class side: `Morph class selectors`) |
| does this class exist? | `Smalltalk includesKey: #SomeName` |
| implementors of a selector | `Smalltalk allImplementorsOf: #drawOn:` |
| senders of a selector | `Smalltalk allCallsOn: #drawOn:` |
| a class's definition & comment | `Morph definition` / `Morph comment` |
| instance variables | `Morph allInstVarNames` |
| subclasses / superclasses | `Morph subclasses` / `Morph allSuperclasses` |
| a method's category | `Morph organization categoryOfElement: #drawOn:` |
| classes in a package | `(CodePackage installedPackages detect: [:p \| p packageName = 'X']) classes` |
| live instances | `SomeClass allInstances` |

Everything grep does, the image does better — scoped to what actually runs:

| grep habit | Ask the image instead |
|---|---|
| grep a string in method bodies | `Smalltalk allMethodsWithSourceString: 'foo' matchCase: false` |
| grep with a wildcard pattern | `Smalltalk allMethodsSourceStringMatching: '*foo*bar*'` |
| grep body text under one class hierarchy | `Smalltalk allMethodsWithSourceString: 'foo' matchCase: false scopeClass: Morph includeSubclasses: true includeSuperclasses: false` |
| find a string/symbol literal | `Smalltalk allMethodsWithString: 'foo'` |
| grep for a selector fragment | `Symbol selectorsContaining: 'foo'` |
| selector by pattern | `Symbol selectorsMatching: 'draw*On:'` |
| fuzzy selector from a typo | `Symbol possibleSelectorsFor: 'drawon'` |
| find a class by name fragment | `Smalltalk classNames select: [:n \| n includesSubString: 'Morph']` |
| grep class comments | `Smalltalk browseClassCommentsWithString: 'foo'` *(opens a browser — prefer the queries above for programmatic use)* |

The `allMethods…` queries answer collections of `MethodReference`s — each responds to `actualClass`, `selector`, and `sourceCode`, so you can chain straight into reading the hits.

Compile with `safelyCompile:classified:` (below), then **verify by reading the source back** — not by checking that a symptom went away. To persist a package to disk, use `pkg save` from inside the image, never a text editor.

## Install

Dependencies (declared in the package, resolved automatically when available on your code path):

- **`WebClient`** — the HTTP server (`WebServer`, `WebUtils`)
- **`Graphics-Files-Additional`** — PNG encoding (`PNGReadWriter`)

File in `RemoteControl.pck.st` (Installed Packages window, or `Feature require: 'RemoteControl'` with the file on your path), then start the server:

```smalltalk
RemoteControl start.        "listen on localhost:2347"
RemoteControl isRunning.    "=> true"
RemoteControl stop.         "shut down"
```

## License

MIT — see [LICENSE](LICENSE).
