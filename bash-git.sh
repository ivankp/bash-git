# PS1 and \ variables documentation:
# https://man7.org/linux/man-pages/man1/bash.1.html#PROMPTING

# Shell Parameter Expansion documentation:
# https://www.gnu.org/software/bash/manual/html_node/Shell-Parameter-Expansion.html

BASHGIT_COLOR_0='\[\033[0m\]'
BASHGIT_COLOR_MISC='\[\033[90m\]'
BASHGIT_COLOR_BRANCH='\[\033[32m\]'
BASHGIT_COLOR_NOBRANCH='\[\033[31m\]'
BASHGIT_COLOR_ORIGIN='\[\033[35m\]'

BASHGIT_HASH_LENGTH=7

BASHGIT_LOG_FORMAT='%C(auto)%h%Creset %s %Cblue(%an, %cd)%Creset%Cgreen%d%Creset'

declare -A BASHGIT_REMOTES=(
    ['github.com']='github'
)

_trap_DEBUG() {
    # save current $SECONDS value
    _PREV_SECONDS="${_PREV_SECONDS:-$SECONDS}"
}
trap _trap_DEBUG DEBUG # execute before every command

# PS0: expanded and displayed after reading a command but before the command is executed
BASHGIT_PS0="$BASHGIT_COLOR_MISC└ \D{%I:%M:%S %P}$BASHGIT_COLOR_0\n"

# trick to not print anything if \j resolves to 0 in PS1
# using bash parameter substitution
_BASHGIT_NJOBS0=''

_PATH_REMOVE_DOTS() {
    local -n _ref="$1"
    local right left
    # /a/b/../c -> /a/c
    while true; do
        right="${_ref#*/../}"
        [[ $right == $_ref ]] && break
        left="${_ref%%/../*}"
        left="${left%/*}"
        _ref="$left/$right"
    done
    # /a/b/c/.. -> /a/b
    left="${_ref%/..}"
    [[ $left != $_ref ]] && _ref="${left%/*}"
}

# Set the variable with the passed name to the clipboard text
_FROM_CLIP() {
    local -n _ref="$1"
    case "$OSTYPE" in
        msys | cygwin)
            _ref="$(< /dev/clipboard)"
            [[ $2 == path ]] && _ref="$(cygpath -u "$_ref")"
            ;;
        *)
            echo 'Not implemented' >&2
            return 1
            ;;
    esac
}

