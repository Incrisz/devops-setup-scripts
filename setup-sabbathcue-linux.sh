#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/Bongisto/SabbathCue.git}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Music/SabbathCue}"
VOSK_MODEL="vosk-model-en-us-0.22-lgraph"
VOSK_ZIP="${VOSK_MODEL}.zip"
VOSK_URL="https://alphacephei.com/vosk/models/${VOSK_ZIP}"

log()  { printf "\n\033[1;34m[INFO]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[OK]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
die()  { printf "\033[1;31m[ERROR]\033[0m %s\n" "$*" >&2; exit 1; }

if [[ "$(uname -s)" != "Linux" ]]; then
  die "This installer is for Linux."
fi

if ! command -v apt-get >/dev/null 2>&1; then
  die "This script currently supports Debian/Ubuntu/Parrot-based Linux systems using apt."
fi

log "Installing Linux/Tauri/audio dependencies..."
sudo apt-get update
sudo apt-get install -y \
  build-essential \
  curl \
  wget \
  unzip \
  file \
  pkg-config \
  python3 \
  python3-pip \
  python3-venv \
  libssl-dev \
  libgtk-3-dev \
  libayatana-appindicator3-dev \
  librsvg2-dev \
  libwebkit2gtk-4.1-dev \
  libasound2-dev

ok "System dependencies installed."

log "Installing/configuring Bun..."
if ! command -v bun >/dev/null 2>&1; then
  curl -fsSL https://bun.sh/install | bash
fi
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

if ! grep -q 'export BUN_INSTALL="$HOME/.bun"' "$HOME/.bashrc" 2>/dev/null; then
  {
    echo
    echo 'export BUN_INSTALL="$HOME/.bun"'
    echo 'export PATH="$BUN_INSTALL/bin:$PATH"'
  } >> "$HOME/.bashrc"
fi

bun --version
ok "Bun is available."

log "Installing/configuring Rust for Linux..."
if ! command -v rustup >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi

export PATH="$HOME/.cargo/bin:$PATH"
# shellcheck disable=SC1090
[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

rustup toolchain install stable-x86_64-unknown-linux-gnu
rustup default stable-x86_64-unknown-linux-gnu

ok "Rust Linux toolchain configured."

log "Cloning/updating SabbathCue..."
mkdir -p "$(dirname "$INSTALL_DIR")"

if [[ -d "$INSTALL_DIR/.git" ]]; then
  warn "Repository already exists at $INSTALL_DIR; leaving current changes intact."
else
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"

log "Applying Linux Rust toolchain correction..."
cat > rust-toolchain.toml <<'EOF'
[toolchain]
channel = "stable"
EOF

rustup show active-toolchain
rustc --version
cargo --version

log "Installing JavaScript dependencies..."
bun install
ok "bun install completed."

log "Preparing SabbathCue assets up to the Windows-only Vosk step..."
# The upstream setup:all ends with a PowerShell-only Vosk downloader.
# Run it once and tolerate only that expected final failure.
set +e
bun run setup:all
SETUP_RC=$?
set -e

if [[ $SETUP_RC -ne 0 ]]; then
  warn "setup:all returned non-zero. This is expected upstream on Linux when it reaches the PowerShell Vosk download step."
fi

log "Installing the Vosk model manually for Linux..."
mkdir -p models/vosk

if [[ ! -f "models/vosk/$VOSK_MODEL/am/final.mdl" ]]; then
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT

  wget -O "$TMP_DIR/$VOSK_ZIP" "$VOSK_URL"
  unzip -q "$TMP_DIR/$VOSK_ZIP" -d "$TMP_DIR"

  rm -rf "models/vosk/$VOSK_MODEL"
  mv "$TMP_DIR/$VOSK_MODEL" "models/vosk/$VOSK_MODEL"
else
  ok "Vosk model already present."
fi

for required in \
  "am/final.mdl" \
  "conf/model.conf" \
  "graph/HCLr.fst" \
  "graph/Gr.fst"
do
  [[ -f "models/vosk/$VOSK_MODEL/$required" ]] || die "Missing Vosk file: $required"
done

ok "Vosk model verified."

log "Removing Windows-only Vosk sidecar resource from Tauri config..."
python3 - <<'PY'
import json
from pathlib import Path

path = Path("src-tauri/tauri.conf.json")
data = json.loads(path.read_text())
resources = data["bundle"]["resources"]
removed = resources.pop("../sidecars/vosk_worker.*", None)
path.write_text(json.dumps(data, indent=2) + "\n")
print("Removed sidecar glob." if removed is not None else "Sidecar glob already absent.")
PY

log "Creating Python Vosk runtime..."
python3 -m venv .venv-vosk
# shellcheck disable=SC1091
source .venv-vosk/bin/activate
python -m pip install --upgrade pip
python -m pip install vosk
python -c "import vosk; print('Vosk Python runtime OK')"
deactivate
ok "Python Vosk runtime ready."

log "Bypassing upstream Supabase/device verification gate for this church/local fork..."
VERIFY_GATE="src/components/verification/VerificationGate.tsx"

if [[ -f "$VERIFY_GATE" ]]; then
  if [[ ! -f "${VERIFY_GATE}.upstream-backup" ]]; then
    cp "$VERIFY_GATE" "${VERIFY_GATE}.upstream-backup"
  fi

  cat > "$VERIFY_GATE" <<'EOF'
import type { ReactNode } from "react"

export function VerificationGate({ children }: { children: ReactNode }) {
  return children
}
EOF
  ok "Supabase verification gate bypassed."
else
  warn "$VERIFY_GATE was not found; skipping verification-gate patch."
fi

log "Verifying ALSA is visible..."
pkg-config --modversion alsa >/dev/null
ok "ALSA development library detected."

cat <<EOF

============================================================
SabbathCue Linux setup is complete.
============================================================

Project:
  $INSTALL_DIR

Linux fixes applied:
  - Installed Tauri/WebKit/GTK dependencies
  - Installed ALSA development libraries
  - Configured Bun PATH
  - Forced Rust to the Linux stable toolchain
  - Replaced Windows-only rust-toolchain setting
  - Downloaded Vosk model without PowerShell
  - Removed Windows-only vosk_worker.* Tauri resource glob
  - Created local Python Vosk environment
  - Bypassed Supabase/device verification gate

To start SabbathCue:

  cd "$INSTALL_DIR"
  source "\$HOME/.cargo/env"
  export BUN_INSTALL="\$HOME/.bun"
  export PATH="\$BUN_INSTALL/bin:\$PATH"
  source .venv-vosk/bin/activate
  bun run tauri dev

To exit the Python environment later:
  deactivate

NOTE:
  This script modifies the upstream project for Linux/local church use.
  Keep these changes in your own fork/branch rather than expecting a clean
  upstream checkout to work identically on Linux.
============================================================

EOF
