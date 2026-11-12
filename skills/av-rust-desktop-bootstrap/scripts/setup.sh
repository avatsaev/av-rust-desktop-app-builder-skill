#!/usr/bin/env bash
# Check for, and install, everything needed to build, test and run a project made from this
# template: system packages (the platform webview's development files), the Rust toolchain with
# clippy, rustfmt and the wasm32 target, Node.js for the web frontend, and cargo-nextest.
#
# Works with bash 3.2+ on Linux (apt, dnf, pacman), macOS, and Git Bash or WSL on Windows.
# Nothing is installed without `--yes` or an interactive confirmation. `--check` installs nothing.
set -eo pipefail

MIN_RUST_MINOR=95 # Rust 1.95, the template's `rust-version`
NVM_VERSION="v0.41.0"

usage() {
  cat <<'EOF'
usage: setup.sh [options]

  --check         report what is present and what is missing; install nothing
  --yes           install without asking (needed when there is no terminal to ask on)
  --no-nextest    skip cargo-nextest: the gate then falls back to `cargo test`
  --no-system     skip system packages (they are already there, or you manage them yourself)
  --no-node       skip Node.js (you manage it yourself)
  --headless      also install Xvfb, a virtual display for running the window where there is
                  none (CI, containers, remote machines)
  -h, --help      show this help

exit status: 0 when everything required is present, 1 when something required is missing,
2 on a usage error.
EOF
}

CHECK=0 YES=0 NEXTEST=1 SYSTEM=1 NODE=1 HEADLESS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK=1 ;;
    --yes | -y) YES=1 ;;
    --no-nextest) NEXTEST=0 ;;
    --no-system) SYSTEM=0 ;;
    --no-node) NODE=0 ;;
    --headless) HEADLESS=1 ;;
    -h | --help) usage; exit 0 ;;
    *) echo "setup.sh: unknown option \`$1\` (see --help)" >&2; exit 2 ;;
  esac
  shift
done

# rustup installs here; a shell that has not re-read its profile does not have it on PATH yet.
if [ -d "${CARGO_HOME:-$HOME/.cargo}/bin" ]; then
  PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
fi

SUMMARY="" MISSING=0 TODO=""
row() { SUMMARY="$SUMMARY$(printf '  %-9s %s' "$1" "$2")"$'\n'; }
ok() { row "ok" "$1"; }
done_() { row "installed" "$1"; }
optional() { row "optional" "$1"; TODO="$TODO    $2"$'\n'; }
missing() { row "MISSING" "$1"; MISSING=$((MISSING + 1)); TODO="$TODO    $2"$'\n'; }
say() { printf '\n== %s\n' "$1"; }
have() { command -v "$1" > /dev/null 2>&1; }

# May we install `$1` now?
confirm() {
  [ "$CHECK" -eq 0 ] || return 1
  [ "$YES" -eq 0 ] || return 0
  [ -t 0 ] || return 1
  printf '%s [y/N] ' "$1"
  read -r answer
  case "$answer" in y | Y | yes | YES) return 0 ;; *) return 1 ;; esac
}

# Prefix for a command that needs root: empty, `sudo`, or `none` when there is no way to get it
# without a terminal to type a password on.
ROOT_PREFIX=""
if [ "$(id -u)" -ne 0 ]; then
  if have sudo && { sudo -n true 2> /dev/null || [ -t 0 ]; }; then
    ROOT_PREFIX="sudo"
  else
    ROOT_PREFIX="none"
  fi
fi

OS="$(uname -s)"

# Node.js 22.12 or newer on an even (LTS) line: what the frontend's tooling supports.
node_ok() {
  have node || return 1
  local version major minor
  version="$(node --version 2> /dev/null)"
  version="${version#v}"
  major="${version%%.*}"
  minor="${version#*.}"
  minor="${minor%%.*}"
  case "$major" in
    22) [ "${minor:-0}" -ge 12 ] 2> /dev/null ;;
    '' | *[!0-9]*) return 1 ;;
    *) [ "$major" -ge 24 ] && [ $((major % 2)) -eq 0 ] ;;
  esac
}

