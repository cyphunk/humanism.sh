#!/usr/bin/env bash
# source $0                        loads all functions
# source $0 <func> [func ...]    load specific functions
# $0 help                        function list and description

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

#
# Optional Settings
#
HUMANISM_DEBUG=${HUMANISM_DEBUG:=0}
HUMANISM_C_MAXDEPTH=${HUMANISM_C_MAXDEPTH:=8}
# using .lcdrc and , as delim to make compatible with https://github.com/deanm/dotfiles/ bashrc
HUMANISM_C_TAG_FILE=${HUMANISM_C_TAG_FILE:="$HOME/.lcdrc"}
HUMANISM_C_TAG_DELIM=","

# By default we attempt to auto tag on filter hits
HUMANISM_C_TAG_AUTO=${HUMANISM_C_TAG_AUTO:=1}
# By default prioritize most recent tag entries and query results
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
  #                         3. if found filter under cwd, goto
  #                         4. if found filter above cwd, goto
  #   c <fIlTeR> <fIlTeR>   filter cascading. find filter, then Nth filter under it
  #   c <tag> <tag>         tag cascading
  #   c <tag> <fIlTeR>      combined
  #   l <tag> <fIlTeR>      ls that adhears to all of the above
  #
  # Managing Tags:
  #   c l
  #   c list                list tags.
  #   c n    <tag>
  #   c name <tag>          add or rename tag for pwd to <tag>
  #   c d
  #   c del                 delete tags for pwd from db
  #   c d   <tag>
  #   c del <tag>           delete tag by name from pwd
  #
  # Optional:
  # HUMANISM_C_TAG_AUTO=0
  # if set to 1 (default) in your env `c fIlTeR` will auto add filter to tag db on success

    # timeout cmd used to set max time limit to search
    if command -v timeout >/dev/null 2>&1 ; then
        TIMEOUT="timeout"
    elif command -v gtimeout >/dev/null 2>&1 ; then
        TIMEOUT="gtimeout"
    else
        echo "error: c/cd requires timeout cmd"
    fi

    touch "$HUMANISM_C_TAG_FILE"

    # delete tags matching $* (dir or tag name)
    _tag_delete () {
        debug "_tag_delete() \"$*\""
        if [ $# -ge 0 ]; then
            grep -v "$*" > "${HUMANISM_C_TAG_FILE}.tmp" "${HUMANISM_C_TAG_FILE}"
            mv "${HUMANISM_C_TAG_FILE}.tmp" "${HUMANISM_C_TAG_FILE}"
        fi
    }
    # Add tag "$2" to dirctory "$1"
    _tag_add () {
        debug "_tag_add() \"$2\" -> \"$1\""
        # Force unique tag name:
        if ! egrep --quiet -i "^$2${HUMANISM_C_TAG_DELIM}" "$HUMANISM_C_TAG_FILE" ; then
            echo "$2${HUMANISM_C_TAG_DELIM}$1" >> "$HUMANISM_C_TAG_FILE"
        fi
    }
    # rename tag with given path to new tag name
    # _tag_rename () {
    #     _tag_delete "${@:2}" # all but first = path
    #     _tag_add "$1" "${@:2}"
    # }
    _tag_get () {
        # bottom first (tail-r)
        local hit=""
        if [ $HUMANISM_C_TAG_PRIORITIZE_RECENT -eq 1 ]; then
            local entry=$(tail -r "$HUMANISM_C_TAG_FILE" | egrep --max-count 1 -i "^$*${HUMANISM_C_TAG_DELIM}")
            if [ "$entry" != "" ]; then
                grep -v "$entry" "$HUMANISM_C_TAG_FILE" > "${HUMANISM_C_TAG_FILE}.tmp"
                echo "$entry" >> "${HUMANISM_C_TAG_FILE}.tmp"
                mv "${HUMANISM_C_TAG_FILE}.tmp" "$HUMANISM_C_TAG_FILE"
                hit=$(echo "$entry" | awk -F"${HUMANISM_C_TAG_DELIM}" '{$1=""; print substr($0, 2)}' )
            fi
        else
            hit=$(egrep --max-count 1 -i "^$*${HUMANISM_C_TAG_DELIM}"  "$HUMANISM_C_TAG_FILE" | \
                  awk -F"${HUMANISM_C_TAG_DELIM}" '{$1=""; print substr($0, 2)}' )
        fi
        #awk -F"$HUMANISM_C_TAG_DELIM" pat="$*" '{first=$1; $1=""; if (first == "pat") print $0}' "$HUMANISM_C_TAG_FILE")
        echo "$hit"
    }
    _tags_list () {
        column -t -s "$HUMANISM_C_TAG_DELIM" "$HUMANISM_C_TAG_FILE"
    }
    # cc () {
    #     # adding and renaming functionality
    #     if []
    #     if [ $# -eq 0 ]; then
    #         local CWD=$(cwd)
    #         if egrep "${HUMANISM_C_TAG_DELIM}$CWD$" ; then
    #             read TAG -p "Rename current directory tag to: "
    #         else
    #             read TAG -p "Tag current directory: "
    #         fi
    #         if egrep "^$TAG${HUMANISM_C_TAG_DELIM}" ; then
    #             read ACTION -p "Tag exists. <enter> to rename, d to delete"
    #         fi
    #         _tag_rename "$CWD" "$TAG"
    #     fi
    # }

    _tag_manage () {
        # Called without TAG means it may delete but will never add
        local DIR="$1"
        local TAG="$2"
        debug "_tag_manage() \"$TAG\" -> \"$DIR\""

        #local last_dir=$(tail -1 "$HUMANISM_C_TAG_FILE" | awk -F"$HUMANISM_C_TAG_DELIM" '{$1=""; print substr($0, 2)}')
        local last_dir=$(cat $HOME/.cwd)
        # resolve absolute path of hit without readlink -f
        pushd "$DIR" &>/dev/null
        local curr_dir=$(pwd)
        popd &>/dev/null

        if [ "Linux" = "$OS" ]; then
            last_hit_time=$(stat --format "%Y" "$HUMANISM_C_HISTORY_FILE")
        else
            last_hit_time=$(stat -f "%m" "$HUMANISM_C_HISTORY_FILE")
        fi
        local now=$(date +%s)
        
        # purge entry only if we cd()/c()'ed very recently and into a parent dir
        if [ $(expr $now - $last_dir_time)  -lt 5 ] && [ "${curr_dir#$last_dir}" == "$curr_dir" ]; then
                debug "_tag_manage() DELETE."
                debug "  parent: \"$last_dir\", current: \"$curr_dir\""
                _tag_delete "$last_dir"
                # _tag_delete "$curr_dir"
        else
            if [ "$TAG" != "" ]; then
                debug "_tag_manage() ADD."
                _tag_add "$curr_dir" "$TAG"
            fi
        fi

    }

    _find_filter () {
        local BASEDIR="$1"
        local SEARCH="${@:2}"
        local DEPTH=1
        local DIR
        for DEPTH in $(seq 1 $HUMANISM_C_MAXDEPTH); do
            # timeout forces stop after one second
            if [ "Linux" = "$OS" ]; then
                DIR=$($TIMEOUT -s SIGKILL 1s \
                      /usr/bin/env find $BASEDIR -mindepth $DEPTH -maxdepth $DEPTH -iname "*$SEARCH*" -type d \
                               -printf "%C@ %p\n" 2>/dev/null | sort -n | tail -1 | awk '{$1=""; print}' )
                            #-exec stat --format "%Y##%n" humanism.sh/dbg (NOTE ISSUE WITH SPACE)
            else
                DIR=$($TIMEOUT -s SIGKILL 1s \
                      /usr/bin/env find $BASEDIR -mindepth $DEPTH -maxdepth $DEPTH -iname "*$SEARCH*" -type d \
                               -exec stat -f "%m %N" {} 2>/dev/null \; | sort -n | tail -1 | awk '{$1=""; print}' )
                ## Failed attempt to remove timeout dependency:
                # DIRS=$(/usr/bin/env find $BASEDIR -depth $DEPTH -iname "*$SEARCH*" -type d \
                #            -exec stat -f "%m %N" {} 2>/dev/null \; & sleep 0.5; kill $! 2>/dev/null)
                # if [[ "$DIRS" != "" ]]; then
                #     DIR=$(echo "$DIRS"  | sort -n | tail -1 | awk '{$1=""; print}')
                # fi
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
        # TODO: test in sh and zsh
        debug "_find_cascade() argument:\"$*\""

        local hit=""

        # first try direct hit that permits spaces in tag names.
        if [ "$hit" != "" ]; then
            debug "_find_cascade() FOUND direct search: $hit"
            echo "$hit"
            return
        fi

        # else try cascade search
        if [ $# -gt 1 ]; then
            local i=0
            for var in "$@"; do
                i=$(($i+1))
                next_hit=$(egrep --max-count 1 -i "^$var${HUMANISM_C_TAG_DELIM}" "$HUMANISM_C_TAG_FILE" | \
                             awk -F"${HUMANISM_C_TAG_DELIM}" '{$1=""; print substr($0, 2)}')
                if [[ "$next_hit" == "" ]]; then
                    # filter couldn't be found. if this is last arg and prior args matched already, assume last is search
                    # else just assume this vailed and move on to the single search outside of the loop
                    if [ $i -eq $# ]; then
                        debug "_find_cascade() loop: arg is last and didn't find tag. run search: \"$hit\" \"$var\""
                        D=$(_find_filter "$hit" "$var")
                        if [[ "$D" != "" ]]; then
                            debug "_find_cascade() loop: found search on last arg: $D"
                            echo "$D"
                            return 0
                        else
                            debug "_find_cascade() loop: didnt find search on last arg: $var"
                            hit=""
                            break
                        fi
                    else
                        debug "_find_cascade() loop: no hit: $next_hit"
                        hit=""
                        break
                    fi
                else
                    # using grep -e may break on some embedded hosts
                    # could try: if [ "${new_hit#$hit}" != "$new_hit" ]; then
                    if echo "$next_hit" | grep -e "^$hit" &>/dev/null; then
                        debug "_find_cascade() loop: checked and \"$next_hit\" contains parent \"$hit\""
                        hit="$next_hit"
                    else
                        debug "_find_cascade() loop: checked and \"$next_hit\" DOES NOT contain parent \"$hit\""
                    fi
                fi
            done
        fi
        debug "_find_cascade() hit after loop: $hit"
        if [[ "$hit" != "" ]]; then
            echo "$hit"
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
        local hit
        hit=$(_find_cascade $*)
        if [[ "$hit" != "" ]]; then
            echo "."
            /usr/bin/env ls $flags "$hit"
        else
            /usr/bin/env ls $args
        fi
    }
    cd () {
        builtin cd "$@"
        _tag_manage "$@"
        pwd > ~/.cwd
    }
    c () {
        # # no args: go to last dir
        if [ $# -eq 0 ]; then
            cd "$(cat $HOME/.cwd)"
            return 0
        # # no args: print tags
        # if [ $# -eq 0 ]; then
        #     _tags_list
        elif [ "$1" = "list" ] || [ "$1" = "l" ]; then
            _tags_list
        # name pwd to tag name
        elif [ "$1" = "name" ] || [ "$1" = "n" ]; then
            if [ $# -gt 1 ]; then
                _tag_add "$(pwd)" "${@:2}"
                echo "\"${@:2}\" -> \"$(pwd)\""
            fi
        elif [ "$1" = "del" ] || [ "$1" = "d" ]; then
            if [ $# -eq 1 ]; then
                # delete by pwd
                _tag_delete "$(pwd)"
            else
                # delete by tag name
                _tag_delete "${@:2}"
            fi
        # if filter is path/directory just go to it. covers .., . and dir\ with/spaces, etc
        elif [ -d "$*" ]; then
            cd "$*"
            return 0
        # arg1: has no slashes so find it in the cwd
        else
            # now search history
            history_hit=$(_find_cascade $*)
            if [[ "$history_hit" != "" ]]; then
                echo "."
                builtin cd "$history_hit"
                pwd > ~/.cwd
                return 0
            fi
            D=$(_find_filter . "$*")
            if [[ "$D" != "" ]]; then
                builtin cd "$D"
                if [ $HUMANISM_C_TAG_AUTO -ne 0 ]; then
                    _tag_manage "$D" "$*"
                fi
                pwd > ~/.cwd
                return 0
            fi
            # now search backward and upward
            echo "<>"
            local FINDBASEDIR=""
            for i in $(seq 1 $HUMANISM_C_MAXDEPTH); do
                    FINDBASEDIR="../$FINDBASEDIR"
                    D=$(_find_filter "$FINDBASEDIR" "$*")
                    if [[ "$D" != "" ]]; then
                           builtin cd "$D"
                           if [ $HUMANISM_C_TAG_AUTO -ne 0 ]; then
                               _tag_manage "$D" "$*"
                           fi
                           pwd > ~/.cwd
                           break
                    fi
            done
        fi
    }
    # TODO: FIX To also show current files and dirs
    _compute_c_completion() {
      COMPREPLY=( $( grep "^$2" ~/.lcdrc | cut -d, -f 1 ) )
    }
    complete -o plusdirs -F _compute_c_completion c
    complete -o plusdirs -F _compute_c_completion l
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

        # export PS=`which ps`
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

    FOLLOWSYMLNK="-L"
    find () {
        LS=""
        if [[ "$1" == "-ls" ]]; then
            # i need -ls some times
            LS="-ls"
            shift;
        fi
        if [ $# -eq 0 ]; then
            /usr/bin/env find .
        elif [ $# -eq 1 ]; then
            # If it is a directory in cwd, file list
            if [ -d "$1" ]; then
                /usr/bin/env find $FOLLOWSYMLNK "$1" $LS
                # else fuzzy find
            else
                /usr/bin/env find $FOLLOWSYMLNK ./ -iname "*$1*" $LS 2>/dev/null
            fi
        elif [ $# -eq 2 ]; then
            /usr/bin/env find $FOLLOWSYMLNK "$1" -iname "*$2*" $LS 2>/dev/null
        else
            /usr/bin/env find $@ $LS
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
