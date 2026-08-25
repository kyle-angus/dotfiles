# dotfiles

Supported platforms: macOS, Debian-ish Linux, WSL, and Windows via Git Bash
(MinGW64).

## Installing

Run the following in your terminal:

```bash
bash -c "$(curl -L https://raw.githubusercontent.com/kyle-angus/dotfiles/master/install.sh)"
```

On Windows, run that from the **Git Bash** shell (not PowerShell or cmd).
Packages are installed with `winget`, so a UAC prompt may appear.

## Windows notes

### Linking

Windows only allows symlinks when Developer Mode is on, or when the shell is
elevated. Without that, `ln -s` silently makes a **copy**, so `$HOME` and the
repo drift apart the moment either one changes. `install.sh` detects this and
picks a mechanism that still tracks the repo:

| What | Mechanism | Notes |
| --- | --- | --- |
| Directories (`scripts`, `nvim`) | NTFS junction (`mklink /J`) | No elevation needed; MSYS treats it as a symlink |
| Config files | A small file that `source`s / `Include`s the real one | Survives `git pull`, which a hardlink would not |

Turning on Developer Mode (Settings → System → For developers) and re-running
`install.sh` switches everything to real symlinks.

Either way, **edit the files in this repo**, never the ones in `$HOME` — the
generated stubs say so in their first line.

### Where things land

| Config | Path |
| --- | --- |
| Neovim | `%LOCALAPPDATA%\nvim` (not `~/.config/nvim`) |
| Zellij | `%APPDATA%\Zellij\config` — note Roaming, not Local |
| SSH | `%USERPROFILE%\.ssh\config`, which includes `ssh/config` |
| Git | `%USERPROFILE%\.gitconfig`, which includes `git/gitconfig` |

`$HOME` and `%USERPROFILE%` must be the same directory. Native `git.exe` and
`ssh.exe` read `%USERPROFILE%` and ignore the `$HOME` that MSYS sets, so if you
have a `HOME` variable set in your Windows environment, unset it — otherwise
ssh quietly falls back to its defaults and commit signing cannot find the key.
`install.sh` warns when it spots this.

### Line endings

Git for Windows defaults `core.autocrlf` to `true` in its **system** config,
which rewrites checkouts to CRLF and leaves every script here failing with
`\r: command not found`. `.gitattributes` pins everything to LF, and
`git/gitconfig` sets `autocrlf = false`. If you cloned before those existed:

```bash
git add --renormalize . && git checkout -- .
```

### YubiKey / FIDO2

Use the Windows OpenSSH build (`C:\Windows\System32\OpenSSH\ssh.exe`). It
drives the token through the Windows Hello / WebAuthn API and needs no separate
provider library; some Git for Windows builds ship an MSYS `ssh` that cannot
see a security key at all. `bash/bashrc` puts the Windows one first on `PATH`,
and `yubikey-ssh` refuses to run with any other.

```bash
yubikey-ssh status
```

### Multiplexer: Zellij instead of tmux

There is no usable tmux under Git Bash, so Windows gets [Zellij](https://zellij.dev)
— upstream ships an official `x86_64-pc-windows-msvc` build, so it needs
neither WSL nor Cygwin. `install.sh` installs it and links `zellij/`.

`zellij/config.kdl` is a *translation* of `tmux/tmux.conf`, not a copy — Zellij
is modal rather than prefix-driven. What carried over:

| tmux | Zellij |
| --- | --- |
| `prefix C-a` | `Ctrl a` enters Zellij's built-in tmux mode (default is `Ctrl b`, rebound) |
| `bind a send-prefix` | `Ctrl a` `a` writes a literal `0x01` |
| `bind-key C-a last-window` | `Ctrl a` `Ctrl a` → `ToggleTab` |
| `history-limit 10000` | `scroll_buffer_size 10000` |
| `mouse on` | `mouse_mode true` |
| `tmux-resurrect` | `session_serialization` — built in, no plugin manager |

What did **not**: the status-line clock (needs a third-party plugin such as
zjstatus), `tmux-pomodoro-plus`, and `base-index`/`renumber-windows`, which
Zellij has no equivalent for. The full list is at the bottom of
`zellij/config.kdl`.

Zellij is launched with Git Bash as its shell (`default_shell`); without that
it opens `cmd.exe` and none of `bash/bashrc` applies.

After editing the config, check that Zellij agrees with you:

```bash
zellij setup --check
```

`tmux/tmux.conf` is still linked on macOS and Linux and is untouched.

### Not available under Git Bash

mosh, gpg-agent socket forwarding, and the X config (`term/`). Use WSL if you
need them; `install.sh` skips them rather than leaving files in `$HOME` that
nothing reads.

## Modifying

I've added a Dockerfile which builds an uniminimized ubuntu server image which can be used
for testing changes in a "clean" environment.

The docker image can be built from the repo root directory with:


```bash
docker build -t <name_of_image> .
```

...and can be run with:

```bash
docker run -it <name_of_image>
```

The default password for the `kangus` user is: `Test123`

## TODO

- [ ] Document scripts
- [ ] Document tmux config
- [ ] Document irssi config
- [ ] Document vim config
- [ ] Add flag to uninstall/remove changes as a result of running the install script
- [ ] Get rid of coc.nvim and use native lsp
- [ ] `scripts/repo-scanner` is a committed macOS Mach-O binary; it cannot run
      on Linux or Windows and has no source in this repo
