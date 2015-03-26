#!/usr/bin/env bash
# source $0                        loads all functions
# source $0 <func> [func ...]    load specific functions
# $0 help                        function list and description

#TODO: bug. c human and then cd causes it to delete even if this was not a new tag
#      this may have to do with the reordering on _tag_get
#      we could consider this a feature but probably not

#
# Optional Settings
#

# Verbose debugging
HUMANISM_DEBUG=${HUMANISM_DEBUG:=0}

# Max depth to search forward, backward with c()
HUMANISM_C_MAXDEPTH=${HUMANISM_C_MAXDEPTH:=8}

# using .lcdrc and , as delim to make compatible with https://github.com/deanm/dotfiles/ bashrc
HUMANISM_C_TAG_FILE=${HUMANISM_C_TAG_FILE:="$HOME/.lcdrc"}

# By default we attempt to auto tag on filter hits
HUMANISM_C_TAG_AUTO=${HUMANISM_C_TAG_AUTO:=1}

# Force unique tag names
HUMANISM_C_TAG_UNIQUE=${HUMANISM_C_TAG_UNIQUE:=0}

# if unique false/0 its advised to prioritize most recent tags
HUMANISM_C_TAG_PRIORITIZE_RECENT=${HUMANISM_C_TAG_PRIORITIZE_RECENT:=1}

#
# Common aliases
#

# Use color if possible
if echo "x" | grep --color x >/dev/null 2>&1; then
    alias egrep='egrep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias grep='grep --color=auto'
fi
# have ls --color=auto?
if ls --color=auto >/dev/null 2>&1; then
    alias ls='ls --color=auto'
fi

SH_SOURCE=${BASH_SOURCE:-$_}

if ! shopt -s expand_aliases >/dev/null 2>&1; then
    setopt aliases >/dev/null 2>&1
fi

if readlink "$SH_SOURCE" >/dev/null 2>&1; then
    export HUMANISM_BASE="$(dirname $(readlink $SH_SOURCE))"
else
    export HUMANISM_BASE="$(dirname $SH_SOURCE)"
fi

OS="$(uname)"
# important command:
# we override with our find. hence gracefully obtain location of original.
FIND="$(which find 2>/dev/null || (command -v env && echo 'find') )"
if [ "$FIND" = "" ]; then
    echo "humanism: couldn't find 'find'. exit"
    return 1
fi

debug () {
    if [ $HUMANISM_DEBUG -ne 0 ]; then
        >&2 echo "$*"
    fi
}

#
# Iterate over arguments and load each function
#

