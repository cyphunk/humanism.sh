#!/usr/bin/env bash
# source $0                        loads all functions
# source $0 <func> [func ...]    load specific functions
# $0 help                        function list and description

#
# Common aliases
#

SH_SOURCE=${BASH_SOURCE:-$_}

if ! shopt -s expand_aliases >/dev/null 2>&1; then
    setopt aliases >/dev/null 2>&1
fi

# have grep --color?
if echo "x" | grep --color x >/dev/null 2>&1; then
    alias egrep='egrep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias grep='grep --color=auto'
fi
# have ls --color=auto?
if ls --color=auto >/dev/null 2>&1; then
    alias ls='ls --color=auto'
fi
alias s='sudo '
# carry aliases by adding space wiki.archlinux.org/index.php/Sudo#Passing_aliases
alias sudo='sudo '
alias ...='cd ../../'
alias ....='cd ../../../'
alias .....='cd ../../../../'

#
# Iterate over arguments and load each function
#

# If no argument defined load all
if [ $# -eq 0 ]; then
    set  -- c log history ps find usage_self ap dbg sshrc $@
fi

if readlink "$SH_SOURCE" >/dev/null 2>&1; then
    export HUMANISM_BASE="$(dirname $(readlink $SH_SOURCE))"
else
    export HUMANISM_BASE="$(dirname $SH_SOURCE)"
fi
OS="$(uname)"

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
  #   recursive cd  (source in .bash_aliases)
  #
  #   c            go to last dir
  #   c path       go to path, if not in cwd search forward and backward for
  #                *PaTh* in tree

    # (optional) use env var HUMANISM_CD_DEPTH for maxdepth
    if [ -z $HUMANISM_CD_DEPTH ]; then
        HUMANISM_CD_DEPTH=8
    fi
    # timeout cmd used to set max time limit to search
    if command -v timeout >/dev/null 2>&1 ; then
        TIMEOUT="timeout"
    elif command -v gtimeout >/dev/null 2>&1 ; then
        TIMEOUT="gtimeout"
    else
        echo "error: c/cd requires timeout cmd"
    fi
    dir_in_tree () {
        local BASEDIR="$1"
        local SEARCH="${@:2}"
        local DEPTH=1
        local DIR
        for DEPTH in $(seq 1 $HUMANISM_CD_DEPTH); do
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
    c () {
        # no args: go to last dir
        if [ $# -eq 0 ]; then
            if [ -f ~/.cwd ]; then
                    builtin cd "`cat ~/.cwd`"
            else
                    builtin cd
            fi
            pwd > ~/.cwd
            return 0
        # if filter is path/directory just go to it. covers .., . and dir\ with/spaces, etc
        elif [ -d "$*" ]; then
                builtin cd "$*"
                pwd > ~/.cwd
                return 0
        # arg1: has no slashes so find it in the cwd
        else
            D=$(dir_in_tree . "$*")
            if [[ "$D" != "" ]]; then
                builtin cd "$D"
                pwd > ~/.cwd
                return 0
            fi
            # now search backward and upward
            echo "<>"
            local FINDBASEDIR=""
            for i in $(seq 1 $HUMANISM_CD_DEPTH); do
                    FINDBASEDIR="../$FINDBASEDIR"
                    D=$(dir_in_tree "$FINDBASEDIR" "$*")
                    if [[ "$D" != "" ]]; then
                           builtin cd "$D"
                           pwd > ~/.cwd
                           break
                    fi
            done
        fi
        }
        cd () {
            builtin cd "$@"
            pwd > ~/.cwd
        }
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
                                echo "#!/bin/bash">$HUMANISM_LOG
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
        if [ $# -eq 0 ]; then
            /usr/bin/env find .
        elif [ $# -eq 1 ]; then
            # If it is a directory in cwd, file list
            if [ -d "$1" ]; then
                /usr/bin/env find $FOLLOWSYMLNK "$1"
                # else fuzzy find
            else
                /usr/bin/env find $FOLLOWSYMLNK ./ -iname "*$1*" 2>/dev/null
            fi
        elif [ $# -eq 2 ]; then
            /usr/bin/env find $FOLLOWSYMLNK "$1" -iname "*$2*" 2>/dev/null
        else
            /usr/bin/env find $@
        fi
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
            grep -A 10 '^  *[^ \(\*]*)' $0 | egrep -B 1 '^  #' | sed 's/#//' | sed 's/--//g'
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
