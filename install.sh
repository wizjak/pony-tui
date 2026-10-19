#!/usr/bin/env bash
# pony-tui installer
# Usage: ./install.sh [-y|--yes] [--uninstall] [-h|--help]
#   -y, --yes      don't ask questions (assume "yes")
#   --uninstall    remove pony-tui from this machine
# Re-running the installer updates an existing install.

REPO_URL="https://github.com/wizjak/pony-tui"
CONFIG_DIR="${HOME:?HOME is not set}/.config"
INSTALL_DIR="$CONFIG_DIR/pony-tui"
BIN_DIR="/usr/local/bin"
BIN_PATH="$BIN_DIR/pony-tui"

ASSUME_YES=0
UNINSTALL=0
UPDATING=0
WORK=""
LOG=""
export GIT_TERMINAL_PROMPT=0

# --- terminal / colors (pastel palette, honors NO_COLOR) --------------------
TTY=0; [[ -t 1 ]] && TTY=1
if (( TTY )) && [[ -z ${NO_COLOR:-} && ${TERM:-dumb} != dumb ]]; then
  RST=$'\e[0m'; BOLD=$'\e[1m'
  PINK=$'\e[38;5;211m'; LAV=$'\e[38;5;183m'; MINT=$'\e[38;5;121m'
  SKY=$'\e[38;5;117m';  SUN=$'\e[38;5;222m'; RED=$'\e[38;5;203m'
  GRAY=$'\e[38;5;245m'
else
  RST=""; BOLD=""; PINK=""; LAV=""; MINT=""; SKY=""; SUN=""; RED=""; GRAY=""
fi

fg() { [[ -n $RST ]] && printf '\e[38;5;%sm' "$1"; }
RB=(204 215 228 120 117 141)
RB_ESC=(); for c in "${RB[@]}"; do RB_ESC+=("$(fg "$c")"); done
LOGO_COL=(); for c in 211 216 228 157 117; do LOGO_COL+=("$(fg "$c")"); done
FRAMES=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)

LOGO=(
' ____    ___   _   _ __   __   _____   _   _   ___ '
'|  _ \  / _ \ | \ | |\ \ / /  |_   _| | | | | |_ _|'
'| |_) || | | ||  \| | \ V /     | |   | | | |  | | '
'|  __/ | |_| || |\  |  | |     | |   | |_| |  | | '
'|_|     \___/ |_| \_|  |_|     |_|    \___/  |___|'
)

cleanup() {
  (( TTY )) && printf '\e[?25h'
  [[ -n $WORK ]] && rm -rf "$WORK"
  [[ -n $LOG ]] && rm -f "$LOG"
}
trap cleanup EXIT
trap 'printf "\n"; exit 130' INT TERM

# --- output helpers ---------------------------------------------------------
ok()      { printf '  %s✔%s %s\n' "$MINT" "$RST" "$1"; }
warn()    { printf '  %s!%s %s\n' "$SUN" "$RST" "$1"; }
bad()     { printf '  %s✖%s %s\n' "$RED" "$RST" "$1"; }
info()    { printf '  %s▸%s %s\n' "$SKY" "$RST" "$1"; }
section() { printf '\n  %s%s▍ %s%s\n\n' "$BOLD" "$PINK" "$1" "$RST"; }
die() {
  bad "$1"
  [[ -n ${2:-} ]] && printf '    %s%s%s\n' "$GRAY" "$2" "$RST"
  exit 1
}

tilde() { local t='~'; printf '%s' "${1/#"$HOME"/$t}"; }

rainbow() {
  local w=$1 j s=""
  for (( j = 0; j < w; j++ )); do s+="${RB_ESC[j % 6]}━"; done
  printf '  %s%s\n' "$s" "$RST"
}

banner() {
  local cols=80 i
  (( TTY )) && cols=$(tput cols 2>/dev/null || echo 80)
  printf '\n'
  if (( cols >= 56 )); then
    for i in "${!LOGO[@]}"; do
      printf '  %s%s%s%s\n' "${LOGO_COL[i]}" "$BOLD" "${LOGO[i]}" "$RST"
    done
    printf '  %s♥  installer  ·  My Little Pony: Friendship is Magic  ♥%s\n' "$LAV" "$RST"
    rainbow 51
  else
    printf '  %s%s♥ PONY%s·%sTUI%s %sinstaller%s\n' "$BOLD" "$PINK" "$LAV" "$SKY" "$RST" "$GRAY" "$RST"
    rainbow 30
  fi
}

usage() {
  cat <<'EOF'
pony-tui installer

Usage: ./install.sh [options]

Options:
  -y, --yes      don't ask questions (assume "yes")
  --uninstall    remove pony-tui from this machine
  -h, --help     show this help

Re-running the installer updates an existing install.
EOF
}

