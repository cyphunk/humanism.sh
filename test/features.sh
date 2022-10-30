#!/bin/bash
#
#
# to debug execute:
# HUMANISM_DEBUG=1 features.sh
#
#


#
# Setup enviornment for tests
#

TESTDIR="/tmp/humanism-test"

mkdir $TESTDIR 2>/dev/null

HUMANISM_C_TAG_FILE="$TESTDIR/.lcdrc"
HUMANISM_DEBUG=${HUMANISM_DEBUG:=0}

rm -rf $HUMANISM_C_TAG_FILE

mkdir -p "$TESTDIR/feature-tests/first with spaces/files/src"
mkdir -p "$TESTDIR/feature-tests/second with spaces/files/src"
touch "$TESTDIR/feature-tests/first with spaces/files/src/foo1.txt"
touch "$TESTDIR/feature-tests/second with spaces/files/src/foo2.txt"


#
# Load humanism.sh with test enviornment
#

SH_SOURCE=${BASH_SOURCE:-$_}

if readlink "$SH_SOURCE" >/dev/null 2>&1; then
    HUMANISM_TEST_BASE="$(dirname $(readlink $SH_SOURCE))"
else
    HUMANISM_TEST_BASE="$(dirname $SH_SOURCE)"
fi

source "$HUMANISM_TEST_BASE/../humanism.sh"


#
# Helper functions
#

# check() shows the output of the history db
check () {
    echo -n "pwd "
    pwd | sed "s%$TESTDIR/%%"
    cc | sed "s%$TESTDIR/%%"
}
# assert <cmd> <cmd1> <cond1> [<cmd2> <cond2> ...]
# executes first cmd and then checks conditions with: cmdN | grep -E "$condN"
# examples:
#   assert "cd /etc" "pwd" "etc" "cat passwd" "root"
#   [passed] cd /etc
#   assert "cd /etc" "pwd" "etc" "cat passwd" "NONEXISTUSER"
#   [failed] cd /etc
assert () {
    cmd=$1; shift
    if [ $HUMANISM_DEBUG -ne 0 ]; then
        eval $cmd
    else
        eval $cmd >/dev/null 2>&1
    fi
    passed="passed";
    while [ 1 ]; do
        if [ $# -le 1 ]; then
            break
        fi
        $1 | grep -E "$2" >/dev/null #2>&1
        if [ $? -ne 0 ]; then
            passed="failed"
            if [ $HUMANISM_DEBUG -ne 0 ]; then
                tput setaf 1; echo -n "  ! "; tput sgr0; echo "assert $1 | grep -E \"$2\""
            fi
        else
            if [ $HUMANISM_DEBUG -ne 0 ]; then
                tput setaf 2; echo -n "  v "; tput sgr0; echo "assert $1 | grep -E \"$2\""
            fi
        fi
        shift 2
    done
    if [ "$passed" == "passed" ];
    then tput setaf 2
    else tput setaf 1
    fi
    echo "[$passed] $cmd"
    tput sgr0
}

savetag () {
    # tag creation and deletion is dependent on the timestamp on tag file
    if [ "$(uname)" = "Linux" ]; then
        touch -t $(date +%m%d%H%M -d '1 minute ago') "$HUMANISM_C_TAG_FILE"
    else
        oneminuteago=$(( $(date +%s) - 60 ))
        touch -t $(date -r $oneminuteago +%m%d%H%M) "$HUMANISM_C_TAG_FILE"
    fi
}


#
# Tests
#

echo -e "\nc <FiL tEr>"
builtin cd "$TESTDIR"
savetag
#      humanism cmd    check  expect result      check2                     expect
assert 'c first with'  'pwd' 'first with spaces' "cat $HUMANISM_C_TAG_FILE" 'first with,'
#check
# exit 0
echo -e "\nc <FiL tEr> - in parent tree"
builtin cd "$TESTDIR/feature-tests/first with spaces/"
savetag
assert 'c second with' 'pwd' 'second with spaces' "cat $HUMANISM_C_TAG_FILE" 'second with,'
#check
#exit 0


echo -e "\ncc <tag> - create tag"
builtin cd "$TESTDIR/feature-tests/first with spaces/"
assert 'cc firsttag' "cat $HUMANISM_C_TAG_FILE" 'firsttag,'


echo -e "\nc <FiLtEr> <FiLtEr>"
builtin cd "$TESTDIR"
savetag
assert 'c firs src' 'pwd' 'first with spaces' 'pwd' 'src' "cat $HUMANISM_C_TAG_FILE" 'src,'
#check
# TODO: I'm not sure i like that it adds a tag for the last filter. should it be the last filter or both as the tag. or none. Then again, maybe this is okay


echo -e "\nc <tag> <FiLtEr>"
builtin cd "$TESTDIR/feature-tests/first with spaces/"
cc d firsttag  >/dev/null 2>&1
cc firsttag  >/dev/null 2>&1
cc d src  >/dev/null 2>&1
builtin cd "$TESTDIR/feature-tests/second with spaces/"
savetag
assert 'c firsttag src' 'pwd' 'first with spaces' 'pwd' 'src' "cat $HUMANISM_C_TAG_FILE" 'src'
#check


echo -e "\nc <tag> <tag> <FiLtEr>"
builtin cd "$TESTDIR/feature-tests/first with spaces/"
cc d firsttag  >/dev/null 2>&1
cc firsttag  >/dev/null 2>&1
builtin cd "$TESTDIR/feature-tests/first with spaces/files"
cc d files >/dev/null 2>&1
cc files >/dev/null 2>&1
cc d src  >/dev/null 2>&1
builtin cd "$TESTDIR/feature-tests/second with spaces/"
savetag
assert 'c firsttag files src' 'pwd' 'first with spaces' 'pwd' 'src'
#check
