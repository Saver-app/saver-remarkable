# Architecture

## Overview

```
┌─────────────────────┐        ┌──────────────────────────┐        ┌────────────────────┐
│  Saver web/mobile    │        │  Saver backend           │        │  reMarkable tablet  │
│  app (flutter-app)   │◄──────►│  - todos, bookmarks,     │◄──────►│  saver-remarkable   │
│                      │  Auth  │    habits, tokens        │  HTTPS │  (this repo)        │
│  Settings → generate │        │  - API functions         │  REST  │  Rust client + QML  │
│  device token        │        │                          │        │  UI, runs under xovi │
└─────────────────────┘        └──────────────────────────┘        └────────────────────┘
```

The tablet never authenticates as a normal user. It only knows a bearer
device token and one HTTPS endpoint. All backend access on its behalf goes
through the `remarkableApi` function, scoped to the token's owning user.

Both endpoints are reached through `api.saver-app.com`, a hosting layer that
rewrites onto the backend functions:

| URL | Function |
| --- | --- |
| `POST https://api.saver-app.com/remarkable` | `remarkableApi` |
| `POST https://api.saver-app.com/remarkable/pair` | `remarkablePairing` |

`SAVER_API_BASE_URL` can point straight at a function's raw URL instead, for
developing against a local emulator, and `SAVER_PAIRING_URL` overrides the
pairing endpoint on its own. Both have `config.toml` equivalents,
`api_base_url` and `pairing_url`, which apply to every entry point rather
than only to the process that inherits the variable. The hosting layer caps
a proxied request at 60s.

## Auth: pairing, then device tokens

The tablet has no practical way to type a 43-character token, so linking
uses a QR + short-code handshake modelled on the OAuth 2.0 Device
Authorization Grant (RFC 8628). The long-lived credential underneath is
still a bearer device token.

### Pairing handshake

1. On launch with no token, the tablet POSTs `{ "op": "start" }` to the
   **unauthenticated** `remarkablePairing` function. It gets back a short
   `userCode` (8 chars from an alphabet with no `I`/`O`/`0`/`1`, since those
   are indistinguishable on e-ink) and a secret 32-byte `deviceCode`.
2. The tablet shows a QR to `https://app.saver-app.com/link-device?code=<userCode>`
   plus the `userCode` in large type. The QR is rendered on-device from a
   raw module matrix, see "QR rendering" below.
3. A signed-in user opens that URL and enters the code, calling the
   `approveRemarkablePairing` callable. That marks the pairing record for
   `userCode` as approved, tagged with their user id.
4. The tablet has been polling `{ "op": "poll", userCode, deviceCode }` on
   the server's advertised `interval`. Once approved, the poll itself mints
   the device token, deletes the pairing record, and returns the token
   exactly once.
5. The backend writes the token to `~/.config/saver-remarkable/config.toml`
   and never hands it to the QML frontend.

Two properties worth preserving: the token is only ever minted at poll time,
so no plaintext secret is ever persisted server-side, and knowing a
`userCode` (short, shown on a screen in public) is useless without the
matching `deviceCode`, which never leaves the tablet. Pairings expire after
10 minutes.

### Device tokens

1. `createRemarkableToken` (callable) still exists as a manual escape hatch
   for a tablet that can't reach the pairing endpoint.
2. Tokens are `smk_<32 random bytes, base64url>`. Only the SHA-256 hash is
   stored, keyed by that hash, alongside `{ uid, label, createdAt,
   lastUsedAt }`.
3. Every device request sends `Authorization: Bearer <token>`. The API
   hashes the incoming token and looks up the owning user by that hash: an
   O(1) lookup, no query needed, since the hash is the record's key.
4. Revoking (`revokeRemarkableToken`) deletes that record. The next device
   request then gets `401`.

The token record is readable by its owning user for the settings-page token
list, and writable only by the backend functions themselves.

### Pairing record expiry

Pairing records expire after ten minutes, but expiry is only enforced when a
code is polled or approved, so an abandoned pairing lingers. A scheduled
`cleanupRemarkablePairings` function sweeps these daily. The database also
has a built-in TTL feature that does the same job with no function and no
invocation cost, once turned on for the collection out-of-band. With that in
place the scheduled sweep is redundant, but harmless to keep: it only ever
touches already-expired records.

## Data model