# If no argument defined load all
if [ $# -eq 0 ]; then
    set  -- c log history ps find usage_self ap dbg sshrc fordo $@
fi

for arg in $*; do

 case "$arg" in
  ap)
  #
  #    unified apt-get, apt-cache and dpkg
  #
  #    ap 		   without arguments for argument list

    if command -v apt-get >/dev/null 2>&1 ; then
    	ap () {
			"$HUMANISM_BASE/ap.linux-apt" $*
		}
	elif command -v brew >/dev/null 2>&1 ; then
		ap () {
			"$HUMANISM_BASE/ap.osx-brew" $*
		}
	elif command -v pkg >/dev/null 2>&1 ; then
		ap () {
			"$HUMANISM_BASE/ap.freebsd-pkg" $*
		}
	fi
    ;;

  dbg)
  #
  #    unified strace, lsof
  #
  #    dbg 		   without arguments for argument list

    dbg () {
        "$HUMANISM_BASE/dbg" $*
    }
    ;;


  sshrc)
  #
  #    carry env through ssh sessions
  #

		sshrc () {
			"$HUMANISM_BASE/sshrc" $*
		}
		;;

  cd|c)
  #
  #   recursive cd
  #
  #   c                     change to global cwd
  #   c <fIlTeR>            go to path or find and goto filter
  #                         1. if filter is path, goto
  #                         2. if filter is name in tag db, goto
  #                         3. if filter found under cwd, goto
  #                         4. if filter found above cwd, goto
  #   c <fIlTeR> <fIlTeR>   filter cascading. find filter, then Nth filter under it
  #   c <tag> <tag>         tag cascading
  #   c <tag> <fIlTeR>      combined. many tags, one filter
  #   l <tag> <fIlTeR>      ls that adheres to all of the above
  #
  #   Managing Tags:
  #   cc                    list tags
  #   cc <tag>              add/rename <tag> for pwd
  #                         prompt to delete if <tag> exists
  #   cc d   <tag>
  #   cc del <tag>          explicit delete
  #
  #   Optional:
  #   HUMANISM_C_TAG_AUTO=1 # set tp 0 to turn off auto tag creation from FiLtEr
  #   HUMANISM_C_TAG_UNIQUE=0 # set to 1 to force tags to be unique
  #   HUMANISM_C_TAG_PRIORITIZE_RECENT=1 # 0 to give priority to older tags


    # timeout cmd used to set max time limit for _find_filter()
    if command -v timeout >/dev/null 2>&1 ; then
        TIMEOUT="timeout -s SIGKILL 1s"
    elif command -v gtimeout >/dev/null 2>&1 ; then
        TIMEOUT="gtimeout -s SIGKILL 1s"
    else
        TIMEOUT=""
        echo "humanism: c/cd will run without timeout cmd."
    fi

    touch "$HOME/.cwd"
    touch "$HUMANISM_C_TAG_FILE"

    # delete tags matching $* by dir or then name
    _tag_delete () {
        debug "_tag_delete() \"$*\""
        egrep -v "^$*,|,$*$" > "${HUMANISM_C_TAG_FILE}.tmp" "${HUMANISM_C_TAG_FILE}"
        mv "${HUMANISM_C_TAG_FILE}.tmp" "${HUMANISM_C_TAG_FILE}"
    }
    # Add tag "$2" for dir "$1"
    _tag_add () {
        if [ $HUMANISM_C_TAG_UNIQUE -eq 1 ] && egrep --quiet -i "^$2," "$HUMANISM_C_TAG_FILE"; then
             return 0
        fi
        echo "$2,$1" >> "$HUMANISM_C_TAG_FILE"
        echo "new tag: $2 -> $1" >&2
    }
    # get tag by name or dir
    _tag_get () {
        local hit=""
        local entry=""

        if [ $HUMANISM_C_TAG_PRIORITIZE_RECENT -eq 1 ]; then
            entry=$(awk '{x[NR]=$0}END{while (NR) print x[NR--]}' "$HUMANISM_C_TAG_FILE" | egrep --max-count 1 -i "^$*,|,$*$")
        else
            entry=$(egrep --max-count 1 -i "^$*,|,$*$"  "$HUMANISM_C_TAG_FILE")
        fi

        if [ "$entry" != "" ]; then
            if [ $HUMANISM_C_TAG_PRIORITIZE_RECENT -eq 1 ]; then
                # as modified time is used to for auto_manage, we attempt to
                # ignore prioritize recents effect
                if [ "Linux" = "$OS" ]; then
                    local modified_time=$(stat --format "%Y" "$HUMANISM_C_TAG_FILE")
                else
                    local modified_time=$(stat -f "%m" "$HUMANISM_C_TAG_FILE")
                fi
                grep -v "$entry" "$HUMANISM_C_TAG_FILE" > "${HUMANISM_C_TAG_FILE}.tmp"
                echo "$entry" >> "${HUMANISM_C_TAG_FILE}.tmp"
                mv "${HUMANISM_C_TAG_FILE}.tmp" "$HUMANISM_C_TAG_FILE"
                if [ "Linux" = "$OS" ]; then
                    touch -t $(date +%m%d%H%M -d $modified_time) "$HUMANISM_C_TAG_FILE"
                else
                    touch -t $(date -r $modified_time +%m%d%H%M) "$HUMANISM_C_TAG_FILE"
                fi

            fi
            # tag=${entry%%,*} directory hit=${entry#*,}
            hit=$(echo "$entry" | awk -F"," '{$1=""; print substr($0, 2)}' )
            echo "$hit"
            return 0
        fi

        return 1
    }
    _tags_list () {
        if command -v column >/dev/null 2>&1; then
            column -t -s "," "$HUMANISM_C_TAG_FILE"
        elif command -v sed >/dev/null 2>&1; then
            sed 's/,/\n  /' "$HUMANISM_C_TAG_FILE"
        else
            cat "$HUMANISM_C_TAG_FILE"
        fi
    }

    _tag_auto_manage () {
        if [ $HUMANISM_C_TAG_AUTO -ne 1 ]; then
            return 0
        fi

        local DIR="$1"
        local TAG="${@:2}"

        debug "_tag_auto_manage() \"$TAG\" -> \"$DIR\""

        local last_dir=$(cat "$HOME/.cwd")

        # resolve absolute path of hit without readlink -f:
        pushd "$DIR" &>/dev/null
        local curr_dir=$(pwd)
        popd &>/dev/null

        if [ "Linux" = "$OS" ]; then
            local last_dir_time=$(stat --format "%Y" "$HUMANISM_C_TAG_FILE")
        else
            local last_dir_time=$(stat -f "%m" "$HUMANISM_C_TAG_FILE")
        fi
        local now=$(date +%s)

        # purge entry only if we cd()/c()'ed very recently and into a parent dir
        # this auto purge will not work on HUMANISM_C_TAG_PRIORITIZE_RECENT
        if [ $(expr $now - $last_dir_time)  -lt 5 ] && [ "${curr_dir#$last_dir}" = "$curr_dir" ]; then
                debug "_tag_auto_manage() DELETE."
                debug "  parent: \"$last_dir\", current: \"$curr_dir\""
                _tag_delete "$last_dir"
        else
            if [ "$TAG" != "" ]; then
                debug "_tag_auto_manage() ADD. \"$TAG\""
                _tag_add "$curr_dir" "$TAG"
            fi
        fi

    }

    # function for manual management of tag db
    cc () {
        if [ $# -eq 0 ]; then
             _tags_list
        elif [ $1 = "del" ] || [ $1 = "d" ]; then
            if [ $# -eq 1 ]; then
                _tag_delete "$(pwd)"
            else
                _tag_delete "${@:2}"
            fi
        # elif _tag_get "$(pwd)"; then # tag dir exists then prompt
        #     read -p "change $(pwd) to \"$*\" (y/[n])? " YN
        #     if [ "$YN" = "y" ]; then
        #         _tag_delete "$(pwd)"
        #         _tag_add "$(pwd)" "$*"
        #     fi
        elif _tag_get "$*" 1>/dev/null; then     # tag name exists than prompt
            read -p "delete \"$*\" (y/[n])? " YN
            if [ "$YN" = "y" ]; then
                _tag_delete "$*"
            fi
        else
            _tag_add "$(pwd)" "$*"
        fi
    }

    _find_filter () {
        local BASEDIR="$1"
        local SEARCH="${@:2}"
        local DEPTH=1
        local DIR
        for DEPTH in $(seq 1 $HUMANISM_C_MAXDEPTH); do
            # timeout forces stop after one second
            debug "_find_filter: \"$BASEDIR\" search \"$SEARCH\" depth $DEPTH"
            if [ "Linux" = "$OS" ]; then
                DIR=$($TIMEOUT \
                      $FIND "$BASEDIR" -mindepth $DEPTH -maxdepth $DEPTH -iname "*$SEARCH*" -type d \
                      -printf "%C@ %p\n" 2>/dev/null | sort -n | tail -1 | awk '{$1=""; print}' )
                      #-exec stat --format "%Y##%n" humanism.sh/dbg (NOTE ISSUE WITH SPACE)
            else
                DIR=$($TIMEOUT \
                      $FIND "$BASEDIR" -mindepth $DEPTH -maxdepth $DEPTH -iname "*$SEARCH*" -type d \
                               -exec stat -f "%m %N" {} 2>/dev/null \; | sort -n | tail -1 | awk '{$1=""; print}' )
            fi
            if [[ "$DIR" != "" ]]; then
                # remove trailing space
                echo "${DIR## }"
                break
            fi
            DEPTH=$(($DEPTH+1))
        done
    }
    _find_cascade () {
        # TODO: test in sh and zsh freebsd and embedded hosts
        # 1. find tag matching "$*"
        #    _find_cascade "this is a complete tag name"
        # 2. find tag's in $*
        #    _find_cascade tag1 tag2 tagN
        # 3. when tags not find use rest as one filter
        #    _find_cascade "this is a filter"
        # 4. if that fails then
        #    _find_cascade "filter1" "filterN"
        # supports:
        #    _find_casecade tag1 tagN "filter under tags"
        #    _find_casecade tag1 tagN "filter1" "filterN"

        debug "_find_cascade() argument:\"$*\""

        local curr_dir=""
        local next_dir=""

        # CASE1 _find_cascade "this is a complete tag name"
        debug "_find_cascade() tag search: \"$*\""
        curr_dir=$(_tag_get "$*")
        if [ "$curr_dir" != "" ]; then
            debug "_find_cascade() tag hit: \"$curr_dir\""
            echo "$curr_dir"
            return
        fi

        # CASE2: _find_cascade tag1 tagN [filter1 filterN]
        # expand "$*" as tags
        while [ $# -gt 0 ]; do
            debug "_find_cascade() tag loop search: \"$1\""
            next_dir=$(_tag_get "$1")
            if [ "$next_dir" = "" ]; then
                debug "_find_cascade() tag loop break"
                break
            fi
            if echo "$next_dir" | grep -e "^$curr_dir" &>/dev/null; then
                debug "_find_cascade() tag loop hit: \"$next_dir\" contains parent \"$curr_dir\""
                curr_dir="$next_dir"
                shift
            else
                debug "_find_cascade() tag loop hit: \"$next_dir\" does not contain parent \"$curr_dir\". break"
                break
            fi
        done

        debug "_find_cascade() i: \"$#\""

        if [ $# -gt 0 ]; then
            # search in last curr_dir hit from tags, or ./
            curr_dir=${curr_dir:=.}
            debug "_find_cascade() filter search: \"$*\" in \"$curr_dir\""
            next_dir=$(_find_filter "$curr_dir" "$*")
            # curr_dir=${next_dir:=$curr_dir}
            if [ "$next_dir" != "" ]; then
                debug "_find_cascade() filter hit: \"$next_dir\""
                echo "$next_dir"
                _tag_auto_manage "$next_dir" "$*" # check if auto make new tag
                return
            fi

            # CASE4 _find_cascade [tag1 tagN] filter1 filterN
            while [ $# -gt 0 ]; do
                local var=${@:$i:1}
                debug "_find_cascade() filter loop search: \"$1\" in \"$curr_dir\""
                next_dir=$(_find_filter "$curr_dir" "$1")
                if [ "$next_dir" != "" ]; then
                    debug "_find_cascade() filter loop hit: \"$next_dir\""
                    curr_dir=$next_dir
                    if [ $# -eq 1 ]; then
                        _tag_auto_manage "$next_dir" "$1"  # check if auto make new tag last
                    fi
                    shift
                else
                    debug "_find_cascade() tag loop break. end."
                    return
                fi
            done
        fi

        if [ "$curr_dir" != "" ] && [ "$curr_dir" != "." ]; then
            debug "_find_cascade() final curr_dir: \"$curr_dir\""
            echo "$curr_dir"
            return
        fi
    }

    l () {
        # list files under a tag other wise pass through to ls
        # first record the basic ls arguments (ones without options)
        # assumes args are first
        local args="$*"
        local flags=""
        while [ $# -gt 0 ] ; do
            case "$1" in
                --*|-*) flags="$flags $1"; shift ;;
                *) break ;;
            esac
        done
        local hit=$(_find_cascade $*)
        if [[ "$hit" != "" ]]; then
            ls $flags "$hit"
        else
            ls $args
        fi
    }
    cd () {
        builtin cd "$@"
        _tag_auto_manage "$@"
        pwd > "$HOME/.cwd"
    }
    c () {
        # # no args: go to gobal cwd dir
        if [ $# -eq 0 ]; then
            cd "$(cat "$HOME/.cwd")"
        elif [ -d "$*" ]; then
            cd "$*"
            return 0
        # arg1: has no slashes so find it in the cwd
        else
            # forward search tags and filters
            local hit=$(_find_cascade $*)
            if [ "$hit" != "" ]; then
                debug "c() cascade hit: \"$hit\""
                builtin cd "$hit"
                pwd > "$HOME/.cwd"
                return 0
            fi
            # now search backward and upward filters only
            echo "<>" >&2
            local FINDBASEDIR=""
            for i in $(seq 1 $HUMANISM_C_MAXDEPTH); do
                    FINDBASEDIR="../$FINDBASEDIR"
                    hit=$(_find_filter "$FINDBASEDIR" "$*")
                    debug "c() reverse hit: \"$hit\""
                    if [ "$hit" != "" ]; then
                           builtin cd "$hit"
                           _tag_auto_manage "$hit" "$*"
                           pwd > "$HOME/.cwd"
                           break
                    fi
            done
        fi
    }
    _compute_c_completion() {
      #local IFS=$'\n'
      COMPREPLY=( $( egrep -i "^$2" "$HUMANISM_C_TAG_FILE" | cut -d, -f 1 ) )
    }
    # zsh
    if command -v compinit >/dev/null 2>&1; then
        # This is not perfect. zsh no my forte. would welcome improvments/suggestions.
        autoload -U compinit && compinit
        autoload -U bashcompinit && bashcompinit
    fi
    complete -o plusdirs -A directory -F _compute_c_completion c
    complete -F _compute_c_completion cc
    complete -o plusdirs -A file -F _compute_c_completion l
    ;;

  log)
  #
  #   create run.sh from history (source in .bash_aliases)
  #
  #   log                  show recent commands and select which are recorded
  #   log some message    append echo message to run.sh
  #   log <N>              append Nth cmd from last. e.g. `log 1` adds last cmd

        log () {
                if [ "$HUMANISM_LOG" == "" ]; then
                        echo "setting LOG=./run.sh"
                        export HUMANISM_LOG="./run.sh"
                else
                        echo "LOG FILE: $HUMANISM_LOG"
                fi
                o=$IFS
                IFS=$'\n'
                H=$(builtin history | tail -20 | head -19 | sort -r  | sed 's/^  *//' | cut -d " " -f 3- )
                if [ $# -eq 0 ]; then
                        select CMD in $H; do
                            break;
                        done;
                elif [[ $# == 1 && "$1" =~ ^[0-9]+$ ]]; then
                        CMD=$(echo "$H" | head -$1 | tail -1)
                else
                        CMD="echo -e \"$@\""
                fi
                IFS=$o
                if [ "$CMD" != "" ]; then
                        echo "CMD \"$CMD\" recorded"
                        if [ ! -f $HUMANISM_LOG ]; then
                                echo "#!/usr/bin/env bash">$HUMANISM_LOG
                        fi
                        echo "$CMD" >> $HUMANISM_LOG
                fi
                chmod u+x "$HUMANISM_LOG"
        }
        ;;

  history)
  #
  #   history with grep
  #
  #   history            list
  #   history <filter>   greped history

        history () {
                if [ $# -eq 0 ]; then
                        builtin history
                else
                        builtin history | grep $@
                fi
        }
        ;;

  ps|pskill)
  #
  #   ps with grep + killps
  #
  #   ps                            list
  #   ps <filter>                   filtered
  #   ps <filter> | killps [-SIG]   kill procs

        if [ "$OS" = "Linux" ]; then
            FOREST="--forest"
        fi
        ps () {
                if [ $# -eq 0 ]; then
                        /usr/bin/env ps $FOREST -x -o pid,uid,user,command
                else
                        /usr/bin/env ps $FOREST -a -x -o pid,uid,user,command | grep -v grep | egrep $@
                fi
        }
        killps () {
                kill $@ $(awk '{print $1}')
        }
        ;;

  find)
  #
  #   find as it should be
  #
  #   find <filter>          find *FiLtEr* anywhere under cwd
  #   find <path> <filter>   find *FiLtEr* anywhere under path path
  #   find $1 $2 $3 ...       pass through to normal find

    #FOLLOWSYMLNK="-L"
    FOLLOWSYMLNK=""
    find () {
        LS=""
        if [[ "$1" == "-ls" ]]; then
            # i need -ls some times
            LS="-ls"
            shift;
        fi
        if [ $# -eq 0 ]; then
            $FIND .
        elif [ $# -eq 1 ]; then
            # If it is a directory in cwd, file list
            if [ -d "$1" ]; then
                $FIND $FOLLOWSYMLNK "$1" $LS
                # else fuzzy find
            else
                $FIND $FOLLOWSYMLNK ./ -iname "*$1*" $LS 2>/dev/null
            fi
        elif [ $# -eq 2 ]; then
            $FIND $FOLLOWSYMLNK "$1" -iname "*$2*" $LS 2>/dev/null
        else
            $FIND $@ $LS
        fi
    }
    ;;

  fordo)
  #
  #   fordo() execute commands on items via pipe. i.e.:
  #
  #   find ../ .txt | fordo echo cat

    fordo () {
      # exec command list on items piped in
      #    find ../ .txt | fordo echo cat
      while read data; do
         for cmd in "$@"; do
           $cmd $data
         done
      done
    }
    ;;
  usage_self)
  #
  # read $0 script and print usage. Assumes $0 structure:
  #
  #   name1)
  #   # comment line1, exactly two spaces on left margin
  #   # comment line2 (up to 10 lines)
  #   <code>

    usage_self () {
            CMD=`basename "$0"`
            echo -en "usage: $CMD "
            # 1: print argument line
            # get args                | into one line | remove )     | aling spacing  | show they OR options
            grep '^  *[^ \(\*]*)' $0 | xargs         | sed 's/)//g' | sed 's/ +/ /g' | sed 's/ /\|/g' | sed 's/--//g'
            # 2: Print arguments with documentation
            echo ""
            grep -A 30 '^  *[^ \(\*]*)' $0 | egrep -B 1 '^  #' | sed 's/#//' | sed 's/--//g'
            echo ""
    }
    ;;

  help)
  # Get usage from comments
    source $0 usage_self
    usage_self
    ;;
 esac
done


# TODO: after using c_history branch there is a colusion issue
# first as a neutral effect of auto tagging from c() one can handle colisions
# by using different fiters for two dirs in different paths:
#       gi,~/project1/code/git
#      git,~/project2/code/git
# This is not exactly bad but requires odd hackery behavior.
#
# Alternatives that remove the auto tag add from filter feature of c():
#    * don't auto tag and instead provide a ca() ("add") that records last match filter
#      in the tag db:
#         $ c git
#         ~/project1/code/git$
#      the filter 'git' is not auto recorded by executing this would record it:
#         ~/project1/code/git$ ca
#      or to set a different tag 'p1git' use:
#         ~/project1/code/git$ ca p1git
#    * monitor for collisons and add part of path to name. Would have problem
#      know which part of path is clever to avoid this:
#                 git,~/project1/code/git
#             codegit,~/project2/code/git
#      To solve you could search the paths from the db to come to the proper:
#                 git,~/project1/code/git
#         project2git,~/project2/code/git
#      But you probably could not avoid this:
#                 git,~/project1/code/git
#              srcgit,~/project2/code/src/git
#      Obviously 'srcgit' would be a tag one might forget is for project2.
#      Currently see no clean way to resolve this.
# Alternatives that retain the auto tag add from filter feature:
#    * search db in reverse order placing greater importance on most recent tag
#      requires allowing paths with the same tag name
#      requires moving an old tag+path key to the front when its used
#      though im not sure this works. perhaps one would never be able to reach
#      the older tag again. assumeing the following, with bottom being recent:
#         git,~/project2/code/git
#         git,~/project1/code/git
#      how would we ever be able to move project2 git to bottom/most-recent?
#      currently if we are in the project2/ dir and `c git` this may work
#    * allow multiple filters to c:
#        $ c p 2 git
#        creates p2git tag for ~/project2/code/git
#      it is unclear how to use find for this without increasing search time
#      as this may require pulling in all entries and not just stopping on first
#      hit
# Other ideas:
#    * allow tag chaining. so with the db:
#         project1,~/project1
#         git,~/project1/code/git
#         project2,~/project2
#         git,~/project1/code/git
#
#         $ c git
#         ~/project1/code/git$ cd
#         $ c project2 git
#         ~/project2/code/git$
#     aka: find $2 that is under $1 tree
#     This is the current function
#     TODO: if first N tags match and there is still N+1 arg, run a search on this
#     Okay wait, now this is the actual version shown here