BASHGIT_RESOLVE_GIT() {
    local -n _git="$1"
    if [[ -f $_git ]]; then
        local re='^gitdir:[[:blank:]]*(.*[^[:space:]])'
        if [[ "$(< "$_git")" =~ $re ]]; then
            local gitdir="${BASH_REMATCH[1]}"
            if [[ $gitdir != /* ]]; then
                _git="$_git/../$gitdir"
                _PATH_REMOVE_DOTS _git
            else
                _git="$gitdir"
            fi
        fi
    elif [[ ! -d $_git ]]; then
        return 1
    fi
    return 0
}

# Recursively find all submodules and run the predicate command for each one
BASHGIT_MODULES() { # predicate repo_path
    "$1" "$2" # invoke the predicate
    if [[ -f "$2/.gitmodules" ]]; then
        local line re='^path[[:blank:]]*=[[:blank:]]*(.*[^[:space:]])'
        while read -r line || [[ -n $line ]]; do
            if [[ $line =~ $re ]]; then
                BASHGIT_MODULES "$1" "$2/${BASH_REMATCH[1]}"
            fi
        done < "$2/.gitmodules"
    fi
}

# Set REPO, SUPER, and GIT paths if we are in a git repo
BASHGIT_CHECK_REPO() {
    local path="${1:-$PWD}"
    # Inspect current path
    local re='^(.+)/.git(/.*)?$'
    if [[ $path =~ $re ]]; then
        BASHGIT_SUPER="${BASH_REMATCH[1]}"
        BASHGIT_REPO="$BASHGIT_SUPER"
        BASHGIT_GIT="$BASHGIT_REPO/.git"
        local right="${BASH_REMATCH[2]}"
        if [[ $right == /modules* ]]; then # inside .git/modules
            while [[ -n $right ]]; do # look for config file
                local config="$BASHGIT_GIT$right/config"
                if [[ -f $config ]]; then
                    # Read repo directory from config file
                    re='^worktree[[:blank:]]*=[[:blank:]]*(.*[^[:space:]])'
                    local line
                    while read -r line || [[ -n $line ]]; do
                        if [[ $line =~ $re ]]; then
                            path="${BASH_REMATCH[1]}"
                            [[ ${path:0:1} != / ]] && path="$BASHGIT_GIT$right/$path"
                            if [[ -d $path ]]; then
                                _PATH_REMOVE_DOTS path
                                BASHGIT_REPO="$path"
                                BASHGIT_GIT="$BASHGIT_GIT$right"
                                return 0
                            fi
                            break
                        fi
                    done < "$config"
                fi
                right="${right%/*}" # go one directory level up
            done
        fi
        return 0
    fi

    # Descend into parent directories one by one
    BASHGIT_REPO="$path"
    while [[ -n $BASHGIT_REPO ]]; do # look for .git
        BASHGIT_GIT="$BASHGIT_REPO/.git"
        if [[ -d $BASHGIT_GIT ]]; then # if .git is a directory
            BASHGIT_SUPER="$BASHGIT_REPO"
            return 0
        elif [[ -f $BASHGIT_GIT ]]; then # if .git is a file
            # this is a submodule
            re='^gitdir:[[:blank:]]*((.*)/\.git.*)'
            if [[ "$(< "$BASHGIT_GIT")" =~ $re ]]; then
                BASHGIT_GIT="${BASH_REMATCH[1]}"
                [[ $BASHGIT_GIT != /* ]] && BASHGIT_GIT="$BASHGIT_REPO/$BASHGIT_GIT"
                if [[ -d $BASHGIT_GIT ]]; then
                    # .git file points to a valid directory
                    BASHGIT_SUPER="$BASHGIT_REPO/${BASH_REMATCH[2]}"
                    _PATH_REMOVE_DOTS BASHGIT_SUPER
                    return 0
                fi
            fi
        fi
        BASHGIT_REPO="${BASHGIT_REPO%/*}" # go one directory level up
    done

    unset BASHGIT_{REPO,SUPER,GIT}
    return 1
}

BASHGIT_CHECK_PARENT() {
    unset BASHGIT_PARENT
    local re='(.*/\.git(/.+)?)/modules/.*[^[:space:]]' git="$BASHGIT_GIT"
    while [[ $git =~ $re ]]; do
        if [[ -z "${BASH_REMATCH[2]}" ]]; then
            BASHGIT_PARENT="${BASH_REMATCH[1]%/*}"
            return 0
        fi
        git="${BASH_REMATCH[1]}"

        if [[ -f "$git/config" ]]; then
            # Read repo directory from config file
            re='^worktree[[:blank:]]*=[[:blank:]]*(.*[^[:space:]])'
            local line
            while read -r line || [[ -n $line ]]; do
                if [[ $line =~ $re ]]; then
                    line="${BASH_REMATCH[1]}"
                    [[ ${line:0:1} != / ]] && line="$git/$line"
                    if [[ -d $line ]]; then
                        _PATH_REMOVE_DOTS line
                        BASHGIT_PARENT="$line"
                        return 0
                    fi
                    break 2
                fi
            done < "$git/config"
            break
        fi
    done
    return 1
}

# get git origin remote name
# git config --get remote.origin.url
BASHGIT_CHECK_ORIGIN() {
    unset BASHGIT_ORIGIN
    local git="${1:-$BASHGIT_GIT}"
    [[ -z $git ]] && return 1

    local re_origin='^\[remote[[:blank:]]+"origin"\]'
    local re_url='^[[:blank:]]*url[[:blank:]]*=[[:blank:]]*(.*[^[:space:]])'
    local line
    while read -r line || [[ -n $line ]]; do
        if [[ -n $re_origin ]]; then
            [[ $line =~ $re_origin ]] && re_origin=
        elif [[ $line =~ $re_url ]]; then
            BASHGIT_ORIGIN="${BASH_REMATCH[1]}"
            return 0
        fi
    done < "$git/config"

    return 1
}

BASHGIT_CHECK_COMMIT() {
    unset BASHGIT_{HASH,BRANCH}
    [[ -v BASHGIT_GIT ]] || return 1

    BASHGIT_HASH="$(< "$BASHGIT_GIT/HEAD")"
    local re_ref='^ref:[[:blank:]]*(refs/heads/(.+))'
    if [[ $BASHGIT_HASH =~ $re_ref ]]; then
        BASHGIT_BRANCH="${BASH_REMATCH[2]}"
        local ref="$BASHGIT_GIT/${BASH_REMATCH[1]}"
        if [[ -f $ref ]]; then
            BASHGIT_HASH="$(< "$ref")"
        else
            unset BASHGIT_{HASH,BRANCH}
            return 1
        fi
    fi
    return 0
}

BASHGIT_PROMPT_COMMAND() {
    local prev_duration=$((SECONDS - _PREV_SECONDS))
    unset _PREV_SECONDS

    PS1="$BASHGIT_COLOR_MISC┌$BASHGIT_COLOR_0 "

    # previous command duration
    if (( prev_duration > 1 )); then
        # seconds
        local t=$(( prev_duration % 60 ))
        local d="$t s"
        # minutes
        t=$(( (prev_duration % 3600) / 60 ))
        (( t > 0 )) && d="$t m $d"
        # hours
        t=$(( prev_duration / 3600 ))
        (( t > 0 )) && d="$t h $d"

        PS1="\n$BASHGIT_COLOR_MISC$d$BASHGIT_COLOR_0\n$PS1"
    fi

    # number of background processes
    PS1+='${_BASHGIT_NJOBS\j-\[\033[33m\][\j]\[\033[0m\] }'

    # python virtual environment
    [[ -n $VIRTUAL_ENV ]] && PS1+="🐍 "

    # git
    unset BASHGIT_{HASH,BRANCH,ORIGIN}
    local origin
    if BASHGIT_CHECK_REPO; then # this is a git repo
        if BASHGIT_CHECK_COMMIT; then # get head hash and branch
            # add short hash and branch name to PS1
            local color="$BASHGIT_COLOR_NOBRANCH"
            local commit="${BASHGIT_HASH:0:$BASHGIT_HASH_LENGTH}"
            if [[ -v BASHGIT_BRANCH ]]; then
                color="$BASHGIT_COLOR_BRANCH"
                commit+=" $BASHGIT_BRANCH"
            fi
            PS1+="$color$commit$BASHGIT_COLOR_0 "
        fi

        if BASHGIT_CHECK_ORIGIN; then
            local re_url='(([^/:]+/)?[^/]+)\.git$'
            if [[ $BASHGIT_ORIGIN =~ $re_url ]]; then
                origin="${BASH_REMATCH[1]}"
                PS1+="$BASHGIT_COLOR_ORIGIN$origin$BASHGIT_COLOR_0 "
            fi
        fi
    fi

    # current directory
    local cwd="$PWD"
    [[ $cwd =~ ^"$HOME"/? ]] && cwd="~${cwd#$HOME}"
    # color slashes
    PS1+="${cwd//\//$BASHGIT_COLOR_MISC/$BASHGIT_COLOR_0}"

    # prompt
    # add $ for each shell level
    local prompt_symbol='├\$'
    local l="${SHLVL:-1}"
    for ((; l > 1; --l)); do
        prompt_symbol+='\$'
    done
    PS1+="\n$BASHGIT_COLOR_MISC$prompt_symbol$BASHGIT_COLOR_0 "

    # set terminal window title
    PS1="\[\033]0;${origin:-bash}\007\]$PS1"
}

repo() {
    BASHGIT_CHECK_REPO && cd "$BASHGIT_REPO"
}

super() {
    BASHGIT_CHECK_REPO && cd "$BASHGIT_SUPER"
}

BASHGIT_LIST_HEADS_R() {
    local f
    for f in "$2"/*; do
        if [[ -d $f ]]; then
            BASHGIT_LIST_HEADS_R "$1" "$f"
        else
            full+=("${f#"$heads/"} $1")
            names[${f##*/}]=1
        fi
    done
}

