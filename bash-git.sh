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

BASHGIT_GL_FORMAT='%C(auto)%h%Creset %s %Cblue(%an, %cd)%Creset%Cgreen%d%Creset'

_trap_DEBUG() {
    # save current $SECONDS value
    _PREV_SECONDS=${_PREV_SECONDS:-$SECONDS}
}
trap _trap_DEBUG DEBUG # execute before every command

# PS0: expanded and displayed after reading a command but before the command is executed
BASHGIT_PS0="$BASHGIT_COLOR_MISC└ \D{%I:%M:%S %P}$BASHGIT_COLOR_0\n"

# trick to not print anything if \j resolves to 0 in PS1
# using bash parameter substitution
_BASHGIT_NJOBS0=''

_PATH_REMOVE_DOTS() {
    local -n ref="$1"
    local right left
    # /a/b/../c -> /a/c
    while true; do
        right="${ref#*/../}"
        [ "$right" == "$ref" ] && break
        left="${ref%%/../*}"
        left="${left%/*}"
        ref="$left/$right"
    done
    # /a/b/c/.. -> /a/b
    left="${ref%/..}"
    [ "$left" != "$ref" ] && ref="${left%/*}"
}

# Set REPO, SUPER, and GIT paths if we are in a git repo
BASHGIT_CHECK_REPO() {
    # Inspect current path
    local re='^(.+)/.git(/.*)?$'
    if [[ "$PWD" =~ $re ]]; then
        BASHGIT_REPO="${BASH_REMATCH[1]}"
        BASHGIT_SUPER="$BASHGIT_REPO"
        BASHGIT_GIT="$BASHGIT_REPO/.git"
        local right="${BASH_REMATCH[2]}"
        if [[ "$right" == /modules* ]]; then # inside .git/modules
            while [ -n "$right" ]; do # look for config file
                local config="$BASHGIT_GIT$right/config"
                if [ -f "$config" ]; then
                    # Read repo directory from config file
                    re='^[[:blank:]]*worktree[[:blank:]]*=[[:blank:]]*(.*[^[:blank:]])'
                    local line
                    while IFS=$'\n' read -r line || [[ -n "$line" ]]; do
                        if [[ "$line" =~ $re ]]; then
                            local path="${BASH_REMATCH[1]}"
                            [[ "$path" != /* ]] && path="$BASHGIT_GIT$right/$path"
                            if [ -d "$path" ]; then
                                _PATH_REMOVE_DOTS path
                                BASHGIT_REPO="$path"
                                BASHGIT_GIT="$BASHGIT_GIT$right"
                                return
                            fi
                            break
                        fi
                    done < "$config"
                fi
                right=${right%/*} # go one directory level up
            done
        fi
        return
    fi

    # Descend into parent directories one by one
    BASHGIT_REPO="$PWD"
    while [ -n "$BASHGIT_REPO" ]; do # look for .git
        BASHGIT_GIT="$BASHGIT_REPO/.git"
        if [ -d "$BASHGIT_GIT" ]; then # if .git is a directory
            BASHGIT_SUPER="$BASHGIT_REPO"
            return
        elif [ -f "$BASHGIT_GIT" ]; then # if .git is a file
            # this is a submodule
            re='^gitdir:[[:blank:]]*((.*)/\.git.*)'
            if [[ "$(< "$BASHGIT_GIT")" =~ $re ]]; then
                BASHGIT_GIT="${BASH_REMATCH[1]}"
                [[ "$BASHGIT_GIT" != /* ]] && BASHGIT_GIT="$BASHGIT_REPO/$BASHGIT_GIT"
                if [ -d "$BASHGIT_GIT" ]; then
                    # .git file points to a valid directory
                    BASHGIT_SUPER="$BASHGIT_REPO/${BASH_REMATCH[2]}"
                    return
                fi
            fi
        fi
        BASHGIT_REPO=${BASHGIT_REPO%/*} # go one directory level up
    done

    unset BASHGIT_{REPO,SUPER,GIT}
    return 1
}

# get git origin remote name
# git config --get remote.origin.url
BASHGIT_CHECK_ORIGIN() {
    unset BASHGIT_ORIGIN
    [ -v BASHGIT_GIT ] || return 1

    local re_origin='^\[remote[[:blank:]]+"origin"\]'
    local re_url='^[[:blank:]]*url[[:blank:]]*=[[:blank:]]*(.*[^[:blank:]])'
    local line
    while IFS=$'\n' read -r line || [[ -n "$line" ]]; do
        if [ -v re_origin ]; then
            [[ "$line" =~ $re_origin ]] && unset re_origin
        elif [[ "$line" =~ $re_url ]]; then
            BASHGIT_ORIGIN="${BASH_REMATCH[1]}"
            return
        fi
    done < "$BASHGIT_GIT/config"

    return 1
}

BASHGIT_CHECK_COMMIT() {
    unset BASHGIT_{HASH,BRANCH}
    [ -v BASHGIT_GIT ] || return 1

    BASHGIT_HASH="$(< "$BASHGIT_GIT/HEAD")"
    local re_ref='^ref:[[:blank:]]*(refs/heads/(.+))'
    if [[ "$BASHGIT_HASH" =~ $re_ref ]]; then
        BASHGIT_BRANCH="${BASH_REMATCH[2]}"
        local ref="$BASHGIT_GIT/${BASH_REMATCH[1]}"
        if [ -f "$ref" ]; then
            BASHGIT_HASH="$(< "$ref")"
        else
            unset BASHGIT_{HASH,BRANCH}
            return 1
        fi
    fi
}

BASHGIT_PROMPT_COMMAND() {
    local prev_duration=$(( SECONDS - _PREV_SECONDS ))
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
    [ -n "$VIRTUAL_ENV" ] && PS1+="🐍 "

    # git
    unset BASHGIT_{HASH,BRANCH,ORIGIN,ORIGIN_SHORT}
    if BASHGIT_CHECK_REPO; then # this is a git repo
        if BASHGIT_CHECK_COMMIT; then # get head hash and branch
            # add short hash and branch name to PS1
            local color="$BASHGIT_COLOR_NOBRANCH"
            local commit="${BASHGIT_HASH:0:$BASHGIT_HASH_LENGTH}"
            if [ -v BASHGIT_BRANCH ]; then
                color="$BASHGIT_COLOR_BRANCH"
                commit+=" $BASHGIT_BRANCH"
            fi
            PS1+="$color$commit$BASHGIT_COLOR_0 "
        fi

        if BASHGIT_CHECK_ORIGIN; then
            local re_url='(([^/]+/)?[^/]+)\.git$'
            if [[ "$BASHGIT_ORIGIN" =~ $re_url ]]; then
                BASHGIT_ORIGIN_SHORT="${BASH_REMATCH[1]}"
                PS1+="$BASHGIT_COLOR_ORIGIN$BASHGIT_ORIGIN_SHORT$BASHGIT_COLOR_0 "
            fi
        fi
    fi

    # current directory
    local cwd="$PWD"
    [[ "$cwd" =~ ^"$HOME"/? ]] && cwd="~${cwd#$HOME}"
    # grey slashes
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
    PS1="\[\033]0;${BASHGIT_ORIGIN_SHORT:-bash}\007\]$PS1"
}

repo() {
    BASHGIT_CHECK_REPO && cd "$BASHGIT_REPO"
}

super() {
    BASHGIT_CHECK_REPO && cd "$BASHGIT_SUPER"
}

gl() {
    local OPTIND opt n=8 fmt= date=
    while getopts ':cd:f:n:' opt; do
        case "$opt" in
            c) echo "$(git rev-list --count HEAD) commits" ;;
            n) n="${OPTARG}" ;;
            d) date="${OPTARG}" ;;
            f) fmt="${OPTARG}" ;;
        esac
    done
    shift "$(($OPTIND -1))"

    git log --date="${date:-relative}" --format="${fmt:-"$BASHGIT_GL_FORMAT"}" -n"$n" "$@"
}

BASHGIT_SM_RE_PATH='^[[:space:]]*(path)[[:space:]]*=[[:space:]]*(.+)'
BASHGIT_SM_R() {
    pushd "$1" > /dev/null || exit 1

    echo "$PWD"
    [ $# -gt 1 ] && "${@:2}"

    # check if .gitmodules file exists
    if [ -f ".gitmodules" ]; then
        # read .gitmodules
        while IFS=$'\r\n' read -r line; do
            if [[ "$line" =~ $BASHGIT_SM_RE_PATH ]]; then
                BASHGIT_SM_R "${BASH_REMATCH[2]}" "${@:2}"
            fi
        done < ".gitmodules"
    fi

    popd > /dev/null
}

sm() { # navigate git submodules with fzf
    [ -z "$BASHGIT_REPO" ] && return 1

    local repo="${BASHGIT_SUPER:-$BASHGIT_REPO}"
    local modules="$repo/.gitmodules"
    [ -f "$modules" ] || return 1

    local update
    local args=()
    while [ $# -gt 0 ]; do
        case "$1" in
            -h)
                echo "\
-h: help
-u: update all submodules
-u [submodule...]: update specified submodules
-r: run command for every submodule recursively searching for submodules
-x: start at current submodule rather than the super repo"
                return
                ;;
            -u)
                shift
                update=()
                while [ $# -gt 0 ]; do
                    case "$1" in
                        -*) break ;;
                        *)
                            update+=("$1")
                            shift
                            ;;
                    esac
                done
                [ -v update ] || update+=(--recursive)
                update=(git submodule update --init "${update[@]}")
                ;;
            -r)
                shift
                # find parent directory containing .git directory
                # local super="$PWD"
                # while [ -n "$super" ]; do # look for .git
                #     if [ -d "$super/.git" ]; then # .git is a directory
                #         BASHGIT_SM_R "$super" "$@"
                #         return $?
                #     fi
                #     super=${super%/*} # go one directory level deeper
                # done
                # return 1

                BASHGIT_SM_R "${opt_x:-$repo}" "$@"
                return
                ;;
            -x)
                shift
                local opt_x="$BASHGIT_REPO"
                ;;
            --)
                shift
                break
                ;;
            -*)
                echo "Unrecognized option $1" >&2
                return 1
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    if [ -v update ]; then
        (
            set -x
            cd "$repo"
            "${update[@]}"
        )
        return
    fi

    # TODO: go into submodules of submodules
    # modules="$(BASHGIT_SM_R "$BASHGIT_SUPER" | sort | fzf -i -q "${args[*]}")"

    modules="$(awk '
        match($0, /^\[submodule[[:blank:]]+"([^"]+)"\]/, m) {
            if (NR>1) { printf "\n" }
            printf "%s", m[1];
            next
        }
        match($0, /^[[:blank:]]*path[[:blank:]]*=[[:blank:]]*(.+)/, m) {
            printf " %s", m[1];
            next
        }
        END {
            printf "\n"
        }' "$modules" | sort | fzf -i -q "${args[*]}")"

    [ -n "$modules" ] && cd "$repo/${modules##* }"
}

_complete_sm() {
    if [ "$COMP_CWORD" -gt 0 ]; then
        local comp=''
        local arg="${COMP_WORDS[COMP_CWORD]}"
        case "${COMP_WORDS[COMP_CWORD-1]}" in
            -u) #TODO
                ;;
            *)
                case "$arg" in
                    -*)
                        comp='-h -u'
                        ;;
                esac
                ;;
        esac
        COMPREPLY=($(compgen -W "$comp" -- "$arg"))
    fi
}
complete -F _complete_sm sm

topic() {
    [ $# -gt 1 ] || [ -z "$BASHGIT_REPO" ] && return 1

    local branch="$BASHGIT_BRANCH"
    if [ -z "$branch" ]; then
        # HEAD does not point to a branch
        [ -z "$BASHGIT_SUPER" ] && return 1 # no super repo

        # Get branch name from .gitmodules
        local line path
        local re_submodule='^\[submodule[[:blank:]]'
        local re_value='^[[:blank:]]*(path|branch)[[:blank:]]*=[[:blank:]]*(.+)'
        while IFS=$'\n' read -r line; do
            if [[ "$line" =~ $re_submodule ]]; then
                if [ -n "$path" ] && [ "$BASHGIT_SUPER/$path" -ef "$BASHGIT_REPO" ]; then
                    unset path
                    break
                else
                    unset path branch
                fi
            elif [[ "$line" =~ $re_value ]]; then
                declare "${BASH_REMATCH[1]}=${BASH_REMATCH[2]}"
            fi
        done < "$BASHGIT_SUPER/.gitmodules" || return 1
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

br_list_heads() {
    local f
    for f in "$1"/*; do
        if [ -d "$f" ]; then
            br_list_heads "$f"
        else
            f="${f#"$heads/"}"
            full+=("$f $path")
            names["${f##*/}"]=1
        fi
    done
}

br() { # work with submodule branches
    [ -z "$BASHGIT_REPO" ] && return 1

    local repo="${BASHGIT_SUPER:-$BASHGIT_REPO}"
    local modules="$repo/.gitmodules"
    [ -f "$modules" ] || return 1

    local nullglob_orig="$(shopt -p nullglob)"
    shopt -s nullglob

    local line path heads
    local -a full
    local -A names
    local re_path='^[[:blank:]]*path[[:blank:]]*=[[:blank:]]*(.*[^[:blank:]])'
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ $re_path ]]; then
            path="${BASH_REMATCH[1]}"
            heads="${repo}/.git/modules/${path}/refs/heads"
            br_list_heads "$heads"
        fi
    done < "$modules"

    $nullglob_orig

    if [ $# -eq 0 ]; then
        for x in "${!names[@]}"; do
            echo "$x"
        done
    elif [ $# -eq 1 ]; then
        local re_branch="^([^[:blank:]]*/)?$1 (.*)"
        for x in "${full[@]}"; do
            if [[ "$x" =~ $re_branch ]]; then
                echo "$x"
            fi
        done
    fi
}

gw() { # Git Web: print link to the online repo
    BASHGIT_CHECK_REPO
    BASHGIT_CHECK_ORIGIN || return 1

    echo "$BASHGIT_ORIGIN"
}
