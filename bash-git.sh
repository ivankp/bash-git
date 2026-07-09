# PS1 and \ variables documentation:
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
    local prev_duration=$(( $SECONDS - $_PREV_SECONDS ))
    unset _PREV_SECONDS

    PS1="$COLOR_GREY┌$COLOR_0 "

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

        PS1="\n$COLOR_GREY$d$COLOR_0\n$PS1"
    fi

    # number of background processes
    PS1+='${_BASHGIT_NJOBS\j-\[\033[33m\][\j]\[\033[0m\] }'

    # python virtual environment
    [ -n "$VIRTUAL_ENV" ] && PS1+="🐍 "

    # git
    unset BASHGIT_{GIT,SUPER,HASH,BRANCH,ORIGIN,ORIGIN_SHORT}
    BASHGIT_REPO="$PWD"
    while [ -n "$BASHGIT_REPO" ]; do # look for .git
        BASHGIT_GIT="$BASHGIT_REPO/.git"
        if [ -d "$BASHGIT_GIT" ]; then # if .git is a directory
            break
        elif [ -f "$BASHGIT_GIT" ]; then # if .git is a file
            # this is a submodule
            local re_gitdir='^gitdir:[[:blank:]]*((.*)/\.git.*)'
            if [[ "$(< "$BASHGIT_GIT")" =~ $re_gitdir ]]; then
                local BASHGIT_GIT_TMP="$BASHGIT_REPO/${BASH_REMATCH[1]}"

                if [ ! -d "$BASHGIT_GIT_TMP" ]; then # gitdir is not a directory
                    # printf "\033[31mInvalid $BASHGIT_GIT file\033[0m\n" >&2
                    # cat "$BASHGIT_GIT" >&2
                    BASHGIT_REPO=${BASHGIT_REPO%/*} # go one directory level deeper
                    continue
                fi

                BASHGIT_GIT="$BASHGIT_GIT_TMP"
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
        local re_ref='^ref:[[:blank:]]*(refs/heads/(.+))'
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
        local re_origin='^\[remote[[:blank:]]+"origin"\]'
        local re_url='^[[:blank:]]*url[[:blank:]]*=[[:blank:]]*(.+)'
        local re_url2='(.*:([0-9]*/)?)?(([^/]+/)?[^/]+)\.git$'
        local line
        while IFS=$'\n' read -r line; do
            if [ -v re_origin ]; then
                [[ "$line" =~ $re_origin ]] && unset re_origin
            elif [[ "$line" =~ $re_url ]]; then
                BASHGIT_ORIGIN="${BASH_REMATCH[1]}"
                if [[ "$BASHGIT_ORIGIN" =~ $re_url2 ]]; then
                    BASHGIT_ORIGIN_SHORT="${BASH_REMATCH[3]}"
                    PS1+="\[\033[35m\]$BASHGIT_ORIGIN_SHORT$COLOR_0 "
                fi
                break
            fi
        done < "$BASHGIT_GIT/config"
    fi

    # current directory
    local cwd="$PWD"
    [[ "$cwd" =~ ^"$HOME"/? ]] && cwd="~${cwd#$HOME}"
    # grey slashes
    PS1+="${cwd//\//$COLOR_GREY/$COLOR_0}"

    # prompt
    # count how many child processes we are from the original bash process
    local prompt_symbol='├'
    if [ "$MSYSTEM" == "MINGW64" ]; then
        local pid=$$
        while [ "$pid" != '1' ]; do
            prompt_symbol+='\$'
            pid="$(< "/proc/$pid/ppid")"
        done
    else
        prompt_symbol+='\$'
    fi
    PS1+="\n$COLOR_GREY$prompt_symbol$COLOR_0 "

    # set terminal window title
    PS1="\[\033]0;${BASHGIT_ORIGIN_SHORT:-Git Bash}\007\]$PS1"
}

PROMPT_COMMAND=BASHGIT_UPDATE_PS1

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
