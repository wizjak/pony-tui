<div align="center">

# 🦄 pony-tui

**Watch every pony, straight from your terminal** 🌈

An [ani-cli](https://github.com/pystardust/ani-cli)-style player for *My Little Pony: Friendship is Magic*, powered by [heartshine](https://fim.heartshine.gay/).

![License: MIT](https://img.shields.io/badge/license-MIT-c3a6ff?style=flat-square)
![Made with Bash](https://img.shields.io/badge/made%20with-Bash-f9a8d4?style=flat-square&logo=gnubash&logoColor=white)
![Platform: Linux](https://img.shields.io/badge/platform-Linux-7dd3fc?style=flat-square&logo=linux&logoColor=white)
![Player: mpv](https://img.shields.io/badge/player-mpv-fde68a?style=flat-square)

</div>

```text
▄▄▄▄   ▄▄▄  ▄▄  ▄▄ ▄▄ ▄▄    ▄▄▄▄▄▄ ▄▄ ▄▄ ▄▄
██▄█▀ ██▀██ ███▄██ ▀███▀ ▄▄▄  ██   ██ ██ ██
██    ▀███▀ ██ ▀██   █        ██   ▀███▀ ██
```

🟥🟧🟨🟩🟦🟪

Browse every season, movie and special from your terminal, pick an episode and watch it in `mpv`. Written in pure Bash, no bloat. 💜

> [!NOTE]
> pony-tui is an unofficial fan project. It doesn't host or distribute any media: the catalog and videos come from heartshine's servers. My Little Pony is a trademark of Hasbro.

## ✨ Features

- 📚 **Full catalog:** seasons 1–9, movies, specials, shorts, clip shows and claymation shorts.
- ⚡ **Fast navigation:** arrow keys or Vim-style keys, live search, page jumps and jump-to-number.
- ⏯️ **Resume:** remembers the last episode you watched and reopens it with a single key.
- 🎛️ **Playback controls:** previous/next episode, autoplay and on-the-fly resolution switching.
- 🧠 **Smart quality fallback:** if an episode isn't available in your chosen resolution, it automatically tries the next best one.
- 🎮 **Discord Rich Presence:** optional, shows what you're watching.
- 🎨 **Pastel UI:** adapts to your terminal size and respects `NO_COLOR`.

## 📋 Requirements

| Dependency | Needed for |
| --- | --- |
| `bash` 4.0+ | 🐚 running pony-tui |
| `mpv` | 🎬 playing episodes |
| `jq` | 📖 reading the episode catalog |
| `curl` | 🌐 downloading the catalog and checking which resolutions exist |
| `git` | 📦 the installer |

You also need an interactive terminal with 256-color support (any modern terminal works).

> [!WARNING]
> pony-tui is built for Linux. macOS ships bash 3.2 by default, so you would need a newer bash from Homebrew.

Install the dependencies with your package manager:

```bash
# Arch / Manjaro
sudo pacman -S --needed git mpv jq curl

# Debian / Ubuntu / Linux Mint
sudo apt install git mpv jq curl

# Fedora
sudo dnf install git mpv jq curl

# openSUSE
sudo zypper install git mpv jq curl
```

## 📥 Installation

```bash
curl -fsSL https://raw.githubusercontent.com/wizjak/pony-tui/refs/heads/main/install.sh | bash
```

The installer checks your dependencies (offering to install any that are missing), downloads pony-tui to `~/.config/pony-tui` and installs the `pony-tui` command in `/usr/local/bin`, which asks for `sudo` once.

Then run it from any terminal:

```bash
pony-tui
```

**🔧 Installer options**

| Option | Description |
| --- | --- |
| `-y`, `--yes` | Don't ask questions, assume "yes" |
| `--uninstall` | Remove pony-tui from this machine |
| `-h`, `--help` | Show help |

To pass options when piping from `curl`:

```bash
curl -fsSL https://raw.githubusercontent.com/wizjak/pony-tui/refs/heads/main/install.sh | bash -s -- --yes
```

**🔄 Updating:** run the installer again.

**🛠️ Manual install** (no `sudo` required):

```bash
git clone https://github.com/wizjak/pony-tui
cd pony-tui
./pony-tui.sh
```

`listeps.sh` must stay in the same folder as `pony-tui.sh`.

## 🚀 Usage

```bash
pony-tui          # open the main menu
pony-tui 4        # open the episode list of category 4 (Season 4)
pony-tui 4 5      # play episode 5 of category 4 right away
pony-tui --help   # show usage
```

| Category | Content |
| --- | --- |
| `1`–`9` | ⭐ Seasons 1 to 9 |
| `10` | 🎞️ Movies |
| `11` | ✦ Specials |
| `12` | ✦ Shorts |
| `13` | ✦ Clip shows |
| `14` | 🧱 Claymatic shorts |

## ⌨️ Keybindings

### 📂 Menus

| Key | Action |
| --- | --- |
| `↑` / `↓` or `k` / `j` | Move selection |
| `PgUp` / `PgDn` | Scroll one page |
| `g` / `G` | Jump to top / bottom |
| `0`–`9` | Type an item number to jump to it |
| `Enter` / `l` / `→` | Select |
| `/` | Search: type to filter the list, `Esc` to clear |
| `a` | Resume the last watched episode (main menu only) |
| `r` | Cycle resolution: 1080p → 720p → 480p |
| `b` / `h` / `←` / `Esc` | Go back |
| `q` | Quit |

### ▶️ Player

When you start an episode, `mpv` opens in its own window and pony-tui shows a "Now playing" panel in the terminal. Use these keys in the terminal:

| Key | Action |
| --- | --- |
| `a` / `←` | ⏮️ Previous episode |
| `s` / `→` | ⏭️ Next episode |
| `p` | 🔁 Toggle autoplay |
| `r` | 📺 Switch resolution and resume from the same point |
| `d` | 🎮 Toggle Discord Rich Presence (only if `pony-rpc` is available) |
| `b` / `q` / `Esc` | ⏹️ Stop playback and go back |

> [!TIP]
> `mpv`'s own shortcuts (pause, seek, fullscreen…) work in its window as usual.

## ⚙️ Configuration

Set these in your shell configuration (`~/.bashrc`, `~/.zshrc`…):

| Variable | Default | Description |
| --- | --- | --- |
| `PONY_QUALITY` | `1080p` | Preferred resolution (`1080p`, `720p`, `480p` or `360p`) |
| `PONY_RPC` | `1` | Set to `0` to disable Discord Rich Presence |
| `NO_COLOR` | unset | Set to any value to disable colors |
| `XDG_STATE_HOME` | `~/.local/state` | Base folder for the saved state |

```bash
export PONY_QUALITY="720p"
```

**📁 Files**

| Path | Contents |
| --- | --- |
| `~/.config/pony-tui/` | The installed program |
| `~/.config/pony-tui/db.json` | Episode catalog, downloaded on first use. Delete it to refresh it |
| `${XDG_STATE_HOME:-~/.local/state}/pony-tui/last` | Last watched episode |

## 🎮 Discord Rich Presence

Show your friends what you're watching! Rich Presence is optional and handled by `pony-rpc`, a small Go program that pony-tui launches while an episode plays. A prebuilt binary is included in the repository, so a normal install already has it. You need the Discord desktop app running.

If the bundled binary doesn't work on your system, build it yourself (requires [Go](https://go.dev/)) from [pony-rpc-source](https://github.com/wizjak/pony-rpc-source):

```bash
git clone https://github.com/wizjak/pony-rpc-source
cd pony-rpc-source
go build -o pony-rpc .
```

Then put the resulting `pony-rpc` binary next to `pony-tui.sh` (in `~/.config/pony-tui/`) or anywhere in your `PATH`. Use `d` in the player or `PONY_RPC=0` to turn it off.

## 🔍 How it works

1. 📖 `listeps.sh` downloads the episode catalog (`db.json`) from heartshine and uses `jq` to list the titles of a category.
2. 🔗 pony-tui builds the video URL for the chosen episode and, with `curl`, checks which resolutions exist for it.
3. 🎬 `mpv` plays the video while pony-tui handles navigation and saves your progress.

## 💖 Acknowledgments

- 🌈 [heartshine](https://fim.heartshine.gay/) for the episode catalog and media hosting.
- 🍥 [ani-cli](https://github.com/pystardust/ani-cli) for the inspiration.

## 📄 License

Released under the [MIT License](LICENSE).

<div align="center">


</div>
