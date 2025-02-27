#!/usr/bin/bash

# PS1 \ variables documentation:
# https://man7.org/linux/man-pages/man1/bash.1.html#PROMPTING

# Shell Parameter Expansion documentation:
# https://www.gnu.org/software/bash/manual/html_node/Shell-Parameter-Expansion.html

COLOR_0='\[\033[0m\]'
COLOR_GREY='\[\033[1;90m\]'

_trap_DEBUG() {
    # save current $SECONDS value
    _PREV_SECONDS=${_PREV_SECONDS:-$SECONDS}
}
trap _trap_DEBUG DEBUG # execute before every command

# PS0: expanded and displayed after reading a command but before the command is executed
PS0="$COLOR_GREY└ \D{%I:%M:%S %P}$COLOR_0\n"

# trick to not print anything if \j resolves to 0 in PS1
# using bash parameter substitution
_BASHGIT_NJOBS0=''

BASHGIT_UPDATE_PS1() {
    local prev_duration=$(($SECONDS - $_PREV_SECONDS))
    unset _PREV_SECONDS

    PS1="$COLOR_GREY┌$COLOR_0 "

    # previous command duration
    if (( prev_duration > 1 )); then
        PS1="\n$COLOR_GREY$prev_duration s$COLOR_0\n$PS1"
    fi

    # number of background processes
    PS1+='${_BASHGIT_NJOBS\j-\[\033[33m\][\j]\[\033[0m\] }'

    # git
    unset BASHGIT_{GIT,SUPER,HASH,BRANCH,ORIGIN,ORIGIN_SHORT}
    BASHGIT_REPO="$PWD"
    while [ -n "$BASHGIT_REPO" ]; do # look for .git
        BASHGIT_GIT="$BASHGIT_REPO/.git"
        if [ -d "$BASHGIT_GIT" ]; then # if .git is a directory
            break
        elif [ -f "$BASHGIT_GIT" ]; then # if .git is a file
            # this is a submodule
            local re_gitdir='^gitdir:[[:space:]]*((.*)/\.git.*)'
            if [[ "$(< "$BASHGIT_GIT")" =~ $re_gitdir ]]; then
                BASHGIT_GIT="$BASHGIT_REPO/${BASH_REMATCH[1]}"
                BASHGIT_SUPER="$BASHGIT_REPO/${BASH_REMATCH[2]}"
            else
                unset BASHGIT_{REPO,GIT}
            fi
            break
        fi
        BASHGIT_REPO=${BASHGIT_REPO%/*} # go one directory level deeper
    done

    if [ -z "$BASHGIT_REPO" ]; then
        unset BASHGIT_{REPO,GIT}
    else # this is a git repo
        # head hash and branch
        BASHGIT_HASH="$(< "$BASHGIT_GIT/HEAD")"
        local re_ref='^ref:[[:space:]]*(refs/heads/(.+))'
        if [[ "$BASHGIT_HASH" =~ $re_ref ]]; then
            BASHGIT_BRANCH="${BASH_REMATCH[2]}"
            local ref="$BASHGIT_GIT/${BASH_REMATCH[1]}"
            if [ -f "$ref" ]; then
                BASHGIT_HASH="$(< "$ref")"
            else
                BASHGIT_HASH=''
            fi
        fi

        # add short hash to PS1
        if [ -n "$BASHGIT_HASH" ]; then
            local color='31'
            local commit="${BASHGIT_HASH:0:7}"
            if [ -n "$BASHGIT_BRANCH" ]; then
                color='32'
                commit+=" $BASHGIT_BRANCH"
            fi
            PS1+="\[\033[${color}m\]$commit$COLOR_0 "
        fi

        # indicate if currently in a submodule
        # [ -v BASHGIT_SUPER ] && PS1+="\[\033[33m\]sub$COLOR_0 "

        # get git origin remote name
        # git config --get remote.origin.url
        local re_origin='^\[remote "origin"\]'
        local re_url='^[[:space:]]*url[[:space:]]*=[[:space:]]*(.+)'
        local line
        while IFS=$'\n' read -r line; do
            if [ -v re_origin ]; then
                [[ "$line" =~ $re_origin ]] && unset re_origin
            elif [[ "$line" =~ $re_url ]]; then
                BASHGIT_ORIGIN="${BASH_REMATCH[1]}"
                if [[ "$BASHGIT_ORIGIN" =~ (([^/]+/)?[^/]+)\.git$ ]]; then
                    BASHGIT_ORIGIN_SHORT="${BASH_REMATCH[1]}"
                    PS1+="\[\033[35m\]$BASHGIT_ORIGIN_SHORT$COLOR_0 "
                fi
                break
            fi
        done < "$BASHGIT_GIT/config"
    fi

    # current directory
    local cwd="$PWD"
    [[ "$cwd" =~ ^"$HOME"(/|$) ]] && cwd="~${cwd#$HOME}"
    # grey slashes
    PS1+="${cwd//\//$COLOR_GREY/$COLOR_0}"

    # prompt
    # count how many child processes we are from the original bash process
    local pid=$$
    local prompt_symbol='├'
    while [ "$pid" != '1' ]; do
        prompt_symbol+='\$'
        pid="$(< "/proc/$pid/ppid")"
    done
    PS1+="\n$COLOR_GREY$prompt_symbol$COLOR_0 "

    # set terminal window title
    PS1="\[\033]0;${BASHGIT_ORIGIN_SHORT:-Git Bash}\007\]$PS1"
}

PROMPT_COMMAND=BASHGIT_UPDATE_PS1

sm() { # navigate git submodules with fzf
    [ -z "$BASHGIT_REPO" ] && return 1

    local repo="${BASHGIT_SUPER:-$BASHGIT_REPO}"
    local modules="$repo/.gitmodules"
    [ -f "$modules" ] || return 1

    # TODO: go into submodules of submodules

    # TODO: rewrite awk script in bash
    modules="$(awk '
        match($0, /^\[submodule\s+"([^"]+)"/, m) {
            if (NR>1) { printf "\n" }
            printf "%s", m[1];
            next
        }
        match($0, /^\s*path\s*=\s*(.*)/, m) {
            printf " %s", m[1];
            next
        }
        END {
            printf "\n"
        }' "$modules" | sort | fzf -i -q "$1")"

    [ -n "$modules" ] && cd "$repo/${modules##* }"
}

topic() {
    [ $# -gt 1 ] || [ -z "$BASHGIT_REPO" ] && return 1

    local line path branch
    local branch="$BASHGIT_BRANCH"
    if [ -z "$branch" ]; then
        # HEAD does not point to a branch
        [ -z "$BASHGIT_SUPER" ] && return 1 # no super repo

        # Get branch name from .gitmodules
        while IFS=$'\n' read -r line; do
            if [[ "$line" =~ ^\[submodule[[:space:]] ]]; then
                if [ -n "$path" ] && [ "$BASHGIT_SUPER/$path" -ef "$BASHGIT_REPO" ]; then
                    unset path
                    break
                else
                    unset path branch
                fi
            elif [[ "$line" =~ ^[[:space:]]*(path|branch)[[:space:]]*=[[:space:]]*(.+) ]]; then
                declare "${BASH_REMATCH[1]}=${BASH_REMATCH[2]}"
            fi
        done < "$BASHGIT_SUPER/.gitmodules"
        if ! [ -n "$path" ] && [ "$BASHGIT_SUPER/$path" -ef "$BASHGIT_REPO" ]; then
            unset branch
        fi
        unset path
    fi

    if [[ "$branch" =~ ^topic/(.+)/.+ ]]; then
        branch="${BASH_REMATCH[1]}"
    fi

    if [ $# -eq 1 ]; then
        git switch -c "topic/$branch/$1"
    else
        echo "git switch -c topic/$branch/"
    fi
}