A user's spaces come from their space memberships, one record per space they
belong to. Each space holds three item kinds, todos, bookmarks and habits,
unchanged from the main app's schema (`flutter-app/lib/services/`):

```jsonc
// todo
{
  "text": "Buy milk",
  "isList": false,
  "isDone": false,
  "hasSubTodos": false,
  "parentId": null,       // or a todo id, for sub-todos
  "userId": "<id of creator>",
  "createdAt": "<timestamp>"
}
```

Bookmarks add `title`/`url` in place of `text`/`isDone`. Habits carry a
`requirementMode` (`everyday` or a windowed count), a `streak`, and
per-day/per-window completion counts. `src/models.rs` mirrors all three.

The reMarkable app shows the union of every space the token's user belongs
to, plus one of them marked "active" (`setActiveSpace`) for where new items
land by default. It doesn't currently let you pick a subset of spaces to
show.

## REST protocol (`remarkableApi`)

Single endpoint, POST-only, JSON body with an `op` field. This is
deliberately RPC-style rather than a resourceful REST API, so the Rust
client's `api.rs` stays one method-call-per-op with no path templating:

```
POST https://api.saver-app.com/remarkable
Authorization: Bearer <device token>
Content-Type: application/json
```

| op | Purpose |
| --- | --- |
| `listItems` | Every space the user belongs to, each with its todos, bookmarks and habits, plus which space is active. |
| `setActiveSpace` | Change which space new items default to. |
| `createTodo`, `createBookmark`, `createHabit` | Add an item to a space. |
| `updateTodo`, `updateBookmark`, `updateHabit` | Edit an existing item's fields. |
| `setTodoDone` | Toggle a todo's done state. |
| `setHabitCount` | Log today's count for a habit. |

`createTodo`/`updateTodo` and friends return `{ "id": "..." }` on create.
mutations return `{ "ok": true }` (see `src/api.rs` for exact request
shapes, which line up one-to-one with `SaverClient`'s methods). Non-2xx
responses are `{ "error": "<message>" }`: `401` means the token is
missing/invalid/revoked, `403` means the token's user isn't a member of the
given `spaceId`, `400` means a malformed request.

On the tablet side, the Rust backend exposes the same operations to the QML
frontend over AppLoad IPC as a parallel set of `MSG_*` message types (see
`src/backend.rs`), for example `MSG_CREATE_TODO` (1004) wraps `createTodo`,
and `MSG_SET_HABIT_COUNT` (1009) wraps `setHabitCount`. Each has a matching
`_RESPONSE` type a hundred numbers up. `MSG_GET_CONFIG`/`MSG_SAVE_CONFIG`
are backend-local: they read and write `config.toml`, including the
notebook-capture settings (confirm-before-saving, default space/list,
sidebar visibility) rather than calling the REST API at all.

The system handwriting patch cannot assume that an AppLoad frontend is open,
so it starts the installed backend executable in a temporary capture mode.
That mode loads the same `Config` as the AppLoad backend and proxies only the
capture requests, so the device token and the effective API URL are resolved
in Rust and neither is handed to xochitl's QML. The command executor starts
that process with a minimal environment, so point this path at another
backend through `api_base_url` in `config.toml`: `SAVER_API_BASE_URL` and
`SAVER_DEVICE_TOKEN` only reach the backend that AppLoad launches.

`--capture-config` also reports the tablet's IANA zone, from the same probe
`MSG_GET_CONFIG` uses, because a reminder set in the capture dialog has to be
stamped with a zone and xochitl's QML has no reliable way to name one.
`createTodoFromNotebook` only creates, so a reminder is a second request:
the dialog chains `updateTodo` onto the id the create returned. That call
cannot be started from inside the command executor's own `runningChanged`
handler, so the patch queues it on a short timer.

## Pairing protocol (`remarkablePairing`)

Separate function at `POST https://api.saver-app.com/remarkable/pair`, with
**no** `Authorization` header, since the tablet has no credential yet. Same
POST-with-`op` shape.

### `start`

Request: `{ "op": "start" }`

Response:
```jsonc
{
  "userCode": "ABCDEFGH",
  "deviceCode": "<43-char base64url secret>",
  "verificationUrl": "https://app.saver-app.com/link-device",
  "verificationUrlComplete": "https://app.saver-app.com/link-device?code=ABCDEFGH",
  "expiresIn": 600,
  "interval": 3
}
```

### `poll`

Request: `{ "op": "poll", "userCode": "ABCDEFGH", "deviceCode": "..." }`

Response is one of:
```jsonc
{ "status": "pending", "interval": 3 }
{ "status": "approved", "token": "smk_..." }   // returned exactly once
{ "status": "expired" }
```

A mismatched `deviceCode` is `403`. Poll at the advertised `interval`.

## AppLoad integration

xovi and AppLoad are third-party, community-built tools, not made or
supported by reMarkable. AppLoad's own version is 0.5.3 as tested here.

Confirmed working on a reMarkable Paper Pro ("ferrari", aarch64) and a
reMarkable 2 (armv7) running OS 3.27.3.0. The QML patches applied on the rM2
without qmldiff errors. The core app was also tested on the rM2 with OS
3.25.0.142 and 3.26.0.68. The reMarkable 1 shares the armv7 build and
1404 x 1872 display with the reMarkable 2. Paper Pure is a supported
xovi/Vellum aarch64 target (`rmppure`) with the same display dimensions. Both
are core-package-compatible on that basis, but neither has actually been
tested, and their capture bindings remain unverified. The Paper Pro Move also
shares the aarch64 build, but remains excluded because its different display
dimensions may expose UI issues.

### App layout

AppLoad discovers apps as directories under
`/home/root/xovi/exthome/appload/<id>/`:

```
manifest.json      { id, name, loadsBackend, entry, supportsScaling, canHaveMultipleFrontends }
icon.png           100x100 RGBA
resources.rcc      Qt binary resource bundle where `entry` resolves
backend/entry      native executable, launched with the socket path as argv[1]
```

Build `resources.rcc` with Qt's `rcc --binary` (host Qt is fine, since it's
a data format, not compiled code). `manifest.json`'s `entry` (`/ui/Main.qml`)
is a path *inside* the bundle, so the `.qrc` prefix must match.

