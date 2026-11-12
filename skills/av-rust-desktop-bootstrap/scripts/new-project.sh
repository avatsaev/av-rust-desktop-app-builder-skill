#!/usr/bin/env bash
# Scaffold a new Rust desktop app from the template in ../assets/template.
#
# Reads only the template and writes only inside the output directory (plus `git init`,
# `cargo fmt`, `cargo generate-lockfile` and `npm ci` run there). Works with bash 3.2+ and POSIX
# sed (Linux, macOS, Git Bash and WSL on Windows).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../assets/template"
RESERVED="doc ops format engine shell testkit ui cli web xtask"

usage() {
  cat <<'EOF'
usage: new-project.sh <dir> --name <name> [options]

  <dir>               directory to create the project in (must not exist, or be empty)
  --name <name>       machine name: lowercase ASCII letters and digits, starting with a letter.
                      Becomes the crate prefix (<name>-engine), the binaries (<name>, <name>-cli),
                      the file extension and the format name. Required.
  --title <Title>     product name shown to users (default: the name with its first letter
                      capitalised). Letters, digits, spaces, dots, hyphens, underscores.
  --id <id>           reverse-DNS application id (default: com.example.<name>). Use a domain you
                      control: changing it after release orphans window state and file associations.
  --author <holder>   copyright holder for LICENSE-MIT and NOTICE (default: "The <Title> Authors")
  --no-git            do not run `git init`
  --no-install        do not run `cargo fmt --all`, `cargo generate-lockfile` and `npm ci`
  --verify            run the gate (`cargo xtask ci`) after scaffolding
  -h, --help          show this help
EOF
}

die() {
  echo "new-project.sh: $*" >&2
  exit 2
}

OUT="" NAME="" TITLE="" APP_ID="" AUTHOR=""
GIT=1 INSTALL=1 VERIFY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --name) [ $# -ge 2 ] || die "--name needs a value"; NAME="$2"; shift 2 ;;
    --title) [ $# -ge 2 ] || die "--title needs a value"; TITLE="$2"; shift 2 ;;
    --id) [ $# -ge 2 ] || die "--id needs a value"; APP_ID="$2"; shift 2 ;;
    --author) [ $# -ge 2 ] || die "--author needs a value"; AUTHOR="$2"; shift 2 ;;
    --no-git) GIT=0; shift ;;
    --no-install) INSTALL=0; shift ;;
    --verify) VERIFY=1; shift ;;
    -h | --help) usage; exit 0 ;;
    -*) die "unknown option \`$1\` (see --help)" ;;
    *) [ -z "$OUT" ] || die "more than one output directory given: \`$OUT\` and \`$1\`"; OUT="$1"; shift ;;
  esac
done

[ -n "$OUT" ] || { usage >&2; exit 2; }
[ -n "$NAME" ] || die "--name is required"
[ -d "$TEMPLATE" ] || die "template not found at $TEMPLATE"

if ! [[ "$NAME" =~ ^[a-z][a-z0-9]*$ ]]; then
  die "--name: lowercase ASCII letters and digits, starting with a letter (no hyphens: it becomes part of Rust identifiers)"
fi
for reserved in $RESERVED; do
  [ "$NAME" != "$reserved" ] || die "--name: \`$NAME\` is one of the template's own crate names ($RESERVED)"
done

if [ -z "$TITLE" ]; then
  TITLE="$(printf '%s' "$NAME" | cut -c1 | tr '[:lower:]' '[:upper:]')$(printf '%s' "$NAME" | cut -c2-)"
fi
[ -n "$APP_ID" ] || APP_ID="com.example.$NAME"
[ -n "$AUTHOR" ] || AUTHOR="The $TITLE Authors"

[[ "$TITLE" =~ ^[A-Za-z0-9][A-Za-z0-9\ ._-]*$ ]] || die "--title: letters, digits, spaces, dots, hyphens and underscores, starting with a letter or digit"
[[ "$APP_ID" =~ ^[A-Za-z0-9]+(\.[A-Za-z0-9_-]+)+$ ]] || die "--id: a reverse-DNS id such as org.example.notes"
case "$AUTHOR" in *$'\n'*) die "--author: one line" ;; esac

if [ -e "$OUT" ]; then
  [ -d "$OUT" ] || die "$OUT exists and is not a directory"
  [ -z "$(ls -A "$OUT")" ] || die "$OUT exists and is not empty"
