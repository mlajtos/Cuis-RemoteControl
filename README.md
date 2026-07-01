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