# nvm, when it is installed but this shell has not loaded it.
load_nvm() {
  local dir="${NVM_DIR:-$HOME/.nvm}"
  [ -s "$dir/nvm.sh" ] || return 1
  export NVM_DIR="$dir"
  # nvm is not written for `set -e`.
  set +e
  # shellcheck disable=SC1091
  . "$dir/nvm.sh" > /dev/null 2>&1
  set -e
  have nvm || declare -F nvm > /dev/null
}
have node || load_nvm || true

# ---------------------------------------------------------------------------------------------
# System packages
# ---------------------------------------------------------------------------------------------

linux_packages() {
  local manager="" build="" pkgconfig="" libs="" headless="" query="" install=""
  if have apt-get; then
    manager="apt"
    # WebKitGTK is the webview Tauri uses on Linux (it brings GTK); librsvg draws icons; libxdo is
    # for menu accelerators.
    libs="libwebkit2gtk-4.1-dev librsvg2-dev libxdo-dev"
    build="build-essential"
    pkgconfig="pkg-config"
    headless="xvfb"
    query="dpkg_installed"
    install="env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends"
  elif have dnf; then
    manager="dnf"
    libs="webkit2gtk4.1-devel librsvg2-devel libxdo-devel"
    build="gcc"
    pkgconfig="pkgconf-pkg-config"
    headless="xorg-x11-server-Xvfb"
    query="rpm -q"
    install="dnf install -y"
  elif have pacman; then
    manager="pacman"
    libs="webkit2gtk-4.1 librsvg xdotool"
    build="gcc"
    pkgconfig="pkgconf"
    headless="xorg-server-xvfb"
    query="pacman -Qi"
    install="pacman -S --needed --noconfirm"
  else
    missing "system packages: no apt, dnf or pacman found" \
      "install a C compiler, pkg-config and your distribution's equivalents of (Debian names): libwebkit2gtk-4.1-dev librsvg2-dev libxdo-dev"
    return 0
  fi

  # The linker. Any C compiler driver will do, so look for the command, not for a package.
  local wanted="$libs"
  if ! have cc && ! have gcc && ! have clang; then
    wanted="$build $wanted"
  fi
  # The build scripts of the webview crates find the system libraries with pkg-config.
  if ! have pkg-config; then
    wanted="$pkgconfig $wanted"
  fi
  [ "$HEADLESS" -eq 0 ] || wanted="$wanted $headless"
  # The installers of rustup and nvm are fetched with curl.
  if ! have curl && { ! have rustup || ! node_ok; }; then
    wanted="$wanted curl ca-certificates"
  fi

  local need="" pkg
  for pkg in $wanted; do
    if $query "$pkg" > /dev/null 2>&1; then :; else need="$need $pkg"; fi
  done
  need="${need# }"
  if [ -z "$need" ]; then
    ok "system packages ($manager)"
    return 0
  fi

  local prefix="$ROOT_PREFIX"
  [ "$prefix" != "none" ] || prefix="sudo"
  local command="${prefix:+$prefix }$install $need"
  [ "$manager" != "apt" ] || command="${prefix:+$prefix }apt-get update && $command"

  if [ "$CHECK" -eq 1 ]; then
    missing "system packages: $need" "$command"
  elif [ "$ROOT_PREFIX" = "none" ]; then
    echo "cannot install system packages from here: not root, and sudo needs a terminal for its password"
    missing "system packages: $need" "$command"
  elif confirm "Install system packages with $manager: $need?"; then
    case "$manager" in
      apt) $ROOT_PREFIX apt-get update || true ;;
      # A machine whose package database was never downloaded (a fresh container) knows no
      # package at all. A database that exists is left alone: refreshing it without upgrading
      # the system is what Arch warns against.
      pacman) pacman -Si gcc > /dev/null 2>&1 || $ROOT_PREFIX pacman -Sy || true ;;
    esac
    # shellcheck disable=SC2086
    if $ROOT_PREFIX $install $need; then
      done_ "system packages: $need"
    else
      echo "setup.sh: installing system packages failed (see above)" >&2
      missing "system packages: $need (the install failed)" "$command"
    fi
  else
    missing "system packages: $need" "$command"
  fi
}

