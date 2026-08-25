#!/bin/bash

# Exit on error (e), on undefined variables (u), and on failure anywhere in a
# pipeline (pipefail).
set -euo pipefail

DOTFILES="$HOME/dotfiles"

# Report *where* we died. Previously the script exited silently mid-run and
# there was no way to tell which step failed.
trap 'echo "ERROR: ${BASH_SOURCE[0]}:${LINENO}: \"${BASH_COMMAND}\" failed (exit $?)" >&2' ERR

log() { printf '==> %s\n' "$*"; }
sub() { printf '    %s\n' "$*"; }

# Marker written into the stub files below, so a re-run can tell "something
# this script generated" apart from "a config the user already had".
MANAGED_MARKER='dotfiles-managed: edit the file this points at, not this one'

# ---------------------------------------------------------------------------
# platform detection
# ---------------------------------------------------------------------------

# Git Bash reports OSTYPE=msys on some builds and cygwin on others, so key off
# MSYSTEM too -- every MSYS2 / Git-for-Windows shell sets it.
is_windows() {
	case "${OSTYPE:-}${MSYSTEM:-}" in
	msys* | cygwin* | *MINGW* | *MSYS*) return 0 ;;
	*) return 1 ;;
	esac
}

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

# Windows has no POSIX symlinks unless Developer Mode is on (or the shell is
# elevated) *and* MSYS is told to create real ones. Without that `ln -s`
# quietly makes a copy, so $HOME and the repo drift apart the moment either
# side changes -- which is silent and very confusing. Probe once, cache it.
NATIVE_SYMLINKS=""
can_symlink() {
	if [ -z "$NATIVE_SYMLINKS" ]; then
		local probe
		probe="$(mktemp -d)"
		if MSYS=winsymlinks:nativestrict ln -s "$probe" "$probe/self" 2>/dev/null; then
			NATIVE_SYMLINKS=yes
		else
			NATIVE_SYMLINKS=no
		fi
		rm -rf "$probe"
	fi
	[ "$NATIVE_SYMLINKS" = yes ]
}

# Mixed form (C:/Users/...): readable by native Windows programs *and* by
# MSYS ones. Native git.exe and C:\Windows\System32\OpenSSH\ssh.exe cannot
# make any sense of the /c/Users/... form.
mixed_path() { cygpath -m "$1"; }

# Write a small file at $dest that *includes* $src -- the fallback for when we
# cannot make a real link. Every config format here has its own include
# directive. A stub keeps working after `git pull` in the dotfiles repo; a copy
# would go stale and a hardlink would be broken outright, since git replaces
# files rather than editing them in place.
write_stub() {
	local src="$1" dest="$2" style="$3"

	case "$style" in
	bash)
		printf '# %s\n# -> %s\nsource "%s"\n' "$MANAGED_MARKER" "$src" "$src" >"$dest"
		;;
	readline)
		printf '# %s\n# -> %s\n$include %s\n' "$MANAGED_MARKER" "$src" "$src" >"$dest"
		;;
	vim)
		printf '" %s\n" -> %s\nsource %s\n' "$MANAGED_MARKER" "$src" "$src" >"$dest"
		;;
	tmux)
		printf '# %s\n# -> %s\nsource-file %s\n' "$MANAGED_MARKER" "$src" "$src" >"$dest"
		;;
	git)
		# Read by native git.exe, so it needs a Windows-style path.
		printf '# %s\n# -> %s\n[include]\n\tpath = %s\n' \
			"$MANAGED_MARKER" "$src" "$(mixed_path "$src")" >"$dest"
		;;
	ssh)
		# Read by Windows OpenSSH, likewise.
		printf '# %s\n# -> %s\nInclude %s\n' \
			"$MANAGED_MARKER" "$src" "$(mixed_path "$src")" >"$dest"
		;;
	*)
		return 1
		;;
	esac
}

# True when $1 is a stub an earlier run wrote, i.e. safe to replace silently.
is_managed_stub() {
	[ -f "$1" ] && head -1 "$1" 2>/dev/null | grep -qF "$MANAGED_MARKER"
}

