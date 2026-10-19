# pony-tui

<img width="853" height="489" alt="image" src="https://github.com/user-attachments/assets/7b22856a-34ea-45b3-b53d-05e13940251d" />


A lightweight CLI/TUI episode browser and player for **My Little Pony: Friendship is Magic**, heavily inspired by [`ani-cli`](https://github.com/pystardust/ani-cli).

Powered by content from [fim.heartshine.gay](https://fim.heartshine.gay/) and rendered locally using `mpv`.

---

## 🚀 Features

- **Full Catalog:** Seasons 1–9, movies, specials, shorts, and extra content.
- **Interactive TUI:** Built-in fast search, Vim-like keybindings (`j`/`k`, `g`/`G`), page jumps, and numbered navigation.
- **Seamless Playback:** Powered by `mpv` with autoplay toggle and quick episode skipping (`a`/`s` or arrow keys).
- **Customizable UI:** Pastel terminal palette with built-in `NO_COLOR` support.
- **Fast & Lightweight:** Written in pure Bash with minimal system dependencies.

---

## 📦 Dependencies

`pony-tui` requires **`bash`**, **`jq`**, **`curl`**, and **`mpv`**.

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

### Menu Navigation
| Key | Action |
| --- | --- |
| `↑` / `↓` or `j` / `k` | Move selection up / down |
| `PgUp` / `PgDn` | Scroll page up / down |
| `g` / `G` | Jump to top / bottom |
| `Enter` / `l` / `→` | Select category or episode |
| `/` | Live search / filter items |
| `0–9` | Direct jump to item number |
| `b` / `h` / `Esc` | Go back |
| `q` | Quit |

### Player Controls
| Key | Action |
| --- | --- |
| `a` / `←` | Play previous episode |
| `s` / `→` | Play next episode |
| `p` | Toggle autoplay |
| `b` / `q` / `Esc` | Stop playback and return to menu |

---

## ⚙️ Environment Variables

You can customize `pony-tui` behavior by setting environment variables in your shell configuration (`~/.bashrc`, `~/.zshrc`, etc.):

- **Video Quality:** Set preferred video resolution (default: `1080p`).
  ```bash
  export PONY_QUALITY="720p"
  ```
- **Disable Colors:** Force plain terminal output without ANSI colors.
  ```bash
  export NO_COLOR=1
  ```

---

## 💖 Acknowledgments

- **[fim.heartshine.gay](https://fim.heartshine.gay/)** for providing the episode database and media hosting.
- **[ani-cli](https://github.com/pystardust/ani-cli)** for inspiring the interactive TUI flow.

---

## 📄 License

This project is licensed under the MIT License.
