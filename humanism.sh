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
# END Optional Settings
#




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
    exit 1
fi


#
# Iterate over arguments and load each function
#

# If no argument defined load all
if [ $# -eq 0 ]; then
    set  -- c log history ps find usage_self ap dbg sshrc fordo $@
fi

# Iterate over defined load arguments
for arg in $*; do
 case "$arg" in
  ap)
  #
  #    unified apt-get, apt-cache and dpkg
  #
  #    ap 		   without arguments for argument list

    if command -v apt-get >/dev/null 2>&1 || command -v pacman >/dev/null 2>&1; then
        alias ap="$HUMANISM_BASE/ap.linux-apt+pac"
	elif command -v brew >/dev/null 2>&1 ; then
        alias ap="$HUMANISM_BASE/ap.osx-brew"
	elif command -v pkg >/dev/null 2>&1 ; then
        alias ap="$HUMANISM_BASE/ap.freebsd-pkg"
	fi
    ;;

  dbg)
  #
  #    unified strace, dtruss, lsof
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

    #touch "$HOME/.cwd"
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
        egrep -v "^$*,|,$*$" "${HUMANISM_C_TAG_FILE}" > "${HUMANISM_C_TAG_FILE}.tmp" \
        && mv "${HUMANISM_C_TAG_FILE}.tmp" "${HUMANISM_C_TAG_FILE}"
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
                | egrep -i "^$*,|,$*$" | head -1)
        # BUGBUG: --max-count not busybox compatible. Replaced with head -1
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
    # command for manual management of tag db
    cc () {
        if [ $# -eq 0 ]; then
            # list tags
            column -t -s "," "$HUMANISM_C_TAG_FILE"  2>/dev/null || \
            sed 's/,/\n  /' "$HUMANISM_C_TAG_FILE"   2>/dev/null || \
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

    # recursive find but ratchet depth (try depth 1, 2 ... $HUMANISM_C_MAXDEPTH)
    _find_filter () {
        local BASEDIR="$1"
        local SEARCH="$2" # ash/sh behave differently than bash with ${@:2}
        local DEPTH=1
        local DIR
        for DEPTH in $(seq 1 $HUMANISM_C_MAXDEPTH); do
            if [ "Linux" = "$OS" ]; then
                DIR=$($TIMEOUT \
                      $FIND "$BASEDIR" -mindepth $DEPTH -maxdepth $DEPTH -iname "*$SEARCH*" -type d \
                      -printf "%C@ %p\n" 2>/dev/null | sort -n | tail -1 | awk '{$1=""; print}' )
                      #-exec stat --format "%Y##%n" humanism.sh/dbg (NOTE ISSUE WITH SPACE)
                      # -printf "%C@ %p\n not busybox find compatible. replace with -exec stat -c "%Y %n" {} \;
            else
                DIR=$($TIMEOUT \
                      $FIND "$BASEDIR" -mindepth $DEPTH -maxdepth $DEPTH -iname "*$SEARCH*" -type d \
                               -exec stat -f "%m %N" {} 2>/dev/null \; | sort -n | tail -1 | awk '{$1=""; print}' )
            fi
            if [[ "$DIR" != "" ]]; then
                # Get full path using either readlink or pushd. (ash/sh might not have pushd)
                # (osx readlink doesn't have expected -f option)
                if command -v realpath >/dev/null 2>&1; then
                    DIR=$(realpath "${DIR## }")
                elif command -v readlink >/dev/null 2>&1 && [ "Linux" = "$OS" ]; then
                    DIR=$(readlink -f "${DIR## }")
                else
                    pushd "${DIR## }" &>/dev/null
                    DIR=$(pwd)
                    popd &>/dev/null
                fi
                echo "$DIR"
                break
            fi
            DEPTH=$(($DEPTH+1))
        done
    }

    cascade_search () {
        local RESULT=""
        local BASE="."
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
            if NEXT_BASE=$(_tag_get "$1") \
               && [ "$NEXT_BASE" != "" ] \
               && echo "$NEXT_BASE" | grep -e "^$BASE" &>/dev/null; then
                BASE="$NEXT_BASE"
                shift
            else
                break
            fi
        done
        # BASE=path of deapest tag, if any matched

        # Assume remaining $* is a filter (with spaces)
        if [ $# -gt 0 ] \
           && NEXT_BASE=$(_find_filter "$BASE" "$*") \
           && [ "$NEXT_BASE" != "" ]; then
            echo "$NEXT_BASE"
            _tag_add "$*" "$NEXT_BASE"
            return
        fi
        # Else split $* into individual filters and find
        while [ $# -gt 0 ]; do
            if NEXT_BASE=$(_find_filter "$BASE" "$1") \
               && [ "$NEXT_BASE" != "" ]; then
                if [ $# -eq 1 ]; then
                    _tag_add "$1" "$NEXT_BASE"
                fi
                BASE=$NEXT_BASE
                shift
            else
                break
            fi
        done
        # This placed here, rather than after tag_add in while() above
        # causes return of last/closest match. Moving it to after tag_add
        # would force exact matches, else move on to parent search (next)
        if [ "$BASE" != "" ] && [ "$BASE" != "." ]; then
            echo "$BASE"
            return
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

    alias c="cascade_command cd"
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
                    #BUGBUG: ash/sh have issue with this syntax. If'ing out wont help. Would need to replace select logic and write own
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
  #   history                      list
  #   history <filter>             greped history
  #   history <filter> <N>         last N results
  #   history <filter> !           execute last
        history () {
                if [ $# -eq 0 ]; then
                        builtin history
                else
                        eval last=\${$#}
                        if [ "$last" == "!" ]; then
                            set -- ${@:1:$#-1} # rm last
                            cmd= $(builtin history | \
                                   grep -v ' history ' | \
                                   grep -i "$*" | \
                                   tail -1 | \
                                   sed 's/^[[:digit:]]\+ //')
                            echo $cmd
                            eval $cmd
                        elif expr $last + 0 > /dev/null; then
                            set -- ${@:1:$#-1} # rm last
                            builtin history | \
                            grep -v ' history ' | \
                            grep -i "$*" | \
                            sed 's/^[[:digit:]]\+ \+//' | \
                            tail -n $last
                        else
                            builtin history | \
                            grep -v ' history '| \
                            grep -i "$*" | \
                            sed 's/^[[:digit:]]\+ \+//'
                        fi
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
                        # `ps aux` is so engraned in my mind. Inform user
                        >&2 echo "humanism.sh ps: \"$@\""
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
        elif [ $# -eq 1 ] && [ -d "$1" ]; then
            # find <path>
            $FIND "$1"
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
  #   find ../ .txt | fordo "echo -e \n\n\n### FILE: " "ls -l" cat

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