# Clear whatever sits at $dest so a link or stub can take its place.
#
# Plain `ln -sf` cannot retarget a symlink that points at a directory: it
# dereferences it and creates the new link *inside*, so re-running the install
# left a self-referential dotfiles/scripts/scripts behind. `-n` fixes that, but
# only if dest is unlinked first when it is a real directory.
clear_dest() {
	local dest="$1" backup

	if [ -L "$dest" ]; then
		# A junction looks like a symlink to MSYS, but `rm` cannot always
		# remove one -- a reparse point needs rmdir.
		rm -f "$dest" 2>/dev/null || rmdir "$dest" 2>/dev/null || true
	elif [ -f "$dest" ]; then
		if is_managed_stub "$dest"; then
			rm -f "$dest"
		else
			# A real config the user already had -- Git Bash ships its own
			# ~/.bashrc, for instance. Never delete it outright.
			backup="$dest.backup.$(date +%Y%m%d%H%M%S)"
			sub "$dest already exists -- moving it to $backup"
			mv "$dest" "$backup"
		fi
	elif [ -d "$dest" ]; then
		if [ -z "$(ls -A "$dest")" ]; then
			rmdir "$dest"
		else
			# Never silently destroy a real config directory.
			backup="$dest.backup.$(date +%Y%m%d%H%M%S)"
			sub "$dest is a non-empty directory -- moving it to $backup"
			mv "$dest" "$backup"
		fi
	fi
}

# Link $src -> $dest. $3 names the include syntax to fall back to on Windows
# when real symlinks are unavailable; leave it off for paths that have no
# include directive (directories, or files nothing ever sources).
link() {
	local src="$1" dest="$2" style="${3:-}"

	if [ ! -e "$src" ] && [ ! -d "$src" ]; then
		sub "SKIP $dest (missing source: $src)"
		return 0
	fi

	mkdir -p "$(dirname "$dest")"
	clear_dest "$dest"

	if ! is_windows; then
		ln -sfn "$src" "$dest"
		sub "$dest -> $src"
		return 0
	fi

	if can_symlink; then
		MSYS=winsymlinks:nativestrict ln -sfn "$src" "$dest"
		sub "$dest -> $src"
		return 0
	fi

	win_link "$src" "$dest" "$style"
}

# Windows without symlink privilege.
#
#   directories -> a junction. `mklink /J` needs no elevation, and MSYS treats
#                  the result as a symlink, so it behaves like one.
#   files       -> an include-stub (see write_stub).
win_link() {
	local src="$1" dest="$2" style="$3"

	if [ -d "$src" ]; then
		if cmd //c mklink //J "$(cygpath -w "$dest")" "$(cygpath -w "$src")" >/dev/null 2>&1; then
			sub "$dest =junction=> $src"
		else
			sub "WARNING: could not create a junction at $dest"
		fi
		return 0
	fi

	if [ -n "$style" ] && write_stub "$src" "$dest" "$style"; then
		sub "$dest =include=> $src"
		return 0
	fi

	# Last resort, and worth saying loudly: this one will not track the repo.
	cp -f "$src" "$dest"
	sub "WARNING: $dest is a COPY of $src -- re-run install.sh after editing it"
}

# Put brew on PATH in *this* shell. The Homebrew installer only edits your
# profile; it does not touch the running shell, so the `brew install` calls
# that used to follow it died with "command not found".
load_brew_env() {
	local candidate
	for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
		if [ -x "$candidate" ]; then
			eval "$("$candidate" shellenv)"
			return 0
		fi
	done
	return 1
}

brew_install() {
	local formula
	for formula in "$@"; do
		if brew list --formula "$formula" &>/dev/null; then
			sub "$formula already installed"
		else
			sub "installing $formula..."
			brew install "$formula"
		fi
	done
}

# ---------------------------------------------------------------------------
# macOS
# ---------------------------------------------------------------------------

