#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-10.11.99.1}"
TARGET="${2:-aarch64-unknown-linux-gnu}"
APP_ID="com.saverapp.remarkable"
BIN="target/${TARGET}/release/saver-remarkable"
REMOTE_DIR="/home/root/xovi/exthome/appload/${APP_ID}"
QMLDIFF_DIR="/home/root/xovi/exthome/qt-resource-rebuilder"
RCC="${RCC:-$HOME/Qt/6.8.2/macos/libexec/rcc}"

if [[ -z "${SSH_KEY:-}" && -f "$HOME/.ssh/id_remarkable" ]]; then
    SSH_KEY="$HOME/.ssh/id_remarkable"
fi

CTL="/tmp/.saver-deploy-%C"
SSH_OPTS=(-o ConnectTimeout=20
          -o ControlMaster=auto
          -o ControlPath="$CTL"
          -o ControlPersist=180)
if [[ -n "${SSH_KEY:-}" ]]; then
    SSH_OPTS+=(-i "$SSH_KEY")
fi
ssh_() { ssh "${SSH_OPTS[@]}" "root@${HOST}" "$@"; }
scp_() { scp "${SSH_OPTS[@]}" "$@"; }

cleanup() { ssh -o ControlPath="$CTL" -O exit "root@${HOST}" 2>/dev/null || true; }
trap cleanup EXIT

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

step "Connecting to ${HOST}"
connected=0
for attempt in 1 2 3; do
    if ssh_err=$(ssh_ -o BatchMode=yes true 2>&1); then
        connected=1
        break
    fi
    case "$ssh_err" in
    *"Permission denied"*|*"Too many authentication failures"*|\
    *"Host key verification failed"*|*"HOST IDENTIFICATION HAS CHANGED"*)
        break
        ;;
    esac
    if [[ $attempt -lt 3 ]]; then
        printf '  no answer yet, waiting for the tablet...\n'
        sleep 5
    fi
done

if (( connected )); then
    echo "  connected."
else
    case "$ssh_err" in
    *"Host key verification failed"*|*"HOST IDENTIFICATION HAS CHANGED"*)
        echo "error: ${HOST}'s host key doesn't match a stored one." >&2
        echo "       Expected when you plug in a different tablet: they all" >&2
        echo "       use this address. If this is your other tablet, trust it" >&2
        echo "       alongside the first, then re-run:" >&2
        echo "         ssh-keyscan -t ed25519 ${HOST} >> ~/.ssh/known_hosts" >&2
        echo "       If you weren't expecting it, stop: something else is on" >&2
        echo "       this address." >&2
        exit 1
        ;;
    *"Permission denied"*|*"Too many authentication failures"*)
        echo "  ${HOST} is up, but no SSH key was accepted."
        [[ -n "${SSH_KEY:-}" ]] && echo "  (tried ${SSH_KEY})"
        echo "  Falling back to the device password, asked once then reused."
        echo "  It's in Settings > Help > Copyrights and licenses, at the bottom."
        if ! ssh_ true; then
            echo >&2
            echo "error: could not log in to ${HOST}." >&2
            exit 1
        fi
        echo
        echo "  To stop being asked every time, copy your key over once:"
        echo "    ssh-copy-id -i ${SSH_KEY:-$HOME/.ssh/id_remarkable}.pub root@${HOST}"
        ;;
    *)
        echo "error: can't reach ${HOST} over SSH." >&2
        echo "       Over USB, check the cable and that the tablet is awake." >&2
        echo "       Over Wi-Fi, check the address in Settings > Help > General." >&2
        echo >&2
        echo "$ssh_err" | sed 's/^/       /' >&2
        exit 1
        ;;
    esac
fi

if [[ -z "${SKIP_BUILD:-}" ]]; then
    step "Building backend for ${TARGET}"
    cargo build --release --target "$TARGET"
fi

if [[ ! -f "$BIN" ]]; then
    echo "error: $BIN not found. Drop SKIP_BUILD, or build it first:" >&2
    echo "  cargo build --release --target $TARGET" >&2
    exit 1
fi

if [[ ! -x "$RCC" ]]; then
    echo "error: rcc not found at $RCC. Set RCC=/path/to/rcc" >&2
    exit 1
fi