BASHGIT_LIST_HEADS() {
    local git="$1/.git"
    if BASHGIT_RESOLVE_GIT git; then
        local heads="$git/refs/heads"
        BASHGIT_LIST_HEADS_R "$1" "$heads"
    fi
}

_sm_options='bopruxh'
sm() { # navigate git submodules
    local -A opts
    local OPTIND=1 OPTARG OPTERR opt
    while getopts ":$_sm_options" opt; do
        case "$opt" in
            h) break ;;
            \?) opt=h; echo "unexpected option -$OPTARG" >&2; break ;;
            *) opts[$opt]=1 ;;
        esac
    done

    if [[ $opt == h || "${opts[b]}${opts[r]}${opts[u]}" > 1 ]]; then
        [[ $opt != h ]] && echo "conflicting options specified: ${!opts[@]}" >&2
        echo 'usage: sm [option...] [argument...]
options:
  -b: list local branches in all submodules
  -b [name...]: list submodules and branches matching the names

  -u: update all submodules
  -u [submodule...]: update specified submodules

  -r [command...]: run command for every submodule

  -x: start at the current repo instead of the super repo

  -o: include origin in the list of submodules
  -p: print the list of submodules (i.e. do not pipe to fzf)

  -h: print this help message and exit'
        return 1
    fi

    shift $((OPTIND - 1))

    BASHGIT_CHECK_REPO || return 1

    local repo
    [[ -v opts[x] ]] && repo="$BASHGIT_REPO" || repo="$BASHGIT_SUPER"

    if [[ -v opts[u] ]]; then # update submodules
        local cmd=(git submodule update --init)
        local arg rec=1
        for arg in "$@"; do
            if [[ $arg != -* ]]; then
                rec=
                break
            fi
        done
        [[ -n $rec ]] && cmd+=(--recursive)
        cmd+=("$@")
        (cd "$repo"; echo "$PWD"; echo "${cmd[@]}"; "${cmd[@]}")
        return
    fi

    if [[ -v opts[b] ]]; then # branches
        local -a full
        local -A names

        local nullglob
        if ! shopt -q nullglob; then
            nullglob=1
            shopt -s nullglob
        fi

        BASHGIT_MODULES BASHGIT_LIST_HEADS "$repo"

        [[ -n $nullglob ]] && shopt -u nullglob

        local x
        if (( $# == 0 )); then
            # If no arguments, print list of branch suffixes
            for x in "${!names[@]}"; do
                echo "$x"
            done
        else
            # For each argument, print all matching branches and modules
            local re
            for x in "$@"; do
                re="^([^[:blank:]]*/)?$x (.*)"
                for x in "${full[@]}"; do
                    if [[ $x =~ $re ]]; then
                        echo "$x"
                    fi
                done
            done
        fi
        return
    fi

    if [[ -v opts[r] ]]; then # run a command for each submodules
        local -a cmd
        (( $# == 0 )) && cmd=(echo) || cmd=("$@")
        sm_predicate() { "${cmd[@]}" "$1"; }
        BASHGIT_MODULES sm_predicate "$repo"
        return
    fi

    # default behavior: select a submodule

    local sm_modules=()
    local re_origin='(([^/:]+/)?[^/]+)\.git$'
    if [[ -v opts[o] ]]; then
        sm_predicate() {
            local git="$1/.git"
            if BASHGIT_RESOLVE_GIT git && BASHGIT_CHECK_ORIGIN "$git"; then
                if [[ $BASHGIT_ORIGIN =~ $re_origin ]]; then
                    sm_modules+=("${BASH_REMATCH[1]} $1")
                fi
            fi
        }
    else
        sm_predicate() {
            sm_modules+=("$1")
        }
    fi
    BASHGIT_MODULES sm_predicate "$repo"

    if [[ ! -v opts[p] ]] && command -v fzf &> /dev/null; then
        local x="$(printf '%s\n' "${sm_modules[@]}" | fzf -i -q "$1")"
        if [[ -n $x ]]; then
            [[ -v opts[o] ]] && x="${x#* }" # cut off origin prefix
            cd "$x"
        fi
    else
        printf '%s\n' "${sm_modules[@]}"
    fi
}

# $1: command name
# $2: current word
# $3: preceding word
_complete_sm() {
    if [[ $2 == -* ]]; then
        local c opts
        while IFS=':' read -r -n1 c; do
            [[ -n $c ]] && opts+="-$c "
        done <<< "$_sm_options"
        COMPREPLY=($(compgen -W "$opts" -- "$2"))
    else
        local -A opts
        local OPTIND=1 OPTARG OPTERR opt
        while getopts ":$_sm_options" opt "${COMP_WORDS[@]:1}"; do
            opts[$opt]=1
        done

        [[ "${opts[b]}${opts[r]}${opts[u]}" > 1 ]] && return 1

        if [[ -v opts[b] ]]; then
            COMPREPLY=($(compgen -W "$(sm -b ${opts[x]:+-x})" -- "$2"))
        elif [[ -v opts[u] ]]; then
            # TODO
            :
        fi
    fi
}
complete -F _complete_sm sm

remote() { # print link to the origin remote's online interface
    local path="$1" ref="$2" dir
    if [[ $1 != - && ( $2 == - || ( -n $1 && ! -e $1 )) ]]; then
        ref="$1"
        path="$2"
    fi
    if [[ $path == - ]]; then
        _FROM_CLIP path path || return 1
    fi
    if [[ -n $path ]]; then
        if [[ -d $path ]]; then
            dir="$path"
        elif [[ -f $path ]]; then
            dir="${path%/*}"
        else
            echo 'usage: remote [path] [git_ref]' >&2
            return 1
        fi
        # convert to absolute path
        [[ $dir != /* ]] && dir="$PWD/$path"
    fi

    BASHGIT_CHECK_REPO "$dir" && BASHGIT_CHECK_ORIGIN || return 1

    local re_http='^https?://([^/]+)/(.*/)?([^/]+)/([^/]+)\.git'
    local re_ssh='^(ssh://)?([^@/:]+@)?([^/:]+)(:|(:[0-9]+)?/)(.*/)?([^/]+)/([^/]+)\.git'

    local -a m
    local i
    if [[ $BASHGIT_ORIGIN =~ $re_http ]]; then
        for i in 1 2 3 4; do
            m+=("${BASH_REMATCH[$i]}")
        done
    elif [[ $BASHGIT_ORIGIN =~ $re_ssh ]]; then
        for i in 3 6 7 8; do
            m+=("${BASH_REMATCH[$i]}")
        done
    else
        echo "\"$BASHGIT_ORIGIN\" did not match a url pattern" >&2
        return 1
    fi

    if [[ -n $ref ]]; then
        BASHGIT_HASH="$(git rev-parse "$ref")"
        [[ $? != 0 ]] && return 1
    else
        BASHGIT_CHECK_COMMIT
    fi

    local relpath
    if [[ -n $path ]]; then
        # TODO: use _PATH_REMOVE_DOTS, implement /./ removal
        relpath="$(realpath --relative-to="$BASHGIT_REPO" "$path")"
        [[ $relpath == . ]] && relpath=
        # path is inside the repo by construction
        # path determines where the repo is found
    fi

    local url
    case "${BASHGIT_REMOTES[${m[0]}]}" in
        github)
            url="https://${m[0]}/${m[1]}${m[2]}/${m[3]}"
            if [[ -v BASHGIT_HASH ]]; then
                if [[ -n $relpath ]]; then
                    url+="/blob/$BASHGIT_HASH/$relpath"
                else
                    url+="/tree/$BASHGIT_HASH"
                fi
            fi
            echo "$url"
            ;;
        bitbucket)
            url="https://${m[0]}/${m[1]}"
            if [[ ${m[2]:0:1} == ~ ]]; then
                url+="users/${m[2]:1}"
            else
                url+="projects/${m[2]}"
            fi
            url+="/repos/${m[3]}/browse"
            [[ -n $relpath ]] && url+="/$relpath"
            [[ -v BASHGIT_HASH ]] && url+="?at=$BASHGIT_HASH"
            echo "$url"
            ;;
        gitlab)
            url="https://${m[0]}/${m[1]}${m[2]}/${m[3]}"
            [[ -v BASHGIT_HASH ]] && url+="/-/blob/$BASHGIT_HASH"
            [[ -n $relpath ]] && url+="/$relpath"
            echo "$url"
            ;;
        *)
            echo "Unexpected origin host type \"${BASHGIT_REMOTES[${m[0]}]}\"" \
                 "for host \"${m[0]}\"" >&2
            return 1
            ;;
    esac
}

