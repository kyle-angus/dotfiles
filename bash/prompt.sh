#!/bin/bash

function prompt_command {

  local red='\[\e[1;31m\]'
  local green='\[\e[1;32m\]'
  local blue='\[\e[1;34m\]'
  local yellow='\[\e[1;33m\]'
  local brown='\[\e[1;33m\]'
  local cyan='\[\e[1;36m\]'
  local purple='\[\e[1;35m\]'
  local white='\[\e[00m\]'
  local black='\[\e[30m\]'
  local blink=$'\033[5m'

  local exit_status=""
  if [[ $? == 0 ]]; then
    exit_status="${yellow}†"
  else
    exit_status="${red}†"
  fi

  local host="${purple}@${brown}$HOSTNAME"

  local dir="$(basename $PWD)"
  if test "${PWD}" = "$HOME"; then
    dir="~"
  fi

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
  
  PS1="${exit_status} ${cyan}\u${purple}${host} ${white}${dir}${git_status}${branch}${white} "
}

PROMPT_COMMAND=prompt_command