function setup_macos {
	log "Starting setup for macOS"

	if ! load_brew_env; then
		log "Installing homebrew..."
		# NONINTERACTIVE=1 is Homebrew's own switch for unattended installs.
		# The old `yes | /bin/bash -c "$(curl ...)"` form aborted the script:
		# when the installer finished, `yes` died of SIGPIPE (exit 141) and
		# `set -o pipefail` handed that to `set -e`. Everything after the
		# Homebrew step was skipped.
		NONINTERACTIVE=1 /bin/bash -c \
			"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

		load_brew_env || {
			echo "ERROR: homebrew installed but 'brew' was not found." >&2
			exit 1
		}
	fi
	sub "using $(brew --prefix)"

	log "Installing packages..."
	# openssh: macOS's own OpenSSH is built without ENABLE_SK_INTERNAL, so it
	# cannot use a FIDO2/YubiKey SSH key at all ("internal security key support
	# not enabled"). Homebrew's build links libfido2 and works. brew's bin
	# directory precedes /usr/bin on PATH, so this one wins.
	brew_install bash bash-completion@2 git tmux coreutils fzf neovim openssh libfido2 ykman

	log "Setting up fzf key bindings..."
	# --all answers the installer's prompts (it uses `read`, so an unattended
	# run would otherwise hang). --no-update-rc stops it appending source lines
	# to ~/.bashrc, which is a symlink into this repo.
	"$(brew --prefix fzf)/install" --all --no-update-rc

	get_dotfiles
	setup_ssh
	create_links

	setup_tmux
	setup_node
	setup_shell
}

# `chsh -s /bin/bash` pinned the login shell to macOS's bash 3.2 even though we
# just installed bash 5.x -- which is why `[ -v VAR ]` (bash 4.2+) failed in
# .bashrc. Point the login shell at the Homebrew bash instead.
function setup_shell {
	local brew_bash
	brew_bash="$(brew --prefix)/bin/bash"

	if [ ! -x "$brew_bash" ]; then
		sub "$brew_bash not found, leaving login shell alone"
		return 0
	fi

	if ! grep -qxF "$brew_bash" /etc/shells; then
		log "Adding $brew_bash to /etc/shells (requires sudo)..."
		echo "$brew_bash" | sudo tee -a /etc/shells >/dev/null
	fi

	if [ "${SHELL:-}" != "$brew_bash" ]; then
		log "Changing login shell to $brew_bash..."
		chsh -s "$brew_bash"
		sub "open a new terminal for this to take effect"
	else
		sub "login shell already $brew_bash"
	fi
}

# ---------------------------------------------------------------------------
# Linux
# ---------------------------------------------------------------------------

function setup_linux {
	log "Starting setup for linux..."

	# Assume we're using debian...
	log "Installing updates..."
	sudo apt-get update

	log "Installing upgrades..."
	sudo apt-get upgrade -y

	log "Installing vim, tmux, mosh, fzf, lynx, build-essential..."
	sudo apt-get install vim tmux mosh fzf lynx build-essential -y

	# udev rules so the YubiKey's FIDO2 HID device is reachable without root.
	log "Installing FIDO2 support..."
	sudo apt-get install libfido2-1 libu2f-udev -y

	get_dotfiles
	setup_ssh
	create_links
	setup_gpg
	setup_tmux
	setup_node
}

function setup_gpg {
	log "Setting up gpg..."

	sub "installing pcscd, scdaemon, gnupg2, pcsc-tools..."
	sudo apt-get install pcscd scdaemon gnupg2 pcsc-tools -y

	# -p: the old plain `mkdir` aborted the run when ~/.gnupg already existed.
	mkdir -p "$HOME/.gnupg"
	chmod 700 "$HOME/.gnupg"

	local conf="$HOME/.gnupg/gpg-agent.conf"
	if [ -f "$conf" ] && grep -q "enable-ssh-support" "$conf"; then
		sub "gpg-agent.conf already configured"
	else
		# >> so we don't discard any other settings already in the file.
		echo "enable-ssh-support" >>"$conf"
		sub "enabled ssh support in gpg config"
	fi
}

# ---------------------------------------------------------------------------
# Windows (Git Bash / MinGW64)
# ---------------------------------------------------------------------------

winget_install() {
	if ! command -v winget &>/dev/null; then
		sub "winget not found -- skipping package installation"
		sub "install 'App Installer' from the Microsoft Store, then re-run"
		return 0
	fi

	local pkg
	for pkg in "$@"; do
		if winget list --exact --id "$pkg" >/dev/null 2>&1; then
			sub "$pkg already installed"
		else
			sub "installing $pkg..."
			# --disable-interactivity keeps winget from prompting, but a UAC
			# dialog can still appear for machine-scope packages. A failure
			# here is not fatal: the remaining packages still install.
			winget install --exact --id "$pkg" --silent --disable-interactivity \
				--accept-package-agreements --accept-source-agreements ||
				sub "WARNING: $pkg did not install"
		fi
	done
}