ask() {  # ask "question" -> 0 = yes (default)
  (( ASSUME_YES )) && return 0
  [[ -r /dev/tty ]] || return 1
  local ans
  printf '  %s?%s %s %s[Y/n]%s ' "$SKY" "$RST" "$1" "$GRAY" "$RST" >/dev/tty
  IFS= read -r ans </dev/tty || return 1
  [[ -z $ans || ${ans,,} == y* ]]
}

# run_step "message" command args...   (spinner + ✔/✖, output goes to $LOG)
run_step() {
  local msg=$1 pid rc i=0 l; shift
  if (( TTY )); then
    printf '\e[?25l'
    "$@" >>"$LOG" 2>&1 </dev/null &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
      printf '\r  %s%s%s %s\e[K' "${RB_ESC[i % 6]}" "${FRAMES[i % ${#FRAMES[@]}]}" "$RST" "$msg"
      i=$(( i + 1 )); sleep 0.08
    done
    wait "$pid"; rc=$?
    printf '\e[?25h\r\e[K'
  else
    "$@" >>"$LOG" 2>&1 </dev/null; rc=$?
  fi
  if (( rc == 0 )); then
    ok "$msg"
  else
    bad "$msg"
    printf '\n'
    while IFS= read -r l; do
      printf '    %s│ %s%s\n' "$GRAY" "$l" "$RST"
    done < <(tail -n 12 "$LOG")
    printf '\n'
    exit 1
  fi
}

# --- requirements -----------------------------------------------------------
MISSING_REQ=(); MISSING_OPT=()
PM_NAME=""; PM_CMD=()
if (( EUID == 0 )); then SUDO=(); else SUDO=(sudo); fi

detect_pm() {
  if   command -v pacman  >/dev/null 2>&1; then PM_NAME=pacman; PM_CMD=(pacman -S --needed --noconfirm)
  elif command -v apt-get >/dev/null 2>&1; then PM_NAME=apt;    PM_CMD=(apt-get install -y)
  elif command -v dnf     >/dev/null 2>&1; then PM_NAME=dnf;    PM_CMD=(dnf install -y)
  elif command -v zypper  >/dev/null 2>&1; then PM_NAME=zypper; PM_CMD=(zypper --non-interactive install)
  fi
}

check_requirements() {
  section "Checking requirements"
  if (( BASH_VERSINFO[0] < 4 )); then
    die "bash 4 or newer is required (you have ${BASH_VERSION%%(*})."
  fi
  ok "bash ${BASH_VERSION%%(*}"

  if command -v git >/dev/null 2>&1; then ok "git"; else bad "git ${GRAY}— required${RST}"; MISSING_REQ+=(git); fi
  if command -v mpv >/dev/null 2>&1; then ok "mpv"; else bad "mpv ${GRAY}— required (plays the episodes)${RST}"; MISSING_REQ+=(mpv); fi
  if command -v curl >/dev/null 2>&1; then ok "curl"; else warn "curl ${GRAY}— optional (lets pony-tui pick the best video quality)${RST}"; MISSING_OPT+=(curl); fi
}

prime_sudo() {
  (( EUID == 0 )) && return 0
  command -v sudo >/dev/null 2>&1 || die "sudo is required to install the command into ${BIN_DIR}."
  if ! sudo -n true 2>/dev/null; then
    printf '\n'
    info "Admin rights are needed once, to put ${BOLD}pony-tui${RST} in ${BIN_DIR}."
    sudo -v || die "Couldn't get admin rights."
  fi
}

