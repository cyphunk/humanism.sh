#!/bin/sh

# function used for testing availability of commands and flags
testflag () {
    if [ "$#" -eq 1 ] && command -v $1 >/dev/null 2>&1 ; then
        return 0
    elif $@ >/dev/null 2>&1 ; then
        return 0
    else
        echo "\"$@\" required"
        return 1
    fi
}

echo "Testing for required commands and command flags"


ERR=0
testflag /usr/bin/env find . -maxdepth 1 -mindepth 1                     || ERR=1
testflag /usr/bin/env find . -type d                                     || ERR=1
testflag /usr/bin/env find . -iname "\*testing\*"                        || ERR=1
if [ "Linux" = "$(uname)" ]; then
    testflag /usr/bin/env find . -maxdepth 1 -printf '%C@ '              || ERR=1
else
    testflag /usr/bin/env find . -maxdepth 1 -exec stat -f "%m %N" {} \; || ERR=1
fi
testflag tail  || ERR=1
testflag sort  || ERR=1
testflag awk   || ERR=1
testflag stat  || ERR=1
testflag touch || ERR=1
testflag date  || ERR=1
if [ "$ERR" -eq 1 ]; then echo "c will not load" ; else echo "c checked"; fi



ERR=0
testflag tail  || ERR=1
testflag head  || ERR=1
testflag sort  || ERR=1
testflag sed   || ERR=1
testflag cut   || ERR=1
testflag chmod || ERR=1
if [ "$ERR" -eq 1 ]; then echo "log will not load"; else echo "log checked"; fi



ERR=0
testflag /usr/bin/env ps -a                      || ERR=1
testflag /usr/bin/env ps -x                      || ERR=1
testflag /usr/bin/env ps -o pid,uid,user,command || ERR=1
if [ "Linux" = "$(uname)" ]; then
    testflag /usr/bin/env ps --forest            || ERR=1
fi
testflag egrep                                   || ERR=1
testflag awk                                     || ERR=1
if [ "$ERR" -eq 1 ]; then echo "ps will not load"; else echo "ps checked"; fi



ERR=0
testflag /usr/bin/env find . -iname "*test*" || ERR=1
if [ "$ERR" -eq 1 ]; then echo "find will not load"; else echo "find checked"; fi



ERR=0
if command -v strace >/dev/null 2>&1 || command -v dtruss >/dev/null 2>&1 ; then
    continue
else
    echo "\"strace\" or \"dtruss\" required"
    ERR=1
fi
testflag lsof                      || ERR=1
if [ "$ERR" -eq 1 ]; then echo "dbg will not load"; else echo "dbg checked"; fi



ERR=0
if [ "Linux" = "$(uname)" ]; then
    testflag apt-get   || ERR=1
    testflag apt-cache || ERR=1
    testflag apt-file  || ERR=1
elif [ "FreeBSD" = "$(uname)" ]; then
    testflag pkg       || ERR=1
elif [ "Darwin" = "$(uname)" ]; then
    testflag brew      || ERR=1
fi
if [ "$ERR" -eq 1 ]; then echo "ap will not load"; else echo "ap checked"; fi


ERR=0
testflag xxd || ERR=1
if command -v xxd >/dev/null 2>&1 || command -v od >/dev/null 2>&1 ; then
    continue
else
    echo "\"xxd\" or \"od\" required"
    ERR=1
fi
testflag tar || ERR=1
if [ "$ERR" -eq 1 ]; then echo "sshrc will not load"; else echo "sshrc checked"; fi


echo "Testing complete."