### The QML root must not be a Window

AppLoad instantiates the entry QML into a `Loader { anchors.fill: parent }`.
A `Loader` cannot host a `Window`/`ApplicationWindow` as its `item`, so a
`Window` root renders as an empty frame with only the AppLoad-supplied title
bar. The root must be a plain `Item`. Window chrome comes from
`manifest.json`'s `name`.

### Backend IPC

AppLoad creates a `SOCK_SEQPACKET` unix socket at
`/tmp/<id>.sock`, then spawns `backend/entry <socket-path>`. Each message is
two datagrams: an 8-byte native-endian header (`msg_type: u32,
length: u32`) followed by a `length`-byte UTF-8 payload. `0xFFFFFFFF` is
terminate and `0xFFFFFFFE` is "frontend (re)attached". All other numbers are
app-defined, see the REST protocol section above for what `saver-remarkable`
actually sends. The QML side uses `AppLoad { applicationID }` from
`net.asivery.AppLoad 1.0`, with `sendMessage(type, text)` and
`onMessageReceived(type, contents)`.

**The empty-payload trap.** A zero-length payload is still a real queued
datagram. If the backend skips the payload `recv` when `length == 0`, that
datagram stays queued, and the *next* header `recv` consumes it and returns
`0`, indistinguishable from an orderly shutdown. The backend then exits and
AppLoad tears the app down a beat after its first reply, which presents as
"the app opens, flashes its first screen, and closes". Always perform the
payload `recv`, even for `length == 0`, regardless of whether the error
check that follows it is conditional. This cost most of a day. Do not
re-introduce it.

Because the app dies with its backend process, any backend crash or early
`return` reads on-device as "the app won't open". `eprintln!` from the
backend lands in `journalctl -u xochitl`, which is the only real debugger
here.

### Restarting xochitl the right way

Always restart with `bash /home/root/xovi/start`, never `systemctl restart
xochitl`. xovi is loaded by an `LD_PRELOAD` in a systemd drop-in that lives
on a tmpfs, so any reboot silently removes it. Restarting the unit on its
own then brings xochitl up with no xovi at all: no AppLoad, no Saver app, no
QML patches, and a completely silent journal that looks exactly like a
broken build. `install-device.sh` always goes through the start script for
this reason. A running app also keeps its old `resources.rcc` and backend,
so close and reopen Saver from the AppLoad menu after reinstalling.

To confirm a QML patch landed:

