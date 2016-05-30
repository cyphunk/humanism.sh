#!/usr/bin/env bash
# source $0                        loads all functions
# source $0 <func> [func ...]    load specific functions
# $0 help                        function list and description


#
# Optional Settings
#

# Max depth to search forward, backward with c()
HUMANISM_C_MAXDEPTH=${HUMANISM_C_MAXDEPTH:=8}

# using .lcdrc and , as delim to make compatible with https://github.com/deanm/dotfiles/ bashrc
HUMANISM_C_TAG_FILE=${HUMANISM_C_TAG_FILE:="$HOME/.lcdrc"}


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
  #
  #   Managing Tags:
  #   cc                    list tags
  #   cc <tag>              add/rename <tag> for pwd
  #                         prompt to delete if <tag> exists
  #   cc d   <tag>
  #   cc del <tag>          explicit delete
  #

    touch "$HOME/.cwd"
    touch "$HUMANISM_C_TAG_FILE"

    # timeout cmd used to set max time limit for _find_filter()
    if command -v timeout >/dev/null 2>&1 ; then
        TIMEOUT="timeout -s SIGKILL 1s"
    elif command -v gtimeout >/dev/null 2>&1 ; then
        TIMEOUT="gtimeout -s SIGKILL 1s"
    else
        TIMEOUT=""
        echo "humanism: c/cd will run without timeout cmd."
    fi

    # delete tags matching $* by dir or then name
    _tag_delete () {
        egrep -v "^$*,|,$*$" "${HUMANISM_C_TAG_FILE}" > "${HUMANISM_C_TAG_FILE}.tmp"
        mv "${HUMANISM_C_TAG_FILE}.tmp" "${HUMANISM_C_TAG_FILE}"
    }
    # Add tag: _tag_add <name> <path>
    _tag_add () {
        echo "$1,$2" >> "$HUMANISM_C_TAG_FILE"
        echo -n "new tag: $1 -> $2" >&2
        if [ $(wc -l $HUMANISM_C_TAG_FILE | awk '{print $1}') -lt 5 ]; then
            echo " (\`cc d\` to delete)" >&2
        else
            echo "" >&2
        fi
    }
    # get tag by name or dir
    _tag_get () {
        local entry=""
        local dir=""
        # return most recent entry (awk reorder with newest on top)
        entry=$(awk '{x[NR]=$0}END{while (NR) print x[NR--]}' "$HUMANISM_C_TAG_FILE" \
                | egrep --max-count 1 -i "^$*,|,$*$")
        if [ "$entry" != "" ]; then
            # prioritize: move the found entry to top of file
            grep -v "$entry" "$HUMANISM_C_TAG_FILE" > "${HUMANISM_C_TAG_FILE}.tmp"
            echo "$entry" >> "${HUMANISM_C_TAG_FILE}.tmp"
            mv "${HUMANISM_C_TAG_FILE}.tmp" "$HUMANISM_C_TAG_FILE"
            dir=$(echo "$entry" | awk -F"," '{$1=""; print substr($0, 2)}' )
            echo "$dir"
            return 0
        fi
        return 1
    }

    _find_filter () {
        local BASEDIR="$1"
        local SEARCH="${@:2}"
        local DEPTH=1
        local DIR
        for DEPTH in $(seq 1 $HUMANISM_C_MAXDEPTH); do
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
                # resolve absolute path of hit without readlink -f:
                # remove trailing space
                pushd "${DIR## }" &>/dev/null
                DIR=$(pwd)
                popd &>/dev/null
                echo "$DIR"
                break
            fi
            DEPTH=$(($DEPTH+1))
        done
    }

    cascade_search () {
        local RESULT=""
        local BASE=""
        local NEXT_BASE=""

        ######
        # Simple cases
        ######

        # CASE: no args
        if [ $# -eq 0 ]; then
            return
        fi
        # CASE: arg is valid path
        if [ -e "$*" ]; then
            echo "$*"
            return
        # CASE: arg is tag name (including spaces)
        elif RESULT=$(_tag_get "$*") && [[ "$RESULT" != "" ]]; then
            echo "$RESULT"
            return
        fi

        ######
        # Complex cases
        ######

        #
        # CASE: mixed tags and path filters under cwd
        #

        # allow optional BASE dir
        if [ -d "$1" ]; then
            BASE="$1"
            shift
        fi
        # get tags under tags
        while [ $# -gt 0 ]; do
            NEXT_BASE=$(_tag_get "$1")
            if [ "$NEXT_BASE" = "" ]; then
                break
            fi
            if echo "$NEXT_BASE" | grep -e "^$BASE" &>/dev/null; then
                BASE="$NEXT_BASE"
                shift
            else
                break
            fi
        done
        # find filters under tags
        if [ $# -gt 0 ]; then
            BASE=${BASE:=.}
            # assume remaining $* is single filter name (with spaces)
            NEXT_BASE=$(_find_filter "$BASE" "$*")
            if [ "$NEXT_BASE" != "" ]; then
                echo "$NEXT_BASE"
                _tag_add "$*" "$NEXT_BASE"
                return
            fi
            # split $* into individual filters and find
            while [ $# -gt 0 ]; do
                local var=${@:$i:1}
                NEXT_BASE=$(_find_filter "$BASE" "$1")
                if [ "$NEXT_BASE" != "" ]; then
                    BASE=$NEXT_BASE
                    if [ $# -eq 1 ]; then
                        _tag_add "$1" "$NEXT_BASE"
                    fi
                    shift
                else
                    break
                fi
            done
            if [ "$BASE" != "" ] && [ "$BASE" != "." ]; then
                echo "$BASE"
                return
            fi
        fi

        #
        # CASE: nothing found under tags or cwd, go to parents
        #
        echo "<>" >&2
        BASE=""
        for i in $(seq 1 $HUMANISM_C_MAXDEPTH); do
            BASE="../$BASE"
            RESULT=$(_find_filter "$BASE" "$*")
            if [ "$RESULT" != "" ]; then
                echo "$RESULT"
                _tag_add "$*" "$RESULT"
                return
            fi
        done

    }

    c () {
        # no args: go to gobal cwd dir
        if [ $# -eq 0 ]; then
            cd "$(cat "$HOME/.cwd")"
        else
            cd $(cascade_search $*)
        fi
    }

    # command for manual management of tag db
    cc () {
        if [ $# -eq 0 ]; then
            # list tags
            column -t -s "," "$HUMANISM_C_TAG_FILE"  2>/dev/null || \
            sed 's/,/\n  /' "$HUMANISM_C_TAG_FILE"     2>/dev/null || \
            cat "$HUMANISM_C_TAG_FILE"
        elif [ $1 = "del" ] || [ $1 = "d" ]; then
            if [ $# -eq 1 ]; then
                _tag_delete "$(pwd)"
            else
                _tag_delete "${@:2}"
            fi
        elif _tag_get "$*" 1>/dev/null; then     # tag name exists than prompt
            read -p "delete \"$*\" (y/[n])? " YN
            if [ "$YN" = "y" ]; then
                _tag_delete "$*"
            fi
        else
            _tag_add "$*" "$(pwd)"
        fi
    }

    cascade_command () {
    	local cmd=$1; shift;
    	if [ -e "$*" ]; then
    		$cmd "$*"
    	elif local path=$(cascade_search $*) && [[ "$path" != "" ]]; then
    		$cmd "$path"
    	else
    		$cmd $*
    	fi
    }

    _cascade_completion() {
      #local IFS=$'\n'
      COMPREPLY=( $( egrep -i "^$2" "$HUMANISM_C_TAG_FILE" | cut -d, -f 1 ) )
    }

    # zsh
    if command -v compinit >/dev/null 2>&1; then
        # This is not perfect. zsh no my forte. would welcome improvments/suggestions.
        autoload -U compinit && compinit
        autoload -U bashcompinit && bashcompinit
    fi
    complete -o plusdirs -A directory -F _cascade_completion c
    complete -F _cascade_completion cc

    # Examples:
    # alias l="cascade_command 'ls -l --color'"
    # complete -o plusdirs -A file -F _cascade_completion l
    #
    # alias atom="cascade_command atom"
    # complete -o plusdirs -A file -F _cascade_completion atom
    #
    # alias subl="cascade_command subl"
    # complete -o plusdirs -A file -F _cascade_completion subl
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
  #   find                            list files in cwd
  #   find <path>                     list files in path
  #   find <path> <filter> [opts..]   find *FiLtEr* anywhere under path
  #   find <filter>                   find *FiLtEr* anywhere under cwd
  #   find <filter> <path> [opts..]   find *FiLtEr* anywhere under path

    find () {
        if [ $# -eq 0 ]; then
            # find
            $FIND .
            exit 0
        elif [ $# -eq 1 ] && [ -d "$1" ]; then
            # find <path>
            $FIND "$1"
            exit 0
        elif [ $# -eq 1 ] && [ ! -d "$1" ]; then
            # find <filter>
            P="./"
            FILTER="$1"; shift
        elif [ ! -d "$1" ] && [ -d "$2" ]; then
            # find <filter> <path> [$*]
            P="$2";
            FILTER="$1"; shift; shift
        else
            # find <path> <filter> [$*]
            P="$1";
            FILTER="$2"; shift; shift
        fi
        $FIND $FOLLOWSYMLNK "$P" -iname "*$FILTER*" $*
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
