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

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

# Symlink src -> dest, replacing whatever is already at dest.
#
# Plain `ln -sf` cannot retarget a symlink that points at a directory: it
# dereferences it and creates the new link *inside*, so re-running the install
# left a self-referential dotfiles/scripts/scripts behind. `-n` fixes that, but
# only if dest is unlinked first when it is a real directory.
link() {
	local src="$1" dest="$2"

	if [ ! -e "$src" ] && [ ! -d "$src" ]; then
		sub "SKIP $dest (missing source: $src)"
		return 0
	fi

	if [ -L "$dest" ] || [ -f "$dest" ]; then
		rm -f "$dest"
	elif [ -d "$dest" ]; then
		if [ -z "$(ls -A "$dest")" ]; then
			rmdir "$dest"
		else
			# Never silently destroy a real config directory.
			local backup="$dest.backup.$(date +%Y%m%d%H%M%S)"
			sub "$dest is a non-empty directory -- moving it to $backup"
			mv "$dest" "$backup"
		fi
	fi

	mkdir -p "$(dirname "$dest")"
	ln -sfn "$src" "$dest"
	sub "$dest -> $src"
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
	brew_install bash bash-completion@2 git tmux coreutils fzf neovim

	log "Setting up fzf key bindings..."
	# --all answers the installer's prompts (it uses `read`, so an unattended
	# run would otherwise hang). --no-update-rc stops it appending source lines
	# to ~/.bashrc, which is a symlink into this repo.
	"$(brew --prefix fzf)/install" --all --no-update-rc

	get_dotfiles
	create_links

	setup_tmux
	setup_node
	setup_ssh
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

	get_dotfiles
	create_links
	setup_gpg
	setup_tmux
	setup_ssh
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
# shared steps
# ---------------------------------------------------------------------------

function setup_node {
	log "Setting up node..."

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
	chmod 700 "$HOME/.ssh"

	# TODO: Setup keybase to automatically pull down keys
}

function create_links {
	log "Creating symlinks..."

	link "$DOTFILES/bash/aliases" "$HOME/.aliases"
	link "$DOTFILES/bash/bashrc" "$HOME/.bashrc"
	link "$DOTFILES/bash/bash_profile" "$HOME/.bash_profile"
	link "$DOTFILES/bash/profile" "$HOME/.profile"
	link "$DOTFILES/bash/inputrc" "$HOME/.inputrc"
	link "$DOTFILES/git/gitconfig" "$HOME/.gitconfig"
	link "$DOTFILES/git/gitignore" "$HOME/.gitignore"
	link "$DOTFILES/vim/vimrc" "$HOME/.vimrc"
	link "$DOTFILES/zsh/zshenv" "$HOME/.zshenv"
	link "$DOTFILES/tmux/tmux.conf" "$HOME/.tmux.conf"
	link "$DOTFILES/scripts" "$HOME/.scripts"
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

	# Authenticate up front so the first sudo prompt isn't buried in output.
	sudo -v

	if [[ "$OSTYPE" == "linux-gnu"* ]]; then
		setup_linux
		log "Setup for Linux completed!"
	elif [[ "$OSTYPE" == "darwin"* ]]; then
		setup_macos
		log "Setup for macOS completed!"
	else
		echo "OS not supported, exiting." >&2
		exit 1
	fi
}

setup
