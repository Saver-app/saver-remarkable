# Saver for reMarkable

Bring your [Saver](https://saver-app.com) todos, bookmarks and habits to a
reMarkable tablet. Browse every Saver space, update items from the e-ink UI,
and turn selected handwriting into a synced todo.

This is the official Saver integration, and its tablet layer is an unofficial
mod built on the community projects [xovi](https://github.com/asivery/xovi),
[AppLoad](https://github.com/asivery/rm-appload) and
[qt-resource-rebuilder](https://github.com/asivery/rm-xovi-extensions).
It is not affiliated with or endorsed by reMarkable.

**Status:** Released. `saver-remarkable` 0.2.0 is in Vellum's stable
repository, so installing it on a supported device takes two commands and no
build toolchain. Building from source is still supported, and is the only
option on Paper Pro Move.

**Public guide:** See the
[Saver for reMarkable guide](https://docs.saver-app.com/remarkable).

> **Warning:** Installation requires root SSH access and runs third-party code
> inside the tablet's main UI process. On Paper Pro, Paper Pro Move, and Paper
> Pure, enabling [Developer Mode][developer-mode]
> factory-resets the tablet and weakens its security. Sync or back up your data
> before enabling it. reMarkable 1 and 2 do not require that Developer Mode
> step, but this software is still unofficial and installed at your own risk.

[developer-mode]: https://developer.remarkable.com/documentation/developer-mode

## Features

- **Todos and lists**: create and edit todos, check them off, organize them in
  lists and add sub-todos.
- **Bookmarks and folders**: create and edit bookmarks, including nested
  bookmark folders.
- **Scheduled habits**: log daily counts and track streaks for daily or
  window-based goals.
- **Multiple spaces**: switch among all Saver spaces you belong to and set
  the default space for new items.
- **Simple pairing**: link the tablet with a QR code or the 8-character code
  shown on its screen. No long token needs to be typed.
- **Handwriting capture**: select handwriting in a notebook and send the
  recognized text to Saver, with an optional space/list confirmation step.

## Compatibility

| Device | Target | Core Vellum package | Status |
| --- | --- | --- | --- |
| Paper Pro | aarch64 | Yes | Core tested on reMarkable OS 3.27.3.0 |
| Paper Pro Move | aarch64 | No, build from source | Core untested. Capture blocked by the core dependency |
| Paper Pure | aarch64 | Yes | Core untested. Capture bindings unverified |
| reMarkable 2 | armv7 | Yes | Core tested on OS 3.25.0.142, 3.26.0.68, and 3.27.3.0. QML patches apply on 3.27.3.0 |
| reMarkable 1 | armv7 | Yes | Core untested. Capture bindings unverified |

reMarkable 1 and Paper Pure are expected to work because each uses an existing
build target and the same 1404 x 1872 display size as reMarkable 2. They have
not yet been confirmed on hardware. A **Yes** above only describes the core
package. It does not establish compatibility for handwriting capture. The core
package remains incompatible with Paper Pro Move because its different display
dimensions may need UI changes. Build from source to try it.

The aarch64 target is `aarch64-unknown-linux-gnu`. The armv7 target is
`armv7-unknown-linux-gnueabihf`.

The tested AppLoad version is 0.5.3. Firmware updates can break xovi or the
optional QML patches even when the Rust target stays the same, so treat only
the confirmed combinations above as known working.

`saver-remarkable-capture` additionally requires reMarkable OS 3.26 or newer
and older than 3.28, `qt-resource-rebuilder`, `qt-command-executor`, and a
manual hashtable build. Its patches bind to private xochitl file paths,
component anchors, and handwriting APIs, all of which must be checked on each
device and firmware release. The upper bound is a guard for unverified
firmware, not a known incompatibility at 3.28. On OS 3.25 the core app installs,
but the sidebar entry and handwriting action are unavailable.

## Current limitations

- Remote changes require **Refresh**. There is no background sync or
  persistent offline cache.
- The tablet cannot delete items or open bookmark URLs.
- Sidebar and handwriting patches are firmware-specific and may need updates
  after a reMarkable OS release.

## Requirements

### Tablet

- A Saver account and a tablet with internet access. All Saver operations and
  handwriting recognition need internet, normally over Wi-Fi. The USB network
  at `10.11.99.1` does not provide an internet route by itself.
- Root SSH access. Paper Pro, Paper Pro Move, and Paper Pure need Developer
  Mode.
  reMarkable 1 and 2 expose SSH without it.
- [Vellum](https://github.com/vellum-dev/vellum) installed on the tablet. As a
  manual alternative, install xovi and AppLoad too, plus
  qt-resource-rebuilder if you want the optional QML actions. The easiest way
  to bootstrap Vellum is
  [reManager](https://github.com/rmitchellscott/reManager), available for
  Linux, macOS and Windows.
- The optional sidebar and handwriting actions need
  `qt-resource-rebuilder`, `qt-command-executor`, and the resource rebuilder's
  initial hashtable setup. Installing `saver-remarkable-capture` pulls both
  extensions in automatically. The hashtable stays a one-time manual step.
  The core AppLoad app works without any of them.

### Build computer (source installs only)

- A Unix-like environment with Bash, `ssh` and `scp`.
- Rust and Cargo, installed with [rustup](https://rustup.rs/).
- A GNU Linux cross-compiler/linker for the tablet's architecture. Installing
  a Rust target alone does not install this linker.
- Qt 6's `rcc` executable for bundling the QML interface.

The installer has been tested on macOS. Linux is expected to work but is
untested. Native Windows is not currently documented.

## Install with Vellum

Vellum resolves xovi, AppLoad and the rest of the dependency chain itself, so
on a supported device this is the whole installation. Replace `TABLET` with
`10.11.99.1` over USB, or the tablet's Wi-Fi address.

1. Install [Vellum](https://github.com/vellum-dev/vellum) on the tablet if it
   is not there already. [reManager](https://github.com/rmitchellscott/reManager)
   bootstraps it from Linux, macOS or Windows.
2. Install the app:

```sh
ssh root@TABLET '/home/root/.vellum/bin/vellum add saver-remarkable'
```

3. Optionally add the sidebar entry and handwriting capture:

```sh
ssh root@TABLET '/home/root/.vellum/bin/vellum add saver-remarkable-capture'
```

4. Restart the tablet UI through xovi so the app and any patches load:

```sh
ssh root@TABLET \
  'setsid bash /home/root/xovi/start >/tmp/xovi-start.log 2>&1 </dev/null &'
```

Then [pair the tablet](#pair-the-tablet).

`saver-remarkable-capture` pulls in `qt-resource-rebuilder` and
`qt-command-executor`, and refuses to install next to the incompatible
`retaskable-capture` or `convert-to-text-remover` mods. It also needs the
resource rebuilder's hashtable, see
[Finish the optional UI integration](#finish-the-optional-ui-integration).

## Install from source

Build from source to develop on the app, or to run it on a device the
published package excludes. Run all commands from the repository root.

### 1. Prepare the tablet

Enable root SSH access and install Vellum, or manually install the required
components listed above. Connect the tablet over USB, wake it, and confirm
that SSH works:

```sh
ssh root@10.11.99.1 true
```

The device password appears at the bottom of **Copyrights and Licenses** in
the tablet's settings. On current Paper Pro software, the full path is
**Settings → General → Help → About → Copyrights and Licenses**. The installer
automatically tries `~/.ssh/id_remarkable`. Add
`-i ~/.ssh/id_remarkable` to manual `ssh` commands if needed.

To deploy a Paper Pro, Paper Pro Move, or Paper Pure over Wi-Fi, enable Wi-Fi
SSH while connected over USB, then use the tablet's Wi-Fi address during
installation:

```sh
ssh root@10.11.99.1 rm-ssh-over-wlan on
```

### 2. Install the Rust target and linker

Install the target for your tablet:

```sh
rustup target add aarch64-unknown-linux-gnu      # Paper Pro / Move / Pure
rustup target add armv7-unknown-linux-gnueabihf  # reMarkable 1 / 2
```

Then configure Cargo to use the corresponding GNU cross-linker. For example,
messense's macOS toolchains use these names when installed on `PATH`:

```toml
[target.aarch64-unknown-linux-gnu]
linker = "aarch64-unknown-linux-gnu-gcc"

[target.armv7-unknown-linux-gnueabihf]
linker = "armv7-unknown-linux-gnueabihf-gcc"
```

Use an absolute path if your toolchain is not on `PATH`. Debian-based Linux
toolchains commonly call the same binaries `aarch64-linux-gnu-gcc` and
`arm-linux-gnueabihf-gcc`. On macOS,
[messense's cross-toolchains](https://github.com/messense/homebrew-macos-cross-toolchains)
provide both targets through Homebrew or downloadable release archives.

### 3. Install Qt's resource compiler

Use your system's Qt 6 package when available. On macOS, `aqtinstall` can
install only the required Qt archive:

```sh
python3 -m pip install aqtinstall
python3 -m aqt install-qt mac desktop 6.8.2 clang_64 \
  -O "$HOME/Qt" --archives qtbase
```

The resulting `rcc` is normally at
`$HOME/Qt/6.8.2/macos/libexec/rcc`. On Linux it is often at
`/usr/lib/qt6/libexec/rcc`. Use the path supplied by your Qt package.

### 4. Build and install

The script syntax is `./install-device.sh [host] [target]`. Set `RCC` when it
is not at the script's macOS default:

```sh
# Paper Pro / Move / Pure over USB (the default host and target)
RCC=/path/to/rcc ./install-device.sh

# Paper Pro / Move / Pure over Wi-Fi
RCC=/path/to/rcc ./install-device.sh 192.168.1.42

# reMarkable 1 / 2 over USB
RCC=/path/to/rcc ./install-device.sh \
  10.11.99.1 armv7-unknown-linux-gnueabihf
```

Use `SSH_KEY=/path/to/private-key` if the tablet key is stored somewhere
other than `~/.ssh/id_remarkable`.

The script connects, builds the Rust backend, bundles the QML UI, and then
uses Vellum to install missing xovi and AppLoad components, plus
qt-resource-rebuilder unless QML patches are skipped. Finally, it copies the
app and optional patches and restarts the tablet UI through xovi.

To install only the core AppLoad app, without the sidebar or handwriting
patches:

```sh
SKIP_QMLDIFF=1 RCC=/path/to/rcc ./install-device.sh
```

Use this core-only mode if you have the incompatible `retaskable-capture` or
`convert-to-text-remover` QML mod installed. `SKIP_QMLDIFF` does not remove
patches from an earlier installation. Remove both Saver `.qmd` files using the
commands under [Update or remove](#update-or-remove) before switching modes.

## Finish the optional UI integration

Either installation path needs this once, and only for the sidebar and
handwriting actions.

`qt-resource-rebuilder` needs a one-time hashtable build on the tablet. If the
installer reports that it is missing, or if the sidebar entry does not appear
after installing `saver-remarkable-capture`, run:

```sh
ssh root@TABLET /home/root/xovi/rebuild_hashtable
```

Replace `TABLET` with the same USB or Wi-Fi host as before. This restarts the
tablet UI and may ask for the device passcode. Afterwards, rerun the installer
(source install) or restart the UI through `/home/root/xovi/start` (Vellum
install) so the sidebar and selection-menu patches are applied.

## Pair the tablet

1. Make sure the tablet is connected to Wi-Fi.
2. Open **Saver** from the file-browser sidebar or the AppLoad launcher.
3. Scan the QR code with another device, or open the
   [Saver web app](https://app.saver-app.com), go to **Settings → reMarkable
   tablet → Enter code from tablet**, and enter the code shown on the tablet.
4. Approve the connection. Saver finishes linking and loads your spaces and
   items automatically.

Pairing codes expire after 10 minutes. Changes made in Saver on another
device appear when the tablet app opens or when you tap **Refresh**.

## Capture a handwritten todo

The optional QML patch uses reMarkable's handwriting-recognition service, so
the tablet must be online and signed in to a reMarkable account.

1. Select handwritten strokes with the notebook lasso tool.
2. Tap the Saver checkmark action in the selection menu.
3. Review the recognized text and choose a Saver space/list, or save directly
   using the defaults configured under **Saver → Settings**.
4. Optionally tap **Reminder** in that dialog to have Saver notify your phone.
   Pick a date and time, and any weekdays it should repeat on. Reminders are
   only offered when the dialog appears, so leave "Ask before saving
   handwritten todos" on if you want them.

## Troubleshooting

- **Pairing or refresh cannot reach Saver:** connect the tablet itself to
  Wi-Fi. USB networking supports deployment but does not provide internet.
- **Paper Pro Wi-Fi deployment cannot connect:** enable it over USB with
  `ssh root@10.11.99.1 rm-ssh-over-wlan on`, then retry with the tablet's
  Wi-Fi address.
- **The sidebar or handwriting action is missing:** check that
  `saver-remarkable-capture` is installed, rebuild the hashtable, rerun the
  installer, and check for `retaskable-capture`, `convert-to-text-remover`, or
  a firmware/QML-patch mismatch.
- **`vellum add` cannot find the package:** refresh the index with
  `vellum update`. If it is still missing, the device or OS version is one the
  package excludes, see [Compatibility](#compatibility), and you need a source
  build.
- **A reinstall appears unchanged:** close Saver completely and reopen it from
  AppLoad so the new backend and `resources.rcc` are loaded.
- **Saver opens and immediately closes:** inspect the xochitl journal for
  backend or AppLoad errors.

In the following commands, replace `TABLET` with `10.11.99.1` or the tablet's
Wi-Fi address. Useful device diagnostics:

```sh
ssh root@TABLET \
  "journalctl -u xochitl --since '-5min' --no-pager | tail -n 200"

ssh root@TABLET \
  "journalctl -u xochitl --no-pager | grep -i qmldiff | tail -n 20"
```

When reporting a problem, include the tablet model, reMarkable OS version,
Rust target, AppLoad version and the relevant journal output.

## Update or remove

To update a Vellum installation, upgrade and restart the UI through xovi:

```sh
ssh root@TABLET '/home/root/.vellum/bin/vellum upgrade'
```

To update a source installation, run `git pull --ff-only` in a Git checkout,
then rerun the same `install-device.sh` command. Either way, close and reopen
Saver after the tablet UI has restarted.

Pairing stores a bearer token in
`/home/root/.config/saver-remarkable/config.toml` with owner-only permissions.
The in-app **Unlink** action removes the local copy, but it does not revoke the
server-side credential. Revoke the tablet in the Saver web app as well when a
device is lost, sold or retired.

To remove a Vellum installation, after revoking the device:

```sh
# Remove the app and the optional patches, keeping the pairing token.
ssh root@TABLET \
  '/home/root/.vellum/bin/vellum del saver-remarkable-capture saver-remarkable'

# Or use purge instead of del to drop the token and handwriting preferences too.
ssh root@TABLET \
  '/home/root/.vellum/bin/vellum purge saver-remarkable-capture saver-remarkable'

ssh root@TABLET \
  'setsid bash /home/root/xovi/start >/tmp/xovi-start.log 2>&1 </dev/null &'
```

Source installs have no uninstaller. Remove only Saver's app directory and QML
patches by hand, then restart xovi:

```sh
ssh root@TABLET \
  'rm -rf -- /home/root/xovi/exthome/appload/com.saverapp.remarkable'
ssh root@TABLET \
  'rm -f -- /home/root/xovi/exthome/qt-resource-rebuilder/saver-sidebar.qmd'
ssh root@TABLET \
  'rm -f -- /home/root/xovi/exthome/qt-resource-rebuilder/saver-selection.qmd'

# Optional: also remove the local token and handwriting preferences.
ssh root@TABLET \
  'rm -rf -- /home/root/.config/saver-remarkable'

ssh root@TABLET \
  'setsid bash /home/root/xovi/start >/tmp/xovi-start.log 2>&1 </dev/null &'
```

xovi, AppLoad and qt-resource-rebuilder are shared dependencies. Keep them if
another tablet mod uses them.

## Development

The tablet UI is QML, loaded by AppLoad from `resources.rcc`. A native Rust
backend communicates with it over AppLoad IPC and sends authenticated HTTPS
requests to Saver. The handwriting patch invokes the same executable's
capture command path, keeping the device token and effective API URL in
Rust. Running the full UI still requires an AppLoad socket, so `cargo run` is
not a standalone desktop preview.

| Path | Purpose |
| --- | --- |
| `src/` | Rust backend, AppLoad IPC, Saver API client, pairing and config |
| `qml/` | Pairing and item-management UI |
| `packaging/appload/` | AppLoad manifest, icon and resource bundle inputs |
| `packaging/qmldiff/` | Optional sidebar and handwriting-capture patches |
| `packaging/vellum/` | `VELBUILD` recipe for the two published Vellum packages |
| `docs/ARCHITECTURE.md` | Protocols, data flow and device debugging notes |

Run the local checks before submitting a change:

```sh
rustup component add rustfmt clippy
cargo fmt --all -- --check
cargo clippy --all-targets --locked -- -D warnings
cargo test --locked
bash -n install-device.sh
```

See [Architecture](docs/ARCHITECTURE.md) for the pairing protocol, API
operations, AppLoad wire format and deeper on-device troubleshooting.

## License

[MIT](LICENSE) © 2026 Paul Gerling.