dpkg_installed() {
  dpkg-query -W -f='${Status}' "$1" 2> /dev/null | grep -q "install ok installed"
}

if [ "$SYSTEM" -eq 1 ]; then
  say "System packages"
  case "$OS" in
    Linux) linux_packages ;;
    Darwin)
      if xcode-select -p > /dev/null 2>&1; then
        ok "Xcode command line tools"
      else
        missing "Xcode command line tools" "xcode-select --install    (finish the dialog it opens, then run this script again)"
      fi
      [ "$HEADLESS" -eq 0 ] || row "note" "--headless has nothing to install on macOS"
      ;;
    MINGW* | MSYS* | CYGWIN*)
      row "note" "Windows: the MSVC toolchain with the \"Desktop development with C++\" workload is required, and the WebView2 runtime (part of Windows 11 and of current Windows 10); this shell cannot check for them"
      [ "$HEADLESS" -eq 0 ] || row "note" "--headless has nothing to install on Windows"
      ;;
    *) row "note" "unknown system \`$OS\`: install a C toolchain and your platform webview's development packages yourself" ;;
  esac
fi

# ---------------------------------------------------------------------------------------------
# Rust
# ---------------------------------------------------------------------------------------------

say "Rust toolchain"

RUSTUP_INSTALL="curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --component clippy --component rustfmt --target wasm32-unknown-unknown"

if ! have rustup && ! have cargo; then
  case "$OS" in
    MINGW* | MSYS* | CYGWIN*)
      missing "Rust (rustup)" "install rustup from https://rustup.rs, open a new shell, then run this script again"
      ;;
    *)
      if ! have curl; then
        missing "Rust (rustup)" "install curl, then: $RUSTUP_INSTALL"
      elif confirm "Install Rust with rustup (into ${CARGO_HOME:-$HOME/.cargo} and ${RUSTUP_HOME:-$HOME/.rustup})?"; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --component clippy --component rustfmt --target wasm32-unknown-unknown
        PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
        done_ "Rust $(rustc --version | cut -d' ' -f2) with rustup (new shells: source \"\$HOME/.cargo/env\")"
      else
        missing "Rust (rustup)" "$RUSTUP_INSTALL"
      fi
      ;;
  esac
fi

if have cargo && ! have rustup; then
  missing "rustup (Rust was installed another way; rustup adds clippy, rustfmt and the wasm32 target)" \
    "replace the system Rust with rustup: $RUSTUP_INSTALL"
fi

if have rustup && have rustc; then
  version="$(rustc --version | cut -d' ' -f2)"
  minor="$(printf '%s' "$version" | cut -d. -f2)"
  if [ "${minor:-0}" -ge "$MIN_RUST_MINOR" ] 2> /dev/null; then
    ok "Rust $version (1.$MIN_RUST_MINOR or newer)"
  elif confirm "Rust $version is older than 1.$MIN_RUST_MINOR. Run \`rustup update stable\`?"; then
    rustup update stable
    done_ "Rust $(rustc --version | cut -d' ' -f2)"
  else
    missing "Rust 1.$MIN_RUST_MINOR or newer (found $version)" "rustup update stable"
  fi

  components="$(rustup component list --installed 2> /dev/null || true)"
  need=""
  for component in clippy rustfmt; do
    case "$components" in *"$component"*) ;; *) need="$need $component" ;; esac
  done
  need="${need# }"
  if [ -z "$need" ]; then
    ok "clippy and rustfmt"
  elif [ "$CHECK" -eq 0 ]; then
    # shellcheck disable=SC2086
    rustup component add $need
    done_ "components: $need"
  else
    missing "components: $need" "rustup component add $need"
  fi

  if rustup target list --installed 2> /dev/null | grep -qx "wasm32-unknown-unknown"; then
    ok "target wasm32-unknown-unknown"
  elif [ "$CHECK" -eq 0 ]; then
    rustup target add wasm32-unknown-unknown
    done_ "target wasm32-unknown-unknown"
  else
    missing "target wasm32-unknown-unknown (the gate's wasm step needs it)" "rustup target add wasm32-unknown-unknown"
  fi
