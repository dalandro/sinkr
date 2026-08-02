# File sinkers — design

**Date:** 2026-07-31
**Slice:** 1b (follows tickets; precedes herdr presence)

## The problem

A ticket records a loose end, but the material the loose end is made of lives
elsewhere: a script under a worktree, a screenshot of the bug, a log from a run
that has since been swept. A week later the ticket says what you meant to do and
nothing about where the work is.

Two distinct needs, and this slice serves both with one record:

1. **Get me back to the file.** A path, so opening the ticket puts you (or an
   agent) one step from the real thing.
2. **Keep the content.** Screenshots get renamed, downloads get deleted. Some
   files must survive in the ticket even when the original is gone.

## The consumer that shapes the design

The primary reader is not only a human in a browser. The target use is telling
Claude *"see sinkr ticket s-16, let's continue"* — so the ticket's contents must
be reachable from a terminal, without a browser, and ideally without the server
running.

Two consequences drive everything below:

- **A path beats embedded content.** An agent with filesystem access reads a
  path fresh and reads only what it needs. Embedded content is a stale copy that
  also costs tokens. So a path is the anchor; a stored copy is the fallback.
- **Snapshots are files on disk, not database blobs.** A blob in SQLite has no
  path, so the one case that matters most — the original is gone — would be the
  one case an agent can't just `Read`. Content-addressed files on disk give every
  attachment, pinned or not, a path.

The design goal collapses to a single testable property:

> Every file line the CLI prints ends in a path that can be read.

## Data model

Vocabulary is already settled in `HANDOFF.md`: a **sinker** is "a ticket's
optional link down to where the work actually lives". A file is its first type.
Sinker types stay rows rather than columns, so slice 2 adds `:worktree` and
`:herdr_space` without a migration.

### `sinkers`

| column | type | notes |
|---|---|---|
| `ticket_id` | FK → tickets, on_delete: delete_all | |
| `type` | string, `Ecto.Enum` | only `:file` registered in this slice |
| `value` | string | absolute path, or a bare filename when `origin: :upload` |
| `origin` | string, `Ecto.Enum` | `:path \| :upload` |
| timestamps | utc_datetime | |

`origin` earns its column: a dropped screenshot has no path, so its `value` is a
filename that must never be stat'd. Without the flag, "file is missing from
disk" and "there was never a disk file" render identically and both look like
breakage.

### `snapshots`

`has_one` on a sinker — a copy you deliberately took.

| column | type | notes |
|---|---|---|
| `sinker_id` | FK → sinkers, on_delete: delete_all, unique | one copy per sinker |
| `sha256` | string | lowercase hex; locates bytes in the store |
| `filename` | string | original name, for download and display |
| `mime` | string | from `MIME.from_path/1` |
| `byte_size` | integer | |
| `pinned_at` | utc_datetime | when you took the copy |

Bytes are **not** in this table. Keeping the db small keeps it copyable, keeps
list rendering from dragging megabytes through Ecto, and gives the bytes a path.

## Stored vs derived

The rule `HANDOFF.md` sets for presence-vs-status applies here unchanged:

- **Stored:** whether a sinker is pinned. That is a fact about a copy you made.
- **Derived at render, never written:** whether the path still exists on disk.
  That is a fact about the world right now.

Nothing in this slice writes `ticket.status`.

## Modules

### `Sinkr.SnapshotStore`

Content-addressed file store. Interface:

- `put(source_path)` → `{:ok, %{sha256:, byte_size:}}` | `{:error, reason}`
- `put_bytes(bytes, filename)` → same shape
- `path(sha256)` → absolute path to the bytes
- `exists?(sha256)` → boolean

Layout `<root>/<first 2 hex>/<remaining hex>`, so a directory never accumulates
thousands of entries. Identical files dedup for free — `put` on bytes already
stored is a no-op returning the same hash.

Root comes from `Application.fetch_env!(:sinkr, :snapshot_root)`:

- dev/prod: `~/.local/share/sinkr/snapshots` (honouring `XDG_DATA_HOME`)
- test: a tmp directory, cleaned per test — the suite must never touch the real store

### `Sinkr.Tickets` (existing context, extended)

- `attach_file(ticket, path)` — expands `~`, makes absolute, `origin: :path`.
  Returns `{:error, :enoent}` if nothing is at the path *at attach time*: a path
  that was never right is a typo, and worth catching immediately. A path that
  goes missing later is expected, and renders as `missing`.
- `attach_upload(ticket, %{filename:, tmp_path:})` — stores bytes and pins in one
  step; an upload with no snapshot would be a record of nothing
