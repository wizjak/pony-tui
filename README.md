# pony-tui

A lightweight CLI/TUI episode browser and player for **My Little Pony: Friendship is Magic**, heavily inspired by [`ani-cli`](https://github.com/pystardust/ani-cli).

Powered by content from [fim.heartshine.gay](https://www.google.com/search?q=https://fim.heartshine.gay/) and rendered locally using `mpv`.

---

## 🚀 What's New in the Latest Version

* **Direct CLI Arguments:** Launch specific categories or individual episodes directly from your terminal (`pony-tui [category] [episode]`).
* **Resume History:** Remembers the last watched episode and allows you to resume it instantly from the main menu using the `[a]` key. Progress is securely stored following XDG standards (`$XDG_STATE_HOME`).
* **Dynamic Resolution Cycling:** Cycle and toggle video quality on-the-fly (`1080p` / `720p` / `480p`) both inside menus and directly while playing using the `[r]` key.
* **Smart URL Validation:** Automatically falls back to available lower qualities if a specific resolution doesn't exist on the server.

---

## 📦 Features

* **Full Catalog:** Seasons 1–9, movies, specials, shorts, and extra content.
* **Interactive TUI:** Built-in fast search, Vim-like keybindings (`j`/`k`, `g`/`G`), page jumps, and numbered navigation.
* **Seamless Playback:** Powered by `mpv` with autoplay toggle, quick episode skipping (`a`/`s` or arrow keys), and state preservation.
* **Customizable UI:** Pastel terminal palette with built-in `NO_COLOR` support.
* **Fast & Lightweight:** Written in pure Bash with minimal system dependencies.

---

## 💻 Usage & CLI Arguments

You can pass arguments directly to open categories or episodes without navigating the menus:

```bash
# Open the interactive main menu
pony-tui

# Open a specific category (e.g., Season 4 -> category 4)
pony-tui 4

# Play a specific episode directly (e.g., Season 4, Episode 5)
pony-tui 4 5

```

> **Category Mapping Reference:**
> `1-9`: Seasons 1 to 9 | `10`: Movies | `11`: Specials | `12`: Shorts | `13`: Clip shows | `14`: Claymatic Shorts

---

## 📦 Dependencies

`pony-tui` requires **`bash`**, **`jq`** (via listeps), **`curl`**, and **`mpv`**.

### Arch Linux / Manjaro

```bash
sudo pacman -Syu jq curl mpv

```

### Debian / Ubuntu / Linux Mint

```bash
sudo apt update && sudo apt install jq curl mpv

```

---

## 📥 Installation

You can install `pony-tui` instantly using the installation script:

```bash
curl -fsSL https://raw.githubusercontent.com/wizjak/pony-tui/refs/heads/main/install.sh | bash

```

Once installed, simply launch it from any terminal session:

```bash
pony-tui

```

---

## 🎮 Navigation & Keybindings

### Main Menu & Category Menus

| Key | Action |
| --- | --- |
| `↑` / `↓` or `j` / `k` | Move selection up / down |
| `PgUp` / `PgDn` | Scroll page up / down |
| `g` / `G` | Jump to top / bottom |
| `Enter` / `l` / `→` | Select category or episode |
| `/` | Live search / filter items |
| `0–9` | Direct jump to item number |
| `a` | **(Main Menu)** Resume last watched episode |
| `r` | Cycle video resolution (`1080p` / `720p` / `480p`) |
| `b` / `h` / `Esc` | Go back |
| `q` | Quit |

### Player Controls

| Key | Action |
| --- | --- |
| `a` / `←` | Play previous episode |
| `s` / `→` | Play next episode |
| `p` | Toggle autoplay |
| `r` | Cycle/switch resolution on-the-fly and resume playback |
| `b` / `q` / `Esc` | Stop playback and return to menu |

---

## ⚙️ Environment Variables

You can customize `pony-tui` behavior by setting environment variables in your shell configuration (`~/.bashrc`, `~/.zshrc`, etc.):

* **Video Quality:** Set preferred default video resolution (default: `1080p`).
```bash
export PONY_QUALITY="720p"

```


* **Disable Colors:** Force plain terminal output without ANSI colors.
```bash
export NO_COLOR=1

```



---

## 💖 Acknowledgments

* **[fim.heartshine.gay](https://www.google.com/search?q=https://fim.heartshine.gay/)** for providing the episode database and media hosting.
* **[ani-cli](https://github.com/pystardust/ani-cli)** for inspiring the interactive TUI flow.

---

## 📄 License

This project is licensed under the MIT License.
