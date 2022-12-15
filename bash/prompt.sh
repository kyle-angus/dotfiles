#!/bin/bash

function prompt_command {
  EXIT_CODE=$?

  # Setup some local variables for colors
  local red='\[\e[1;31m\]'
  local green='\[\e[1;32m\]'
  local blue='\[\e[1;34m\]'
  local yellow='\[\e[1;33m\]'
  local brown='\[\e[33m\]'
  local cyan='\[\e[1;36m\]'
  local purple='\[\e[1;35m\]'
  local white='\[\e[00m\]'
  local black='\[\e[30m\]'
  local blink=$'\033[5m'


  # Determine the exit status of the last command
  local exit_status=""
  if [[ $EXIT_CODE == 0 ]]; then
    exit_status="${yellow}†"
  else
    exit_status="${red}†"
  fi

  # Setup host
  local host="${white}@${yellow}$HOSTNAME"

  # Setup current path
  local dir="$(basename $PWD)"
  if test "${PWD}" = "$HOME"; then
    dir="~"
  fi

  # Setup current git information
  local branch=" ($(git branch --show-current 2>/dev/null))"
  test "${branch}" = " ()" && branch=""
  local git_status=$(git status 2>/dev/null)
  test "${dir}" = "${branch}" && branch='(.)'
  if [[ ! $git_status =~ "working tree clean" ]]; then
    git_status="${red}"
  elif [[ $git_status =~ "Your branch is ahead of" ]]; then
    git_status="${yellow}"
  elif [[ $git_status =~ "nothing to commit" ]]; then
    git_status="${green}"
  else
    git_status="${cyan}"
  fi
  
  PS1="${exit_status} ${blue}\u${purple}${host} ${white}${dir}${git_status}${branch}${white} "
}

PROMPT_COMMAND=prompt_command