- `pin_sinker(sinker)` — reads `value`, copies to store, inserts snapshot
- `unpin_sinker(sinker)` — deletes the snapshot row, leaves the bytes
- `detach_sinker(sinker)`
- `list_sinkers(ticket)` — snapshot preloaded
- `file_status(sinker)` — `:on_disk | :missing | :upload`, derived, no writes

### `Sinkr.Tickets.Markdown`

`render(ticket, entries)` → markdown string, where each entry is
`%{sinker: sinker, status: :on_disk | :missing | :upload, snapshot_path: path | nil}`.
Pure: no repo, no filesystem, no clock. Status and snapshot path are computed by
the caller and passed in, so the function is testable with no fixtures on disk,
and the CLI, a future `.md` route, and a future MCP tool all render identically.

Output shape:

```
# s-16 — Validator frontmatter scalars
Status: active · Category: bug · Priority: Soon (P2)
Next step: make the scalar check reject arrays

## Files
- /home/daniel-c/skillz-wt/validator-frontmatter-scalars/ci/validate.mjs
- Screenshot 2026-07-31.png — pinned copy: /home/daniel-c/.local/share/sinkr/snapshots/ab/cdef…
- /tmp/run.log — MISSING; pinned copy: /home/daniel-c/.local/share/sinkr/snapshots/ef/1234…
```

### `Sinkr.CLI`

Commands `show <ref>` and `list`. All behaviour lives in `run/1`, which returns
`{:ok, output}` / `{:error, message}` and is tested directly; `main/1` prints,
halts, and stays too thin to need tests.

**Starts `Sinkr.Repo` only — never the endpoint**, or it fights a running server
for port 4040. SQLite is in WAL mode, so reads while the server is live are safe.

Shipped as `bin/sinkr`, a shell wrapper around
`mix run --no-start -e 'Sinkr.CLI.main(...)'`, not as a compiled escript: an
escript doesn't evaluate `config/runtime.exs`, so the snapshot root and database
path would have to be re-derived in a second place. The wrapper costs ~300 ms
more per invocation and keeps one config path.

Measured on this machine 2026-07-31: bare BEAM boot 155 ms; full app boot plus
one ticket query via `mix run` 561 ms. Reusing a running server's BEAM over
distributed Erlang could save at most ~400 ms, at the cost of node names,
cookies, and an is-it-up branch with its own failure modes. Rejected. The CLI
always boots its own Repo — one code path, server up or down.

## Web UI

A "Files" section on the open ticket, below Next step:

- Path field + Attach button.
- Drop zone via `allow_upload(:files, max_entries: 5, max_file_size: 20 MB)`.
  A dropped file is copied and pinned immediately, `origin: :upload`.
- One row per sinker: monospace path or filename, a `pinned` badge, a `missing`
  badge, a thumbnail when the snapshot mime is an image, and pin/unpin plus
  detach actions.

`GET /snapshots/:sha256` serves bytes with `send_file`. It **must** reject any
sha that is not 64 lowercase hex characters before touching the filesystem —
that parameter otherwise reaches a path join — and 404 an unknown hash.

## Testing

TDD throughout, in this order. Each stage is tested before it is implemented.

1. `SnapshotStore` — put from path, put bytes, hash stability, dedup, `exists?`,
   error on unreadable source
2. `Sinker` changeset — required fields, unknown type rejected, `origin` values
3. `Tickets` — attach/pin/unpin/detach, `list_sinkers` preloads,
   `file_status` for all three cases, cascade on ticket delete
4. `Markdown` — plain path, pinned, missing-with-pin, upload, no files at all
5. `CLI` — `show` for a real ref, unknown ref exits non-zero, `list`
6. LiveView — attach by path, detach, pin, thumbnail rendered for a pinned image
7. Snapshot route — serves bytes, rejects non-hex sha, 404s unknown hash

## Out of scope, deliberately

- **Garbage collection.** Dedup means deleting a snapshot row must not delete
  bytes another sinker shares. Needs a `sinkr gc` that counts references; not
  this slice. Until then, unpinning leaks bytes, knowingly.
- Other sinker types (`:worktree`, `:session`, `:herdr_space`) — slice 2.
- CLI writes (`sinkr attach`). A CLI write cannot refresh an open browser tab;
  there is no PubSub across OS processes.
- Line ranges (`file.ex:42-58`).
- Inline preview of text files.
- An MCP server. `Markdown.render/1` is the seam it will use when it arrives.
