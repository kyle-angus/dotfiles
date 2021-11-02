#!/bin/bash

# Fail on a single command in a pipeline
set -o pipefail

# Exit if there's an error (e) or if an undefined (u) variable is used 
set -eu

# Save global script args
ARGS=("$@")

function setup_macos {
  echo "Starting setp for macOS"
  
  # Install Homebrew
  yes | /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Install the latest Git
  brew install git

  # Install NodeJS + NPM
  brew install node

  # Install Tmux
  brew install tmux

  brew install coreutils

  # TODO: Add steps for installing docker
}

function setup_linux {
  echo "Starting setup for linux..."

  install_node
  get_dotfiles
  create_links
  setup_gpg

  sudo apt-get install lynx -y
}

function setup_gpg {
  
  #sudo apt-get install pcscd scdaemon gnupg2 pcsc-tools -y
  
  # Setup the .gnp-agent.conf in $HOME/.gnupg/ to include enable-ssh-support 
  if [ ! -f "$HOME/.gnupg/gpg-agent.conf" ]; then
    echo "gpg-agent.conf doesn't exist"
  elif [ -z $(grep "enable-ssh-auth" "$HOME/.gnupg/gpg-agent.conf") ]; then
    echo "gpg-agent.conf already configured"
  else
    echo "adding enable-ssh-auth to gpg-agent.conf"
  fi
}

function install_node {
  # Install NVM
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash

  # Source our profile again so we can run nvm
  . $HOME/.bashrc

  # Install the latest LTS version of NodeJS
  nvm install --lts

  #TODO: Setup npm prefix for macOS (and maybe linux)
}

function get_dotfiles {
  # Clone dotfiles
  git clone https://github.com/kyle-angus/dotfiles.git $HOME/dotfiles
}

function setup_tmux {

  # Setup TPM / Tmux
  git clone https://github.com/tmux-plugins/tpm $HOME/.tmux/plugins/tpm
  echo "Prefix+I to install plugins if you're in TMUX already"

}

function create_links {
  ln -sf "$HOME/dotfiles/bash/aliases" "$HOME/.aliases"
  ln -sf "$HOME/dotfiles/bash/bashrc" "$HOME/.bashrc"
  ln -sf "$HOME/dotfiles/bash/bashrc" "$HOME/.bash_profile"
  ln -sf "$HOME/dotfiles/bash/profile" "$HOME/.profile"
  #ln -sf "$HOME/dotfiles/git/gitconfig" "$HOME/.gitconfig"
  ln -sf "$HOME/dotfiles/npm/npmrc" "$HOME/.npmrc"
  ln -sf "$HOME/dotfiles/vim/vimrc" "$HOME/.vimrc"
  ln -sf "$HOME/dotfiles/zsh/zshenv" "$HOME/.zshenv"
  ln -sf "$HOME/dotfiles/tmux/tmux.conf" "$HOME/.tmux.conf"
  ln -sf "$HOME/dotfiles/scripts" "$HOME/.scripts"
  ln -sf "$HOME/dotfiles/term/xprofile" "$HOME/.xprofile"
  ln -sf "$HOME/dotfiles/term/Xresources" "$HOME/.Xresources"
}

function setup {
  # Authenticate
  sudo -v

  # Change default shell
  chsh -s /bin/bash
  
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    setup_linux
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    setup_macos
  else
    echo "OS not supported, exiting."
    exit 1
  fi
}

setup_linux