step "Bundling QML"
"$RCC" --binary -o packaging/appload/resources.rcc packaging/appload/app.qrc

VELLUM=/home/root/.vellum/bin/vellum

ensure_extension() {
    local so="$1" pkg="$2"
    if ssh_ "test -f /home/root/xovi/extensions.d/${so}" 2>/dev/null; then
        echo "  ${pkg}: already installed"
        return 0
    fi
    if ! ssh_ "test -x ${VELLUM}" 2>/dev/null; then
        echo "error: ${pkg} is missing, and Vellum isn't installed to add it." >&2
        echo "       Install Vellum first (reManager can do it), then re-run." >&2
        exit 1
    fi
    echo "  ${pkg}: missing, installing with Vellum..."
    ssh_ "${VELLUM} add ${pkg}"
}

if [[ -z "${SKIP_DEPS:-}" ]]; then
    step "Checking device dependencies"
    if ! ssh_ "test -f /home/root/xovi/xovi.so" 2>/dev/null; then
        if ! ssh_ "test -x ${VELLUM}" 2>/dev/null; then
            echo "error: xovi isn't installed, and neither is Vellum." >&2
            echo "       Install Vellum first (reManager can do it), then re-run." >&2
            exit 1
        fi
        echo "  xovi: missing, installing with Vellum..."
        ssh_ "${VELLUM} add xovi"
    else
        echo "  xovi: already installed"
    fi

    ensure_extension appload.so appload
    if [[ -z "${SKIP_QMLDIFF:-}" ]]; then
        ensure_extension qt-resource-rebuilder.so qt-resource-rebuilder
        if ! ssh_ "test -s /home/root/xovi/exthome/qt-resource-rebuilder/hashtab" 2>/dev/null; then
            echo
            echo "  NOTE: qt-resource-rebuilder has no hashtable yet, so the QML"
            echo "        patches (sidebar entry, handwriting-to-todo) will not"
            echo "        apply. Build it once, on the tablet:"
            echo
            echo "          ssh root@${HOST} /home/root/xovi/rebuild_hashtable"
            echo
            echo "        It restarts the GUI and may ask for your passcode on"
            echo "        the device. Then re-run this script."
        fi
    fi
fi

step "Installing the app to ${HOST}"
ssh_ "mkdir -p ${REMOTE_DIR}/backend; rm -f ${REMOTE_DIR}/backend/entry" || true
scp_ "$BIN" "root@${HOST}:${REMOTE_DIR}/backend/entry"
scp_ packaging/appload/manifest.json \
     packaging/appload/icon.png \
     packaging/appload/resources.rcc \
     "root@${HOST}:${REMOTE_DIR}/"
ssh_ "chmod +x ${REMOTE_DIR}/backend/entry"

if [[ -z "${SKIP_QMLDIFF:-}" ]]; then
    step "Installing the qmldiff patches"
    if ssh_ "test -d ${QMLDIFF_DIR}"; then
        scp_ packaging/qmldiff/*.qmd "root@${HOST}:${QMLDIFF_DIR}/"
    else
        echo "warning: ${QMLDIFF_DIR} missing. Is the qt-resource-rebuilder" >&2
        echo "         extension installed? Skipping the xochitl UI patches." >&2
    fi
fi

step "Restarting xochitl through xovi"
ssh_ "setsid bash /home/root/xovi/start >/tmp/xovi-start.log 2>&1 </dev/null &" || true

printf 'waiting for the tablet'
for _ in $(seq 1 12); do
    sleep 5
    printf '.'
    if ssh_ -o BatchMode=yes true 2>/dev/null; then break; fi
done
echo

step "Result"
if ssh_ "journalctl -u xochitl --since '-2min' --no-pager 2>/dev/null | grep -i qmldiff | grep -iE 'error|warning'" ; then
    echo
    echo "^ qmldiff reported a problem. A parse error drops EVERY rule in the"
    echo "  file, so the selection-menu button just will not appear."
else
    echo "No qmldiff errors."
fi
ssh_ "journalctl -u xochitl --since '-2min' --no-pager 2>/dev/null | grep -c 'Processing file' | sed 's/^/qmldiff files patched: /'" || true

echo
echo "Installed to ${HOST}:${REMOTE_DIR}"
echo "Open (or close and reopen) Saver from the AppLoad menu to pick up changes."
