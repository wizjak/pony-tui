#!/usr/bin/env bash
# pony-tui — MLP:FiM episode browser
# Usage: ./pony-tui.sh   (needs mpv, plus listeps.sh next to this script or in PATH)
#
# Keys (menus):  ↑/↓ or j/k move · Enter select · / search · 0-9 jump to number
#                PgUp/PgDn · g/G top/bottom · b/←/Esc back · q quit
# Keys (player): a/← previous · s/→ next · p toggle autoplay · b/q/Esc back

BASE_URL="https://static.heartshine.gay/g4-fim"
QUALITY="${PONY_QUALITY:-1080p}"
QUALITIES=("$QUALITY" 1080p 720p 480p 360p)   # tried in order; first one that exists wins
CUR_Q="$QUALITY"
RES_URL=""
declare -A URL_CACHE
HAVE_CURL=0; command -v curl >/dev/null 2>&1 && HAVE_CURL=1
AUTOPLAY=0

CATEGORIES=(
  "Season 1" "Season 2" "Season 3" "Season 4" "Season 5"
  "Season 6" "Season 7" "Season 8" "Season 9"
  "Movies" "Specials" "Shorts" "Clip shows" "Claymatic Shorts"
)
SEASON_COUNT=9   # the first 9 entries are seasons; the rest (Movies, Specials…) use the same s{CAT}e{NUM} URL scheme

# --- sanity checks ----------------------------------------------------------
if [[ ! -t 0 || ! -t 1 ]]; then
  echo "pony-tui needs an interactive terminal." >&2
  exit 1
fi
if ! command -v mpv >/dev/null 2>&1; then
  echo "mpv is not installed (it is required to play episodes)." >&2
  exit 1
fi

# --- locate listeps.sh ------------------------------------------------------
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$DIR/listeps.sh" ]]; then
  LISTEPS=(bash "$DIR/listeps.sh")
elif command -v listeps.sh >/dev/null 2>&1; then
  LISTEPS=(listeps.sh)
else
  echo "Can't find listeps.sh (neither next to this script nor in your PATH)." >&2
  exit 1
fi

# --- colors (256-color pastel palette; honors NO_COLOR) ---------------------
if [[ -z ${NO_COLOR:-} && ${TERM:-dumb} != dumb ]]; then
  RST=$'\e[0m'; BOLD=$'\e[1m'
  PINK=$'\e[38;5;211m'; LAV=$'\e[38;5;183m'; MINT=$'\e[38;5;121m'
  SKY=$'\e[38;5;117m';  SUN=$'\e[38;5;222m'; RED=$'\e[38;5;203m'
  GRAY=$'\e[38;5;245m'; WHITE=$'\e[38;5;255m'
  SELBG=$'\e[48;5;97m\e[38;5;231m\e[1m'
else
  RST=""; BOLD=""; PINK=""; LAV=""; MINT=""; SKY=""; SUN=""; RED=""; GRAY=""; WHITE=""
  SELBG=$'\e[7m'
fi
EOL=$'\e[K\n'

fg() { [[ -n $RST ]] && printf '\e[38;5;%sm' "$1"; }

RB=(204 215 228 120 117 141)           # rainbow
RB_ESC=(); for c in "${RB[@]}"; do RB_ESC+=("$(fg "$c")"); done
LOGO_COL=(); for c in 211 216 228 157 117; do LOGO_COL+=("$(fg "$c")"); done
EQ=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)

LOGO=(
' ____    ___   _   _ __   __   _____   _   _   ___ '
'|  _ \  / _ \ | \ | |\ \ / /  |_   _| | | | | |_ _|'
'| |_) || | | ||  \| | \ V /     | |   | | | |  | | '
'|  __/ | |_| || |\  |  | |     | |   | |_| |  | | '
'|_|     \___/ |_| \_|  |_|     |_|    \___/  |___|'
)