topic() {
    (( $# < 2 )) && BASHGIT_CHECK_REPO || return 1

    local branch="$BASHGIT_BRANCH"
    if [[ -z $branch ]]; then # HEAD does not point to a branch
        BASHGIT_CHECK_PARENT && [[ -f "$BASHGIT_PARENT/.gitmodules" ]] || return 1

        # Get branch name from .gitmodules
        branch=
        local line last path s
        local re_submodule='^\[submodule[[:blank:]]'
        local re_value='^(path|branch)[[:blank:]]*=[[:blank:]]*(.*[^[:space:]])'

        while read -r line || last=1; do
            if [[ -n $s && $line =~ $re_value ]]; then
                declare "${BASH_REMATCH[1]}=${BASH_REMATCH[2]}"
            fi
            if [[ -n $last || $line == '['* ]]; then
                if [[ -n $path && $BASHGIT_PARENT/$path -ef $BASHGIT_REPO ]]; then
                    break
                else
                    path=
                    branch=
                fi
                [[ $line =~ $re_submodule ]] && s=1 || s=
            fi
            [[ -n $last ]] && break
        done < "$BASHGIT_PARENT/.gitmodules"

        [[ -z $branch ]] && return 1
    fi

    [[ $branch =~ ^topic/(.+)/.+ ]] && branch="${BASH_REMATCH[1]}"

    if (( $# == 1 )); then
        git switch -c "topic/$branch/$1"
    else
        echo "git switch -c topic/$branch/"
    fi
}

gl() {
    local OPTIND=1 OPTARG OPTERR opt n=8
    while getopts ':cn:' opt; do
        case "$opt" in
            c) echo "$(git rev-list --count HEAD) commits" ;;
            n) n="${OPTARG}" ;;
        esac
    done
    shift $((OPTIND - 1))

    git log -n"$n" --date=relative --format="$BASHGIT_LOG_FORMAT" "$@"
}

amend() {
    local OPTIND=1 OPTARG OPTERR opt edit push args=()
    while getopts ':aedph' opt; do
        case "$opt" in
            a) args+=('--all') ;;
            e) edit=1 ;;
            d) args+=('--date=now') ;;
            p) push=1 ;;
            h) echo 'usage: amend [option...]
options:
  -a: `commit --all`
  -e: no `commit --no-edit`
  -d: `commit --date=now`
  -p: `git push --force-with-lease`
  -h: print this help message and exit'; return 0 ;;
        esac
    done
    shift $((OPTIND - 1))

    [[ -z $edit ]] && args+=('--no-edit')

    git commit --amend "${args[@]}" "$@" && [[ -n $push ]] && git push --force-with-lease
}