function setup_windows {
	log "Starting setup for Windows (Git Bash)..."

	if [[ "${MSYSTEM:-}" != MINGW* ]]; then
		sub "WARNING: MSYSTEM is '${MSYSTEM:-unset}', expected MINGW64."
		sub "These dotfiles target the Git Bash / MinGW64 shell."
	fi

	# Native git.exe and C:\Windows\System32\OpenSSH\ssh.exe resolve ~ and
	# their config locations from %USERPROFILE%, ignoring the $HOME that MSYS
	# sets. When the two disagree, every file linked below lands where only
	# Git Bash will look for it: ssh silently falls back to its built-in
	# defaults and commit signing cannot find the key.
	local winhome
	winhome="$(cygpath -u "${USERPROFILE:-}" 2>/dev/null || true)"
	if [ -n "$winhome" ] && [ "$(cd "$HOME" && pwd -P)" != "$(cd "$winhome" && pwd -P)" ]; then
		sub "WARNING: \$HOME ($HOME) and %USERPROFILE% ($winhome) differ."
		sub "Native git and ssh read %USERPROFILE%, so they will not see"
		sub "the config linked into \$HOME. Unset HOME in your Windows"
		sub "environment variables so Git Bash uses %USERPROFILE%."
	fi

	if can_symlink; then
		sub "native symlinks available"
	else
		sub "no symlink privilege -- using junctions for directories and"
		sub "include-stubs for config files; both track the repo correctly."
		sub "For real symlinks instead: turn on Developer Mode under"
		sub "Settings > System > For developers, then re-run this script."
	fi

	log "Installing packages..."
	winget_install \
		Neovim.Neovim \
		junegunn.fzf \
		BurntSushi.ripgrep.MSVC \
		Yubico.YubiKeyManager

	get_dotfiles
	setup_ssh
	create_links
	setup_node

	# tmux, mosh and gpg-agent socket forwarding have no usable Git Bash
	# build. Use WSL if you need them.
	sub "skipping tmux/gpg -- not available under Git Bash"
}

# ---------------------------------------------------------------------------
# shared steps
# ---------------------------------------------------------------------------

function setup_node {
	log "Setting up node..."

	# nvm-sh is a POSIX shell script and does not manage Windows node builds.
	# Its Windows counterpart (nvm4w) is a separate .exe with its own
	# installer, so there is nothing to source here.
	if is_windows; then
		if command -v nvm &>/dev/null; then
			sub "nvm for Windows already installed"
		elif command -v node &>/dev/null; then
			sub "node $(node --version) already on PATH -- leaving it alone"
		else
			sub "installing nvm for Windows..."
			winget_install CoreyButler.NVMforWindows
			sub "open a new shell, then: nvm install lts && nvm use lts"
		fi
		return 0
	fi

	export NVM_DIR="$HOME/.nvm"

	if [ ! -s "$NVM_DIR/nvm.sh" ]; then
		sub "installing nvm..."
		# PROFILE=/dev/null: the installer would otherwise append its own init
		# lines to ~/.bashrc (a symlink into this repo). bash/bashrc already
		# sources nvm.sh itself.
		curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh |
			PROFILE=/dev/null bash
	else
		sub "nvm already installed"
	fi

	# nvm.sh is not written to survive `set -eu`, so relax them while sourcing.
	# This step used to run `source "$HOME/.bashrc"`, which ended the whole
	# install: load_executables returned 1 whenever ~/.cargo/env was absent.
	set +eu
	# shellcheck disable=SC1091
	\. "$NVM_DIR/nvm.sh"
	set -eu

	sub "installing LTS version of node..."
	nvm install --lts

	if command -v corepack &>/dev/null; then
		sub "enabling corepack (provides yarn/pnpm)..."
		corepack enable
	fi
}

function get_dotfiles {
	if [ -d "$DOTFILES/.git" ]; then
		log "Updating dotfiles..."
		# --ff-only, and non-fatal: a dirty working tree used to abort the run.
		if ! git -C "$DOTFILES" pull --ff-only; then
			sub "WARNING: could not fast-forward $DOTFILES (local changes?), continuing"
		fi
	else
		log "Cloning dotfiles..."
		git clone https://github.com/kyle-angus/dotfiles.git "$DOTFILES"
		git -C "$DOTFILES" remote set-url origin git@github.com:kyle-angus/dotfiles.git
	fi
}

