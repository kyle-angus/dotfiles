#!/bin/bash

# Fail on a single command in a pipeline
set -o pipefail

# Exit if there's an error (e) or if an undefined (u) variable is used
set -eu

function setup_macos {
	echo "Starting setup for macOS"

	# Install Homebrew
	if ! command -v brew &>/dev/null; then
		echo "Installing homebrew..."
		yes | /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
	fi

	echo "Installing latest bash & bash completions..."
	brew install bash
	brew install bash-completion@2

	# Install the latest Git
	echo "Installing git..."
	brew install git

	# Install Tmux
	echo "Installing tmux..."
	brew install tmux

	echo "Installing coreutils..."
	brew install coreutils

	echo "Installing fzf..."
	brew install fzf
	$(brew --prefix)/opt/fzf/install

	# TODO: Add steps for installing docker
	get_dotfiles
	create_links

	setup_tmux
	setup_node

}

function setup_linux {
	echo "Starting setup for linux..."

	# Assume we're using debian...
	echo "Installing updates..."
	sudo apt update &>/dev/null

	echo "Installing upgrades..."
	sudo apt-get upgrade -y &>/dev/null

	echo "Installing tmux, mosh, fzf, lynx, build-essntial..."
	sudo apt install vim tmux mosh fzf lynx build-essential -y &>/dev/null

	get_dotfiles
	create_links
	setup_gpg
	setup_tmux
	setup_ssh

	if ! command -v nvm; then
		setup_node
	fi

}

function setup_gpg {
	echo "Setting up gpg..."

	echo "Installing pcsd, scdaemon, gnupg2, pcsc-tools..."
	sudo apt-get install pcscd scdaemon gnupg2 pcsc-tools -y &>/dev/null

	# Setup the .gnp-agent.conf in $HOME/.gnupg/ to include enable-ssh-support
	if [ ! -f "$HOME/.gnupg/gpg-agent.conf" ]; then
		echo "Creating gpg config directory..."
		mkdir "$HOME/.gnupg"
		touch "$HOME/.gnupg/gpg-agent.conf"
		echo "enable-ssh-support" >"$HOME/.gnupg/gpg-agent.conf"
		echo "Enabled ssh in gpg config..."
	elif grep -q "enable-ssh-support" <"$HOME/.gnupg/gpg-agent.conf"; then
		echo "gpg-agent.conf already configured"
	else
		echo "enable-ssh-support" >"$HOME/.gnupg/gpg-agent.conf"
		echo "Enabled ssh in gpg config..."
	fi
}

function setup_node {
	echo "Setting up node..."

	# Install NVM
	echo "Installing nvm..."
	curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash &>/dev/null

	# Source our profile again so we can run nvm
	source "$HOME/.bashrc"

	# Install the latest LTS version of NodeJS
	echo "Installing LTS version of node..."
	nvm install --lts &>/dev/null

	echo "Installing yarn..."
	source "$HOME/.bashrc"
	corepack enable
	npm i -g --force yarn &>/dev/null

	#TODO: Setup npm prefix for macOS (and maybe linux)
}

function get_dotfiles {
	echo "Pulling latest dotfiles..."
	previous_dir=$(pwd)

	if [ ! -d "$HOME/dotfiles" ]; then
		git clone https://github.com/kyle-angus/dotfiles.git "$HOME/dotfiles" &>/dev/null
		cd "$HOME/dotfiles"
		git remote set-url origin git@github.com:kyle-angus/dotfiles.git
	else
		cd "$HOME/dotfiles"
		git pull &>/dev/null
	fi

	cd "$previous_dir"
}

function setup_tmux {
	echo "Setting up tmux..."

	# Setup TPM / Tmux
	echo "Installing TPM..."
	mkdir -p "$HOME/.tmux/plugins"
	git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm" &>/dev/null

	echo "Prefix+I to install plugins if you're in TMUX already"

}

function setup_ssh {
	echo "Setting up ssh..."

	if [ ! -d "$HOME/.ssh" ]; then
		mkdir "$HOME/.ssh"
		chmod 700 "$HOME/.ssh"
	fi

	# TODO: Setup keybase to automatically pull down keys
}

function create_links {
	echo "Creating symlinks..."
	DOTFILES="$HOME/dotfiles"

	# TODO: May need to add checks for each of these?
	ln -sf "$DOTFILES/bash/aliases" "$HOME/.aliases"
	ln -sf "$DOTFILES/bash/bashrc" "$HOME/.bashrc"
	ln -sf "$DOTFILES/bash/bashrc" "$HOME/.bash_profile"
	ln -sf "$DOTFILES/bash/profile" "$HOME/.profile"
	ln -sf "$DOTFILES/bash/inputrc" "$HOME/.inputrc"
	ln -sf "$DOTFILES/git/gitconfig" "$HOME/.gitconfig"
	ln -sf "$DOTFILES/git/gitignore" "$HOME/.gitignore"
	ln -sf "$DOTFILES/npm/npmrc" "$HOME/.npmrc"
	ln -sf "$DOTFILES/vim/vimrc" "$HOME/.vimrc"
	ln -sf "$DOTFILES/zsh/zshenv" "$HOME/.zshenv"
	ln -sf "$DOTFILES/tmux/tmux.conf" "$HOME/.tmux.conf"
	ln -sf "$DOTFILES/scripts" "$HOME/.scripts"
	ln -sf "$DOTFILES/term/xprofile" "$HOME/.xprofile"
	ln -sf "$DOTFILES/term/Xresources" "$HOME/.Xresources"

	if [ -d "$HOME/.config/nvm" ]; then
		ln -sf "$DOTFILES/nvim" "$HOME/.config/nvim"
	else
		mkdir -p "$HOME/.config/nvim"
	fi
}

function setup {
	echo "Starting setup..."

	# Authenticate
	sudo -v

	if [[ "$SHELL" != "/bin/bash" ]]; then
		# Change default shell
		echo "Changing shell to bash..."
		chsh -s /bin/bash
	fi

	if [[ "$OSTYPE" == "linux-gnu"* ]]; then
		setup_linux
		echo "Setup for Linux completed!"
	elif [[ "$OSTYPE" == "darwin"* ]]; then
		setup_macos
		echo "Setup for macOS completed!"
	else
		echo "OS not supported, exiting."
		exit 1
	fi
}

setup