```sh
ssh root@TABLET "journalctl -u xochitl --no-pager | grep qmldiff | tail -20"
```

`Configured hashtab rules.` means the rules file parsed. A `Processing file
<path>` line means the rules were applied to that file. A parse error drops
every rule in the file, so a single bad line anywhere makes the
selection-menu button vanish rather than misbehave: see the header of
`packaging/qmldiff/saver-selection.qmd` for the traps that cause one. If the
hashtable itself is missing, rebuild it on-device (restarts the GUI, may
prompt for the passcode):

```sh
ssh root@TABLET /home/root/xovi/rebuild_hashtable
```

`packaging/appload/icon.png` is the Saver mark from the Flutter app's
`assets/icons/Square_icon.png`, scaled to the 100x100 RGBA AppLoad expects:

```sh
sips -s format png -z 100 100 ../flutter-app/assets/icons/Square_icon.png \
    --out packaging/appload/icon.png
```

The colour is kept rather than flattened to line art, since the Paper Pro's
panel is colour e-ink and the yellow actually renders.

### QR rendering

`src/pairing.rs` emits the QR as `{ size, modules }` where `modules` is a
row-major run of `'1'`/`'0'`, and `qml/PairingPage.qml` paints it onto a
`Canvas`. This avoids both an image encoder in the backend and any
dependency on an SVG/image plugin being present in xochitl's QML runtime.

## Packaging

Vellum is apk-based, so `packaging/vellum/VELBUILD` is an `APKBUILD`-shaped
recipe. It builds two packages from one source tarball, both published to
Vellum's stable repository as of 0.1.1:

| Package | Contents | Extra dependencies |
| --- | --- | --- |
| `saver-remarkable` | `manifest.json`, `icon.png`, `resources.rcc`, `backend/entry` | `appload>=0.5.3` |
| `saver-remarkable-capture` | `saver-sidebar.qmd`, `saver-selection.qmd` | matching `saver-remarkable` version/revision, `qt-resource-rebuilder`, `qt-command-executor`, `remarkable-os>=3.26`, `remarkable-os<3.28` |

The split exists because the QML patches are firmware-specific and collide
with other mods, while the core app is neither. `saver-remarkable-capture`
declares `!convert-to-text-remover` and `!retaskable-capture`, so apk refuses
the combination up front instead of letting someone install two mods that
patch the same selection menu, and its `remarkable-os` bounds keep it off
firmware whose private xochitl paths, anchors, and handwriting APIs have not
been checked. The upper bound is a guard for unverified releases rather than a
known break at 3.28. Device support for the core package does not imply capture
support. The capture bindings still need verification on each model. The core
package carries
`!rmppm`, which keeps it off Paper Pro Move until its different display
dimensions have been tested. reMarkable 1 and Paper Pure are allowed because
their architecture and display dimensions match existing supported builds.

The capture subpackage pins `saver-remarkable=$pkgver-r$pkgrel` because its QML
patches invoke the core binary's `--capture-config` and `--capture-api` CLI
contract. This prevents apk from combining capture with a different core
release.

`package()` installs to exactly the paths `install-device.sh` writes, so a
package install and a source install produce the same on-device layout and
can replace each other. Only the source path has a `SKIP_QMLDIFF` equivalent.
with packages, the patches are present iff `saver-remarkable-capture` is.

`postdeinstall` deletes `/home/root/.config/saver-remarkable` only when
`VELLUM_PURGE=1`, so `vellum del` leaves a device paired while
`vellum purge` unlinks it locally. Neither revokes the token server-side.

Cutting a release means tagging `vX.Y.Z`, setting `pkgver` to match,
refreshing `sha512sums` against that tag's GitHub tarball, and submitting the
recipe to Vellum's package repository. `pkgrel` resets to 0 with a new
`pkgver` and increments for a packaging-only rebuild. The tarball checksum is
over the *tag*, so re-tagging an already-published version invalidates it,
which is why 0.1.1 needed a second checksum commit.

## Still to do

- Confirming reMarkable 1 and Paper Pure actually run the app, not just that
  they match an existing build target and display size.
- Adapting and testing the UI on Paper Pro Move. Until then the package
  excludes it, so that device needs a source build.
- The tablet needs Wi-Fi: the USB link (10.11.99.1) carries no default
  route, so pairing can't reach the backend over USB alone.
