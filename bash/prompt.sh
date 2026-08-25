#!/bin/bash

function prompt_command {
  local exit_code=$?

  # Setup some local variables for colors
  local red='\[\e[1;31m\]'
  local green='\[\e[1;32m\]'
  local blue='\[\e[1;34m\]'
  local yellow='\[\e[1;33m\]'
  local purple='\[\e[1;35m\]'
  local white='\[\e[00m\]'

  # Determine the exit status of the last command
  local exit_status=""
  if [[ $exit_code == 0 ]]; then
    exit_status="${yellow}†"
  else
    exit_status="${red}†"
  fi

  # Setup host
  local host="${white}@${yellow}$HOSTNAME"

  # Setup current path. Parameter expansion instead of `basename $PWD`, which
  # word-splits on directories containing whitespace and then makes basename
  # print one line per word.
  local dir="${PWD##*/}"
  if [[ $PWD == "$HOME" ]]; then
    dir="~"
  elif [[ -z $dir ]]; then
    dir="/" # $PWD is the filesystem root
  fi

  # Setup current git information. `git status --porcelain -b` reports the
  # branch and the dirty state in a single call, and its output is stable
  # across locales -- unlike the human-readable `git status` this used to grep.
  #
  # --no-optional-locks stops git refreshing the on-disk index as a side
  # effect. This runs before *every* prompt, and on Windows those writes are
  # both slow and prone to colliding with an editor or a background fetch
  # holding index.lock.
  local branch=""
  local git_color="${white}"
  local git_state
  git_state=$(git --no-optional-locks status --porcelain=v1 -b 2>/dev/null)

  if [[ -n $git_state ]]; then
    # First line is the branch header, e.g. "## main...origin/main [ahead 1]"
    local head_line="${git_state%%$'\n'*}"
    head_line="${head_line#\#\# }"

    local branch_name="${head_line%%...*}" # drop the upstream, if any
    branch_name="${branch_name%% *}"       # drop "[ahead N]" when no upstream

    if [[ $head_line == "HEAD (no branch)" ]]; then
      branch_name="detached"
    elif [[ $head_line == "No commits yet on "* ]]; then
      branch_name="${head_line#No commits yet on }"
    fi

    if [[ $git_state == *$'\n'* ]]; then
      git_color="${red}" # working tree is dirty
    elif [[ $head_line == *"[ahead "* || $head_line == *"[behind "* ]]; then
      git_color="${yellow}" # clean, but out of sync with the upstream
    else
      git_color="${green}" # clean and in sync
    fi

    # Collapse to "(.)" when the branch only repeats the directory name.
    if [[ $branch_name == "$dir" ]]; then
      branch=" (.)"
    else
      branch=" (${branch_name})"
    fi
  fi

  PS1="${exit_status} ${blue}\u${purple}${host} ${white}${dir}${git_color}${branch}${white} "
}

PROMPT_COMMAND=prompt_command