# --- terminal setup / cleanup ----------------------------------------------
MPV_PID=""
cleanup() {
  [[ -n $MPV_PID ]] && kill "$MPV_PID" 2>/dev/null
  printf '\e[?25h'
  tput rmcup 2>/dev/null
}
trap cleanup EXIT
trap 'exit 130' INT TERM
trap ':' WINCH
tput smcup 2>/dev/null
printf '\e[?25l'

# --- helpers ----------------------------------------------------------------
ROWS=24; COLS=80
term_size() {
  local r c
  read -r r c < <(stty size 2>/dev/null)
  ROWS=${r:-24}; COLS=${c:-80}
}

spaces() {  # spaces N -> $SP
  local n=$1; (( n < 0 )) && n=0
  printf -v SP '%*s' "$n" ''
}

BAR_W=0; BAR=""
make_bar() {
  local w=$1 j
  (( w == BAR_W )) && return
  BAR_W=$w; BAR=""
  for (( j = 0; j < w; j++ )); do
    BAR+="${RB_ESC[j % ${#RB[@]}]}━"
  done
  BAR+=$RST
}

HDR=""; HDR_LINES=0
build_header() {
  term_size
  local w=$(( COLS - 4 )); (( w > 76 )) && w=76; (( w < 10 )) && w=10
  make_bar "$w"
  HDR=""
  if (( COLS >= 56 && ROWS >= 28 )); then
    local i tag="♥  My Little Pony: Friendship is Magic  ♥"
    HDR+=$EOL
    spaces $(( (COLS - ${#LOGO[0]}) / 2 ))
    for i in "${!LOGO[@]}"; do
      HDR+="${SP}${LOGO_COL[i]}${BOLD}${LOGO[i]}${RST}${EOL}"
    done
    spaces $(( (COLS - ${#tag}) / 2 ))
    HDR+="${SP}${LAV}${tag}${RST}${EOL}"
    spaces $(( (COLS - w) / 2 ))
    HDR+="${SP}${BAR}${EOL}${EOL}"
    HDR_LINES=9
  else
    HDR+=" ${BOLD}${PINK}♥ PONY${LAV}·${SKY}TUI${RST} ${GRAY}— MLP:FiM episode browser${RST}${EOL}"
    HDR+="  ${BAR}${EOL}${EOL}"
    HDR_LINES=3
  fi
}

KEY=""
read_key() {  # read_key [timeout]  -> $KEY ; returns 1 on timeout
  local t=${1:-} k rest rest2 rc
  KEY=""
  if [[ -n $t ]]; then IFS= read -rsn1 -t "$t" k; else IFS= read -rsn1 k; fi
  rc=$?
  if (( rc > 128 )); then
    [[ -n $t ]] && return 1
    KEY=$'\x01'; return 0          # interrupted (e.g. terminal resize) -> redraw
  elif (( rc != 0 )); then
    exit 0                         # EOF
  fi
  if [[ $k == $'\e' ]]; then
    IFS= read -rsn2 -t 0.02 rest
    k+=$rest
    if [[ $rest == '['[0-9] ]]; then
      IFS= read -rsn1 -t 0.02 rest2
      k+=$rest2
    fi
  fi
  KEY=$k
  return 0
}

show_message() {
  build_header
  printf '\e[H%s\n  %s\e[J' "$HDR" "$1"
}

wait_key() {
  printf '\n\n  %sPress any key to continue…%s' "$GRAY" "$RST"
  read_key
}

# --- generic list menu ------------------------------------------------------
# items in MENU_ITEMS[]; result index in MENU_SEL
# select_menu TITLE START_INDEX [NOTE] [ROOT]   -> 0 = chosen, 1 = back
VIS=()
menu_filter() {
  local f=${1,,} i
  VIS=()
  for i in "${!MENU_ITEMS[@]}"; do
    if [[ -z $f || ${MENU_ITEMS[i],,} == *"$f"* ]]; then VIS+=("$i"); fi
  done
}

select_menu() {
  local title=$1 start=${2:-0} note=${3:-} root=${4:-0}
  local n=${#MENU_ITEMS[@]} filter="" numbuf="" mode=nav pos=0 top=0 i
  menu_filter ""
  for i in "${!VIS[@]}"; do (( VIS[i] == start )) && pos=$i; done

  while true; do
    build_header
    local cnt=${#VIS[@]}
    local vh=$(( ROWS - HDR_LINES - 6 )); (( vh < 3 )) && vh=3
    local W=$(( COLS - 5 )); (( W < 20 )) && W=20
    local sbcol=$(( COLS - 1 ))

    (( pos >= cnt )) && pos=$(( cnt - 1 ))
    (( pos < 0 )) && pos=0
    (( pos < top )) && top=$pos
    (( pos >= top + vh )) && top=$(( pos - vh + 1 ))
    (( top > cnt - vh )) && top=$(( cnt - vh ))
    (( top < 0 )) && top=0

    local out=$'\e[H'"$HDR"
    out+="  ${BOLD}${PINK}◆ ${title}${RST}  ${GRAY}· ${n} items${RST}${EOL}${EOL}"

    local thumb_n=0 thumb_s=0 r idx tag txt line sb
    if (( cnt > vh )); then
      thumb_n=$(( vh * vh / cnt )); (( thumb_n < 1 )) && thumb_n=1
      thumb_s=$(( top * (vh - thumb_n) / (cnt - vh) ))
    fi

    if (( cnt == 0 )); then
      out+="   ${GRAY}No matches.${RST}${EOL}"
      for (( r = 1; r < vh; r++ )); do out+=$EOL; done
    else
      for (( r = 0; r < vh; r++ )); do
        i=$(( top + r ))
        if (( i < cnt )); then
          idx=${VIS[i]}
          printf -v tag '%-5s' "[$(( idx + 1 ))]"
          txt=${MENU_ITEMS[idx]}
          (( ${#txt} > W - 8 )) && txt="${txt:0:W-9}…"
          if (( i == pos )); then
            printf -v line '%-*s' "$W" " ▸ ${tag}${txt}"
            line="${SELBG}${line}${RST}"
          else
            line="   ${PINK}${tag}${RST}${txt}"
          fi
        else
          line=""
        fi
        sb=""
        if (( cnt > vh )); then
          if (( r >= thumb_s && r < thumb_s + thumb_n )); then sb="${LAV}┃${RST}"; else sb="${GRAY}│${RST}"; fi
        fi
        out+="${line}"$'\e[K\e['"${sbcol}"'G'"${sb}${EOL}"
      done
    fi

    # status + hint
    local status hint back_hint plural="es"
    (( cnt == 1 )) && plural=""
    if [[ $mode == filter ]]; then
      status="${SUN}/${RST} ${WHITE}${filter}${RST}${SUN}▌${RST}  ${GRAY}${cnt} match${plural}${RST}"
      hint="${SKY}type${RST} ${GRAY}to filter${RST}  ${SKY}⏎${RST} ${GRAY}select${RST}  ${SKY}Esc${RST} ${GRAY}cancel${RST}"
    else
      if [[ -n $filter ]]; then
        status="${SUN}filter:${RST} ${filter}  ${GRAY}${cnt}/${n} shown · Esc clears${RST}"
      elif [[ -n $numbuf ]]; then
        status="${SUN}jump to:${RST} ${BOLD}${numbuf}${RST}  ${GRAY}· Enter to confirm${RST}"
      elif [[ -n $note ]]; then
        status=$note
      else
        status="${GRAY}$(( cnt > 0 ? pos + 1 : 0 ))/${cnt}${RST}"
      fi
      if (( root )); then
        back_hint="${SKY}q${RST} ${GRAY}quit${RST}"
      else
        back_hint="${SKY}b${RST} ${GRAY}back${RST}  ${SKY}q${RST} ${GRAY}quit${RST}"
      fi
      hint="${SKY}↑↓${RST} ${GRAY}move${RST}  ${SKY}⏎${RST} ${GRAY}select${RST}  ${SKY}/${RST} ${GRAY}search${RST}  ${SKY}0-9${RST} ${GRAY}jump${RST}  ${back_hint}"
    fi
    out+="${EOL}  ${status}${EOL}  ${hint}"$'\e[K\e[J'
    printf '%s' "$out"

    read_key
    note=""

    if [[ $mode == filter ]]; then
      case $KEY in
        $'\e[A'|$'\eOA') (( cnt > 0 )) && pos=$(( pos > 0 ? pos - 1 : cnt - 1 )) ;;
        $'\e[B'|$'\eOB') (( cnt > 0 )) && pos=$(( (pos + 1) % cnt )) ;;
        '') if (( cnt > 0 )); then MENU_SEL=${VIS[pos]}; return 0; fi ;;
        $'\e') filter=""; mode=nav; menu_filter ""; pos=0; top=0 ;;
        $'\x7f'|$'\b')
          if [[ -z $filter ]]; then mode=nav; else filter=${filter%?}; fi
          menu_filter "$filter"; pos=0; top=0 ;;
        *)
          if (( ${#KEY} == 1 )) && [[ $KEY == [[:print:]] ]]; then
            filter+=$KEY; menu_filter "$filter"; pos=0; top=0
          fi ;;
      esac
      continue
    fi

    case $KEY in
      $'\e[A'|$'\eOA'|k) numbuf=""; (( cnt > 0 )) && pos=$(( pos > 0 ? pos - 1 : cnt - 1 )) ;;
      $'\e[B'|$'\eOB'|j) numbuf=""; (( cnt > 0 )) && pos=$(( (pos + 1) % cnt )) ;;
      $'\e[5~') numbuf=""; pos=$(( pos - vh < 0 ? 0 : pos - vh )) ;;
      $'\e[6~') numbuf=""; pos=$(( pos + vh > cnt - 1 ? cnt - 1 : pos + vh )) ;;
      $'\e[H'|$'\e[1~'|g) numbuf=""; pos=0 ;;
      $'\e[F'|$'\e[4~'|G) numbuf=""; pos=$(( cnt - 1 )) ;;
      [0-9])
        numbuf+=$KEY
        (( 10#$numbuf > n )) && numbuf=$KEY
        local target=$(( 10#$numbuf - 1 ))
        for (( i = 0; i < cnt; i++ )); do
          if (( VIS[i] == target )); then pos=$i; break; fi
        done ;;
      '/') mode=filter; numbuf="" ;;
      ''|l|$'\e[C'|$'\eOC')
        if (( cnt > 0 )); then MENU_SEL=${VIS[pos]}; return 0; fi ;;
      $'\e'|$'\x7f')
        if [[ -n $numbuf ]]; then numbuf=""
        elif [[ -n $filter ]]; then filter=""; menu_filter ""; pos=0; top=0
        else return 1; fi ;;
      b|B|h|$'\e[D'|$'\eOD') return 1 ;;
      q|Q) exit 0 ;;
    esac
  done
}

# --- URL resolution (some files only exist in lower qualities) ---------------
# resolve_url CAT NUM -> sets RES_URL and CUR_Q ; returns 1 if no quality exists
resolve_url() {
  local key="$1:$2" q u="" code tried=" "
  if [[ -n ${URL_CACHE[$key]:-} ]]; then
    RES_URL=${URL_CACHE[$key]%%|*}; CUR_Q=${URL_CACHE[$key]##*|}
    return 0
  fi
  for q in "${QUALITIES[@]}"; do
    [[ $tried == *" $q "* ]] && continue
    tried+="$q "
    printf -v u '%s/s%02de%02d-%s.mp4' "$BASE_URL" "$1" "$2" "$q"
    if (( ! HAVE_CURL )); then RES_URL=$u; CUR_Q=$q; return 0; fi
    code=$(curl -s -o /dev/null -r 0-0 --connect-timeout 4 --max-time 8 -w '%{http_code}' "$u" 2>/dev/null)
    if [[ $code == 200 || $code == 206 ]]; then
      URL_CACHE[$key]="$u|$q"; RES_URL=$u; CUR_Q=$q
      return 0
    fi
  done
  RES_URL=$u
  return 1
}

# --- player -----------------------------------------------------------------
PLAY_NOTE=""; PLAY_NOTE_UNTIL=0; PLAY_LAST=0
set_note() { PLAY_NOTE="${RED}$1${RST}"; PLAY_NOTE_UNTIL=$(( SECONDS + 2 )); }

bline() {  # bline PLAIN [COLORED]  -> appends a boxed line to $out
  local plain=$1 colored=${2-} pad
  if [[ -z $colored ]]; then
    (( ${#plain} > BW - 4 )) && plain="${plain:0:BW-5}…"
    colored=$plain
  fi
  spaces $(( BW - 4 - ${#plain} )); pad=$SP
  out+="  ${BC}│${RST} ${colored}${pad} ${BC}│${RST}${EOL}"
}

draw_player() {  # draw_player SXE TITLE N TOTAL ELAPSED
  local sxe=$1 title=$2 n=$3 total=$4 el=$5
  build_header
  local out=$'\e[H'"$HDR"
  local BW=$(( COLS - 4 )); (( BW > 72 )) && BW=72; (( BW < 30 )) && BW=30
  local BC=$LAV

  local ts h=$(( el / 3600 )) m=$(( el % 3600 / 60 )) s=$(( el % 60 ))
  if (( h > 0 )); then printf -v ts '%d:%02d:%02d' "$h" "$m" "$s"; else printf -v ts '%02d:%02d' "$m" "$s"; fi

  local ap; if (( AUTOPLAY )); then ap="${MINT}on${RST}"; else ap="${GRAY}off${RST}"; fi

  out+="  ${BOLD}${MINT}▶ NOW PLAYING${RST}${EOL}"
  local dashes; spaces $(( BW - 2 )); dashes=${SP// /─}
  out+="  ${BC}╭${dashes}╮${RST}${EOL}"

  local head="${sxe} · ${title}"
  (( ${#head} > BW - 4 )) && head="${head:0:BW-5}…"
  bline "$head" "${BOLD}${PINK}${head}${RST}"
  bline ""

  # animated equalizer + elapsed time
  local nb=$(( BW - 4 - ${#ts} - 3 )) bars="" j ph
  (( nb > 32 )) && nb=32; (( nb < 8 )) && nb=8
  for (( j = 0; j < nb; j++ )); do bars+="${RB_ESC[j % 6]}${EQ[RANDOM % 8]}"; done
  spaces $(( nb + 2 + ${#ts} )); ph=$SP
  bline "$ph" "${bars}${RST}  ${SKY}${ts}${RST}"

  bline ""
  local info="#${n} of ${total} · ${CUR_Q}"
  bline "$info" "${GRAY}${info}${RST}"
  local sw=20 filled=$(( n * 20 / total )) f e
  spaces "$filled"; f=${SP// /▰}
  spaces $(( sw - filled )); e=${SP// /▱}
  local cnt_txt="${n}/${total}"
  spaces $(( sw + 2 + ${#cnt_txt} )); ph=$SP
  bline "$ph" "${PINK}${f}${GRAY}${e}${RST}  ${GRAY}${cnt_txt}${RST}"

  out+="  ${BC}╰${dashes}╯${RST}${EOL}${EOL}"
  out+="  ${SKY}a${GRAY}/${SKY}←${RST} ${GRAY}prev${RST}   ${SKY}s${GRAY}/${SKY}→${RST} ${GRAY}next${RST}   ${SKY}p${RST} ${GRAY}autoplay:${RST} ${ap}   ${SKY}b${RST} ${GRAY}back${RST}${EOL}"
  if (( SECONDS < PLAY_NOTE_UNTIL )); then
    out+="${EOL}  ${PLAY_NOTE}${EOL}"
  fi
  out+=$'\e[J'
  printf '%s' "$out"
}

play_episode() {  # play_episode CAT_NUM EP_INDEX EPISODES...
  local cat_num=$1 ep_index=$2; shift 2
  local -a eps=("$@")
  local total=${#eps[@]}

  while true; do
    PLAY_LAST=$ep_index
    local num=$(( ep_index + 1 )) url sxe title=${eps[ep_index]}
    if (( cat_num <= SEASON_COUNT )); then
      printf -v sxe 'S%02dE%02d' "$cat_num" "$num"
    else
      sxe="${CATEGORIES[cat_num-1]} #${num}"
    fi
    show_message "${SKY}Finding ${sxe}…${RST}"
    if ! resolve_url "$cat_num" "$num"; then
      show_message "${RED}✖ Couldn't find a file for ${sxe}.${RST}
  ${GRAY}It may not exist on the server, or you're offline.${RST}
  ${GRAY}${RES_URL}${RST}"
      wait_key
      return
    fi
    url=$RES_URL

    mpv --no-terminal --no-hwdec --force-media-title="$sxe — $title" "$url" </dev/null >/dev/null 2>&1 &
    MPV_PID=$!

    local start=$SECONDS action="" rc=0
    PLAY_NOTE=""; PLAY_NOTE_UNTIL=0
    while kill -0 "$MPV_PID" 2>/dev/null; do
      draw_player "$sxe" "$title" "$num" "$total" $(( SECONDS - start ))
      if read_key 0.25; then
        case $KEY in
          a|A|$'\e[D'|$'\eOD')
            if (( ep_index > 0 )); then action=prev; break; fi
            set_note "You're already at the first episode of this category." ;;
          s|S|$'\e[C'|$'\eOC')
            if (( ep_index < total - 1 )); then action=next; break; fi
            set_note "You're already at the last episode of this category." ;;
          p|P) AUTOPLAY=$(( 1 - AUTOPLAY )) ;;
          b|B|q|Q|$'\e') action=back; break ;;
        esac
      fi
    done

    if [[ -n $action ]]; then
      kill "$MPV_PID" 2>/dev/null; wait "$MPV_PID" 2>/dev/null
    else
      wait "$MPV_PID" 2>/dev/null; rc=$?
    fi
    MPV_PID=""

    case $action in
      prev) ep_index=$(( ep_index - 1 )); continue ;;
      next) ep_index=$(( ep_index + 1 )); continue ;;
      back) return ;;
    esac

    # mpv ended on its own
    if (( rc != 0 )); then
      show_message "${RED}✖ mpv exited with code ${rc}.${RST}
  ${GRAY}The episode may not exist at this URL, or you're offline.${RST}
  ${GRAY}${url}${RST}"
      wait_key
      return
    fi
    if (( AUTOPLAY && ep_index < total - 1 )); then
      ep_index=$(( ep_index + 1 )); continue
    fi
    return
  done
}

# --- episodes menu ----------------------------------------------------------
episodes_menu() {
  local cat_num=$1 name="${CATEGORIES[$1-1]}"
  local -a eps
  show_message "${SKY}Loading ${name}…${RST}"
  mapfile -t eps < <("${LISTEPS[@]}" "$cat_num" 2>/dev/null | sed 's/\r$//' | grep -v '^[[:space:]]*$')

  if (( ${#eps[@]} == 0 )); then
    show_message "${RED}✖ listeps.sh returned no episodes for \"${name}\".${RST}"
    wait_key
    return
  fi

  local sel=0 note=""
  while true; do
    MENU_ITEMS=("${eps[@]}")
    select_menu "$name" "$sel" "$note" 0 || return
    sel=$MENU_SEL; note=""
    play_episode "$cat_num" "$sel" "${eps[@]}"
    sel=$PLAY_LAST
  done
}

# --- main menu --------------------------------------------------------------
main_menu() {
  local sel=0 i
  while true; do
    MENU_ITEMS=()
    for i in "${!CATEGORIES[@]}"; do
      if (( i < SEASON_COUNT )); then
        MENU_ITEMS+=("★  ${CATEGORIES[i]}")
      else
        MENU_ITEMS+=("✦  ${CATEGORIES[i]}")
      fi
    done
    select_menu "Pick a category" "$sel" "" 1 || exit 0
    sel=$MENU_SEL
    episodes_menu $(( sel + 1 ))
  done
}

main_menu
