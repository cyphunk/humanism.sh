#!/bin/bash


TESTDIR="/tmp/humanism-test"

mkdir $TESTDIR 2>/dev/null

HUMANISM_C_TAG_FILE="$TESTDIR/.lcdrc"
HUMANISM_DEBUG=${HUMANISM_DEBUG:=0}
HUMANISM_C_TAG_AUTO=1

rm -rf feature-tests $HUMANISM_C_TAG_FILE

mkdir --parents "$TESTDIR/feature-tests/first with spaces/files/src"
mkdir --parents "$TESTDIR/feature-tests/second with spaces/files/src"
touch "$TESTDIR/feature-tests/first with spaces/files/src/foo1.txt"
touch "$TESTDIR/feature-tests/second with spaces/files/src/foo2.txt"

SH_SOURCE=${BASH_SOURCE:-$_}

if readlink "$SH_SOURCE" >/dev/null 2>&1; then
    HUMANISM_TEST_BASE="$(dirname $(readlink $SH_SOURCE))"
else
    HUMANISM_TEST_BASE="$(dirname $SH_SOURCE)"
fi

source "$HUMANISM_TEST_BASE/../humanism.sh"



check () {
    echo -n "pwd "
    pwd | sed "s%$TESTDIR/%%"
    cc | sed "s%$TESTDIR/%%"
}
assert () {
    cmd=$1
    shift
    if [ $HUMANISM_DEBUG -ne 0 ]; then
        $cmd
    else
        $cmd >/dev/null 2>&1
    fi
    passed="passed";
    tput setaf 2
    while [ 1 ]; do
        if [ $# -le 1 ]; then
            break
        fi
        $1 | egrep "$2" >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            tput setaf 1
            passed="failed";
        fi
        shift 2
    done
    echo "[$passed] $cmd"
    tput setaf 7
}

savetag () {
    # tag creation and deletion is dependent on the timestamp on tag file
    touch -t $(date +%m%d%H%M -d '1 minute ago') "$HUMANISM_C_TAG_FILE"
}


#echo -e "HUMANISM_C_TAG_FILE=$HUMANISM_C_TAG_FILE\n"


echo -e "\nc <FiL tEr>"
builtin cd "$TESTDIR"
savetag
assert 'c first with'  'pwd' 'first with spaces' "cat $HUMANISM_C_TAG_FILE" 'first with,'
#check


echo -e "\nc <FiL tEr> - in parent tree"
builtin cd "$TESTDIR/feature-tests/first with spaces/"
savetag
assert 'c second with' 'pwd' 'second with spaces' "cat $HUMANISM_C_TAG_FILE" 'second with,'
#check


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


builtin cd "$TESTDIR"
echo -e "\nl <tag> <tag> <FiLtEr> - ls cascade"
assert 'l firsttag files src' 'l firsttag files src' 'foo1.txt'
# TODO: should l() auto create tags?