function setup_tmux {
	log "Setting up tmux..."

	local tpm="$HOME/.tmux/plugins/tpm"
	if [ -d "$tpm/.git" ]; then
		sub "TPM already installed"
	else
		# Cloning into an existing directory is a fatal error, so every re-run
		# of the old script died here.
		mkdir -p "$(dirname "$tpm")"
		git clone https://github.com/tmux-plugins/tpm "$tpm"
	fi

	sub "Prefix+I to install plugins if you're in tmux already"
}

function setup_ssh {
	log "Setting up ssh..."

	mkdir -p "$HOME/.ssh"
	# Windows ignores POSIX modes -- access is an NTFS ACL matter there, and
	# Windows OpenSSH does not object to what MSYS reports.
	if ! is_windows; then
		chmod 700 "$HOME/.ssh"
	fi

	# TODO: Setup keybase to automatically pull down keys
}

function create_links {
	log "Creating symlinks..."

	link "$DOTFILES/bash/aliases" "$HOME/.aliases" bash
	link "$DOTFILES/bash/bashrc" "$HOME/.bashrc" bash
	link "$DOTFILES/bash/bash_profile" "$HOME/.bash_profile" bash
	link "$DOTFILES/bash/profile" "$HOME/.profile" bash
	link "$DOTFILES/bash/inputrc" "$HOME/.inputrc" readline
	link "$DOTFILES/git/gitconfig" "$HOME/.gitconfig" git
	link "$DOTFILES/vim/vimrc" "$HOME/.vimrc" vim
	link "$DOTFILES/scripts" "$HOME/.scripts"

	# This was missing entirely, so ~/.ssh/config never existed and none of
	# the host blocks (github.com, revres, gemini) were ever in effect.
	link "$DOTFILES/ssh/config" "$HOME/.ssh/config" ssh

	# ~/.gitignore is not a file git reads on its own -- core.excludesFile in
	# git/gitconfig already points straight at git/gitignore in the repo. The
	# link is kept on mac and linux because it costs nothing there, but on
	# Windows there is no include syntax for it, so linking would leave a
	# stale *copy* in $HOME. Skip it instead.
	if ! is_windows; then
		link "$DOTFILES/git/gitignore" "$HOME/.gitignore"
	fi

	if is_windows; then
		# Native nvim.exe reads %LOCALAPPDATA%\nvim, never ~/.config/nvim.
		link "$DOTFILES/nvim" "$(cygpath -u "$LOCALAPPDATA")/nvim"
		# zsh, tmux and X have no Git Bash story; skip them rather than
		# litter $HOME with files nothing will ever read.
		sub "skipping zshenv/tmux.conf/xprofile/Xresources on Windows"
		return 0
	fi

	link "$DOTFILES/zsh/zshenv" "$HOME/.zshenv"
	link "$DOTFILES/tmux/tmux.conf" "$HOME/.tmux.conf" tmux
	link "$DOTFILES/term/xprofile" "$HOME/.xprofile"
	link "$DOTFILES/term/Xresources" "$HOME/.Xresources"

	# This read `-d "$HOME/.config/nvm"` -- a typo for nvim. On a clean machine
	# the test failed, so the else branch just created an empty
	# ~/.config/nvim and the config was never linked at all.
	link "$DOTFILES/nvim" "$HOME/.config/nvim"
}

# ---------------------------------------------------------------------------

function setup {
	log "Starting setup..."

	if is_windows; then
		# There is no sudo here; winget raises UAC itself when it needs to.
		setup_windows
		log "Setup for Windows completed!"
		echo
		log "To set up the YubiKey SSH key for GitHub, run:"
		sub "yubikey-ssh generate   (first time)"
		sub "yubikey-ssh recover    (key already exists on the token)"
		return 0
	fi

	# Authenticate up front so the first sudo prompt isn't buried in output.
	sudo -v

	if [[ "$OSTYPE" == "linux-gnu"* ]]; then
		setup_linux
		log "Setup for Linux completed!"
	elif [[ "$OSTYPE" == "darwin"* ]]; then
		setup_macos
		log "Setup for macOS completed!"
		echo
		log "To set up the YubiKey SSH key for GitHub, run:"
		sub "yubikey-ssh generate   (first time)"
		sub "yubikey-ssh recover    (key already exists on the token)"
	else
		echo "OS not supported, exiting." >&2
		exit 1
	fi
}

setup