install_missing() {
  local -a pkgs=("${MISSING_REQ[@]}" "${MISSING_OPT[@]}")
  (( ${#pkgs[@]} == 0 )) && return 0
  detect_pm
  if [[ -z $PM_NAME ]]; then
    (( ${#MISSING_REQ[@]} )) && die "Missing required packages: ${MISSING_REQ[*]}" "Install them with your package manager, then run this again."
    return 0
  fi
  printf '\n'
  if ask "Install ${pkgs[*]} with ${PM_NAME}?"; then
    run_step "Installing ${pkgs[*]}" "${SUDO[@]}" "${PM_CMD[@]}" "${pkgs[@]}"
    local c
    for c in "${MISSING_REQ[@]}"; do
      command -v "$c" >/dev/null 2>&1 || die "$c is still missing after the install."
    done
  else
    (( ${#MISSING_REQ[@]} )) && die "Can't continue without: ${MISSING_REQ[*]}" "Try: ${SUDO[*]} ${PM_CMD[*]} ${MISSING_REQ[*]}"
    warn "Skipping optional packages."
  fi
}

# --- install steps (run inside run_step) ------------------------------------
step_clone() { git clone --depth 1 "$REPO_URL" "$WORK/pony-tui"; }

step_place() {
  mkdir -p "$CONFIG_DIR" && rm -rf "$INSTALL_DIR" && mv "$WORK/pony-tui" "$INSTALL_DIR"
}

step_perms() {
  cd "$INSTALL_DIR" || return 1
  if [[ ! -f listeps.sh || ! -f pony-tui.sh ]]; then
    echo "The repository is missing listeps.sh or pony-tui.sh."
    return 1
  fi
  chmod +x listeps.sh pony-tui.sh pony-rpc
  [[ -f pony-tui ]] && chmod +x pony-tui
  return 0
}

step_link() {
  local src="$INSTALL_DIR/pony-tui"
  if [[ ! -f $src ]]; then   # repo has no launcher: generate a tiny one
    src="$WORK/launcher"
    printf '#!/usr/bin/env bash\nexec bash "%s/pony-tui.sh" "$@"\n' "$INSTALL_DIR" > "$src"
  fi
  "${SUDO[@]}" mkdir -p "$BIN_DIR" && "${SUDO[@]}" install -m 755 "$src" "$BIN_PATH"
}

# --- summary box ------------------------------------------------------------
P=(); C=()
badd() { P+=("$1"); C+=("$2"); }

summary() {
  local ver verb="installed" w=0 p line i pad
  ver=$(git -C "$INSTALL_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
  (( UPDATING )) && verb="updated"

  P=(); C=()
  badd "✔ pony-tui ${verb}!"                 "${BOLD}${MINT}✔ pony-tui ${verb}!${RST}"
  badd "" ""
  badd "Run it with   pony-tui"              "${GRAY}Run it with${RST}   ${BOLD}${PINK}pony-tui${RST}"
  badd "Files         $(tilde "$INSTALL_DIR")" "${GRAY}Files${RST}         $(tilde "$INSTALL_DIR")"
  badd "Command       ${BIN_PATH}"           "${GRAY}Command${RST}       ${BIN_PATH}"
  badd "Version       ${ver}"                "${GRAY}Version${RST}       ${ver}"

  for p in "${P[@]}"; do (( ${#p} > w )) && w=${#p}; done
  printf -v line '%*s' $(( w + 2 )) ''; line=${line// /─}

  printf '\n  %s╭%s╮%s\n' "$LAV" "$line" "$RST"
  for i in "${!P[@]}"; do
    printf -v pad '%*s' $(( w - ${#P[i]} )) ''
    printf '  %s│%s %s%s %s│%s\n' "$LAV" "$RST" "${C[i]}" "$pad" "$LAV" "$RST"
  done
  printf '  %s╰%s╯%s\n\n' "$LAV" "$line" "$RST"
  printf '  %sRe-run this installer anytime to update. Enjoy the ponies ♥%s\n\n' "$GRAY" "$RST"
}

# --- uninstall --------------------------------------------------------------
do_uninstall() {
  section "Uninstalling"
  if [[ ! -e $INSTALL_DIR && ! -e $BIN_PATH ]]; then
    warn "pony-tui doesn't seem to be installed."
    return 0
  fi
  ask "Remove $(tilde "$INSTALL_DIR") and ${BIN_PATH}?" || { warn "Cancelled."; return 0; }
  prime_sudo
  run_step "Removing the pony-tui command" "${SUDO[@]}" rm -f "$BIN_PATH"
  run_step "Removing $(tilde "$INSTALL_DIR")" rm -rf "$INSTALL_DIR"
  printf '\n  %sAll gone. Bye bye ♥%s\n\n' "$GRAY" "$RST"
}

# --- main -------------------------------------------------------------------
main() {
  local a
  for a in "$@"; do
    case $a in
      -y|--yes)    ASSUME_YES=1 ;;
      --uninstall) UNINSTALL=1 ;;
      -h|--help)   usage; exit 0 ;;
      *)           die "Unknown option: $a" "Try --help" ;;
    esac
  done

  cd "$HOME" || exit 1
  WORK=$(mktemp -d) || exit 1
  LOG=$(mktemp)     || exit 1

  banner
  (( EUID == 0 )) && warn "Running as root: files will go to $(tilde "$INSTALL_DIR")."

  if (( UNINSTALL )); then
    do_uninstall
    return 0
  fi

  check_requirements
  prime_sudo
  install_missing

  [[ -d $INSTALL_DIR ]] && UPDATING=1
  if (( UPDATING )); then section "Updating"; else section "Installing"; fi

  run_step "Downloading from GitHub"                   step_clone
  run_step "Setting up $(tilde "$INSTALL_DIR")"        step_place
  run_step "Making the scripts executable"             step_perms
  run_step "Installing the pony-tui command"           step_link

  [[ -x $BIN_PATH ]] || die "The command wasn't installed at ${BIN_PATH}."
  if ! command -v pony-tui >/dev/null 2>&1; then
    warn "${BIN_DIR} isn't in your PATH — add it to run pony-tui from anywhere."
  fi
  ok "Everything checks out"

  summary
}

main "$@"
exit $?