fi

# ---------------------------------------------------------------------------------------------
# Node.js, for the web frontend (React, Vite, the Tauri CLI). npm comes with it.
# ---------------------------------------------------------------------------------------------

NVM_INSTALL="curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh | bash"

install_node() {
  if ! load_nvm; then
    have curl || return 1
    curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh" | bash || return 1
    load_nvm || return 1
  fi
  set +e
  nvm install --lts
  local status=$?
  set -e
  return "$status"
}

if [ "$NODE" -eq 1 ]; then
  say "Node.js"
  if node_ok; then
    ok "Node.js $(node --version) with npm $(npm --version 2> /dev/null || echo '?')"
  else
    found="$(have node && node --version || echo none)"
    case "$OS" in
      MINGW* | MSYS* | CYGWIN*)
        missing "Node.js 22.12+, 24 or 26+ (found $found)" "install the current LTS from https://nodejs.org, open a new shell, then run this script again"
        ;;
      *)
        if confirm "Install the current Node.js LTS with nvm (into ${NVM_DIR:-$HOME/.nvm}; found $found)?"; then
          if install_node && node_ok; then
            done_ "Node.js $(node --version) with nvm (new shells load it from your profile; in this one: . \"\$HOME/.nvm/nvm.sh\")"
          else
            missing "Node.js 22.12+, 24 or 26+ (the nvm install failed, see above)" "$NVM_INSTALL && . \"\$HOME/.nvm/nvm.sh\" && nvm install --lts"
          fi
        else
          missing "Node.js 22.12+, 24 or 26+ (found $found)" "$NVM_INSTALL && . \"\$HOME/.nvm/nvm.sh\" && nvm install --lts"
        fi
        ;;
    esac
  fi
fi

# ---------------------------------------------------------------------------------------------
# Cargo tools. Compiled from source: a few minutes. The Tauri CLI is not here: it is an npm
# dependency of the project (`npm run tauri`).
# ---------------------------------------------------------------------------------------------

cargo_tool() { # name, probe command, what it is for
  local name="$1" probe="$2" purpose="$3"
  if eval "$probe" > /dev/null 2>&1; then
    ok "$name ($purpose)"
  elif ! have cargo; then
    optional "$name ($purpose)" "cargo install $name --locked"
  elif confirm "Install $name with \`cargo install\` ($purpose; compiles for a few minutes)?"; then
    if cargo install "$name" --locked; then
      done_ "$name ($purpose)"
    else
      echo "setup.sh: \`cargo install $name\` failed (see above)" >&2
      optional "$name ($purpose): cargo install failed" "cargo install $name --locked"
    fi
  else
    optional "$name ($purpose)" "cargo install $name --locked"
  fi
}

say "Cargo tools"
if [ "$NEXTEST" -eq 1 ]; then
  cargo_tool cargo-nextest "cargo nextest --version" "the parallel test runner; without it the gate uses cargo test"
else
  row "skipped" "cargo-nextest (--no-nextest)"
fi

# ---------------------------------------------------------------------------------------------

printf '\nSummary\n%s' "$SUMMARY"
if [ -n "$TODO" ]; then
  printf '\nTo finish, run:\n%s' "$TODO"
fi
if [ "$HEADLESS" -eq 1 ] && [ "$OS" = "Linux" ]; then
  printf '\nNo display? Start a virtual one before running the window:\n    Xvfb :99 -screen 0 1280x800x24 &\n    export DISPLAY=:99\n'
fi
if [ "$MISSING" -gt 0 ]; then
  printf '\n%s required item(s) missing.\n' "$MISSING"
  exit 1
fi
printf '\nEverything required is present.\n'