fi

UPPER="$(printf '%s' "$NAME" | tr '[:lower:]' '[:upper:]')"
YEAR="$(date +%Y)"
# Only the author is free text: escape what is special on the right-hand side of `s|…|…|`.
AUTHOR_ESCAPED="$(printf '%s' "$AUTHOR" | sed -e 's/[\\&|]/\\&/g')"

# Renaming happens in two passes so that a replacement can never be renamed again (an id such as
# `org.myapp.tools` contains a placeholder). The longest placeholder is matched first.
render() {
  sed \
    -e 's|com\.example\.myapp|%%AVRD:ID%%|g' \
    -e 's|MyApp|%%AVRD:TITLE%%|g' \
    -e 's|MYAPP|%%AVRD:UPPER%%|g' \
    -e 's|myapp|%%AVRD:NAME%%|g' \
    -e 's|__YEAR__|%%AVRD:YEAR%%|g' \
    -e 's|__AUTHOR__|%%AVRD:AUTHOR%%|g' "$1" | sed \
    -e "s|%%AVRD:ID%%|$APP_ID|g" \
    -e "s|%%AVRD:TITLE%%|$TITLE|g" \
    -e "s|%%AVRD:UPPER%%|$UPPER|g" \
    -e "s|%%AVRD:NAME%%|$NAME|g" \
    -e "s|%%AVRD:YEAR%%|$YEAR|g" \
    -e "s|%%AVRD:AUTHOR%%|$AUTHOR_ESCAPED|g"
}

# Template path -> project path: `dot-x` components are dotfiles (installers and package managers
# tend to drop or reinterpret real ones), a `.tmpl` suffix is removed, placeholders are renamed.
target_path() {
  printf '%s\n' "$1" | sed -E -e 's#(^|/)dot-#\1.#g' -e 's#\.tmpl$##' -e "s#myapp#$NAME#g"
}

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
count=0
while IFS= read -r file; do
  rel="${file#"$TEMPLATE"/}"
  dest="$OUT/$(target_path "$rel")"
  mkdir -p "$(dirname "$dest")"
  case "$rel" in
    # Binary assets are copied as they are.
    *.png | *.ico | *.icns | *.jpg | *.gif | *.woff2 | *.ttf | *.otf) cp "$file" "$dest" ;;
    *) render "$file" > "$dest" ;;
  esac
  count=$((count + 1))
done < <(find "$TEMPLATE" -type f | LC_ALL=C sort)

[ "$count" -gt 0 ] || die "no files found in $TEMPLATE"
echo "wrote $count files to $OUT"
echo "  name: $NAME   title: $TITLE   id: $APP_ID"

cd "$OUT"

if [ "$GIT" -eq 1 ]; then
  if ! command -v git > /dev/null 2>&1; then
    echo "note: git is not installed; skipped \`git init\`"
  elif git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    echo "note: $OUT is inside an existing git work tree; skipped \`git init\`"
  else
    git init -q
    echo "initialised a git repository"
  fi
fi

if [ "$INSTALL" -eq 1 ] || [ "$VERIFY" -eq 1 ]; then
  for tool in cargo npm; do
    if ! command -v "$tool" > /dev/null 2>&1; then
      echo "new-project.sh: $tool is not on PATH; run scripts/setup.sh, then in $OUT:" >&2
      echo "  cargo fmt --all && cargo generate-lockfile && (cd apps/$NAME && npm ci) && cargo xtask ci" >&2
      exit 1
    fi
  done
  # A name of another length moves rustfmt's line breaks; without this the gate fails at `fmt`.
  cargo fmt --all
  # Applications pin their dependencies: commit Cargo.lock.
  cargo generate-lockfile
  echo "formatted the sources and generated Cargo.lock (commit it)"
  # The frontend's dependencies, exactly as package-lock.json pins them.
  (cd "apps/$NAME" && npm ci --no-audit --no-fund)
  echo "installed the frontend's dependencies (apps/$NAME/node_modules)"
fi

if [ "$VERIFY" -eq 1 ]; then
  cargo xtask ci
fi

cat <<EOF

next, in $OUT:
  cargo xtask ci                          the gate; all eight steps should pass before your first change
  cargo run -p $NAME                      the window (after the gate, or \`cargo xtask web\`, built the frontend)
  cargo run -q -p $NAME-cli -- commands   every command the app has
EOF
