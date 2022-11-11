#!/bin/bash

# Fail on a single command in a pipeline
set -o pipefail

# Exit if there's an error (e) or if an undefined (u) variable is used 
set -eu

function setup_macos {
  echo "Starting setup for macOS"
  
  # Install Homebrew
  if ! command -v brew &>/dev/null; then
    yes | /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  # Install the latest Git
  brew install git

  # Install NodeJS + NPM
  brew install node

  # Install Tmux
  brew install tmux

  brew install coreutils

  brew install fzf

  # TODO: Add steps for installing docker
  get_dotfiles
  create_links

  setup_tmux
  install_node

}

function setup_linux {
  echo "Starting setup for linux..."
  # Assume we're using debian...
  sudo apt update &>/dev/null
  sudo apt-get upgrade -y &>/dev/null
  sudo apt install vim tmux lynx build-essential -y &>/dev/null
  
  get_dotfiles
  create_links
  setup_gpg
  setup_tmux
  setup_ssh

  if ! command -v nvm; then
    install_node
  fi

}

function setup_gpg {
  echo "Setting up gpg..."
  
  sudo apt-get install pcscd scdaemon gnupg2 pcsc-tools -y &>/dev/null
  
  # Setup the .gnp-agent.conf in $HOME/.gnupg/ to include enable-ssh-support 
  if [ ! -f "$HOME/.gnupg/gpg-agent.conf" ]; then
    mkdir "$HOME/.gnupg"
    touch "$HOME/.gnupg/gpg-agent.conf"
    echo "enable-ssh-support" > "$HOME/.gnupg/gpg-agent.conf"
  elif grep -q "enable-ssh-support" < "$HOME/.gnupg/gpg-agent.conf"
  then
    echo "gpg-agent.conf already configured"
  else
    echo "enable-ssh-support" > "$HOME/.gnupg/gpg-agent.conf"
  fi
}

function install_node {
  # Install NVM
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash &>/dev/null

  # Source our profile again so we can run nvm
  source "$HOME/.bashrc"

  # Install the latest LTS version of NodeJS
  nvm install --lts &>/dev/null

  #TODO: Setup npm prefix for macOS (and maybe linux)
}

function get_dotfiles {
    echo "Pulling latest dotfiles..."
  if [ ! -d "$HOME/dotfiles" ]; then
    git clone https://github.com/kyle-angus/dotfiles.git "$HOME/dotfiles" &>/dev/null
    git remote set-url origin git@github.com:kyle-angus/dotfiles.git
  else
    previousDir=$(pwd)
    cd "$HOME/dotfiles"
    git pull &>/dev/null
    cd "$previousDir"
  fi
}

function setup_tmux {
  echo "Setting up tmux..."
  # Setup TPM / Tmux
  mkdir -p "$HOME/.tmux/plugins"
  git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm" &>/dev/null
  echo "Prefix+I to install plugins if you're in TMUX already"

}

function setup_ssh {
  echo "Setting up ssh..."

  if [ ! -d "$HOME/.ssh" ]; then
    mkdir "$HOME/.ssh";
    chmod 700 "$HOME/.ssh"
  fi

  # TODO: Setup keybase to automatically pull down keys
}

function create_links {
  echo "Creating symlinks..."
  DOTFILES="$HOME/dotfiles"

  ln -sf "$DOTFILES/bash/aliases" "$HOME/.aliases"
  ln -sf "$DOTFILES/bash/bashrc" "$HOME/.bashrc"
  ln -sf "$DOTFILES/bash/bashrc" "$HOME/.bash_profile"
  ln -sf "$DOTFILES/bash/profile" "$HOME/.profile"
  ln -sf "$DOTFILES/git/gitconfig" "$HOME/.gitconfig"
  ln -sf "$DOTFILES/git/gitignore" "$HOME/.gitignore"
  ln -sf "$DOTFILES/npm/npmrc" "$HOME/.npmrc"
  ln -sf "$DOTFILES/vim/vimrc" "$HOME/.vimrc"
  ln -sf "$DOTFILES/zsh/zshenv" "$HOME/.zshenv"
  ln -sf "$DOTFILES/tmux/tmux.conf" "$HOME/.tmux.conf"
  ln -sf "$DOTFILES/scripts" "$HOME/.scripts"
  ln -sf "$DOTFILES/term/xprofile" "$HOME/.xprofile"
  ln -sf "$DOTFILES/term/Xresources" "$HOME/.Xresources"
}

function setup {
  # Authenticate
  sudo -v

  if [[ "$SHELL" != "/bin/bash" ]]; then
    # Change default shell
    chsh -s /bin/bash
  fi

  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    setup_linux
    echo "Setup for Linux completed"
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    setup_macos
    echo "Setup for macOS completed"
  else
    echo "OS not supported, exiting."
    exit 1
  fi
}

setup
