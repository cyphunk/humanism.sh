# Humanism.sh

These commands attempt to introduce some humanism to POSIX users by providing
sensible defaults to basic commands and changing the basic functionality of some
so as to free neurons for use on something other than remembering command flags.
This effort ignores with intent the response "it only takes you one more second
to do it the normal way."

Examples: ``cd`` use typically includes only one argument: a directory. With
that assumption this seems absurd:
``cd ./to\ some\ directory``. And ``history`` and ``ps`` are
rarely used without ``grep``. ``find`` is typically used to fuzzy search for a
file name so why isn't ``-iname "*$@*"`` the default?

Some commands herein alter workflow more intrusively. The ``c`` command,
intended to replace cd, will search forward and backward looking for a directory
that matches any part of the argument filter. Though subtle this change makes
moving through the file systems similar to using command launchers found in
modern OS UI's (cmd+space osx, alt+F2 ubuntu). The ``ap`` command unifies
package searching, installation and information making finding needed
dependencies or files easier. And more.

Russell Stewart's sshrc is included so that these tools and environment can be
carried between hosts.

## Installation

To load all commands for each new terminal shell (bash/zsh/sh compatible) source
the file in your profile or bashrc:

    source humanism.sh

Alternatively you can load commands selectively ``source humanism.sh <cmd>``
or execute ``humanism.sh help`` to see list of commands.

You are likely use `ap` and in some cases `dbg` via sudo/root so link these
scripts into a PATH'ed bin:

    sudo ln -s <humanism.sh_path>/dbg /usr/local/bin
    sudo ln -s <humanism.sh_path>/ap.<version> /usr/local/bin

Commands have been tested on OSX, Ubuntu and FreeBSD and various virtual hosts
and embedded devices. If you find errors please execute the dependency test
script ``sh -x test/requirements.sh`` and submit an issue on github.

## Use

### c (cd)

    c            go to last dir
    c <FiLteR>   go to path, if not in cwd search forward and backward for
                 *FiLtEr* in tree

![example c use](/examples/c.gif)

Details:

    c <fIlTeR>            go to path or find and goto filter  
                          1. if filter is path, goto  
                          2. if filter is name in tag db, goto  
                          3. if filter found under cwd, goto  
                          4. if filter found above cwd, goto
    c <fIlTeR> <fIlTeR>   filter cascading. find filter, then Nth filter under it  
    c <tag> <tag>         tag cascading
    c <tag> <fIlTeR>      combined. many tags, one filter  
    l <tag> <fIlTeR>      ls that adheres to all of the above  

Managing Tags:

Tags get created either manually using these commands or automatically when a
``c fIlTeR`` is found.

    cc                    list tags  
    cc <tag>              add/remove/rename <tag> for pwd  
                          prompt to delete if <tag> exists  
    cc d   <tag>  
    cc del <tag>          explicit delete  

To disable auto tagging set ``HUMANISM_C_TAG_AUTO=0`` before sourcing humanism.sh

### find

    find <filter>          find *FiLtEr* anywhere under cwd
    find <path> <filter>   find *FiLtEr* anywhere under path
    find $1 $2 $3 ...      pass through to normal find

![example find use](/examples/find.gif)


### history

    history            list
    history <filter>   greped history

![example history use](/examples/history.gif)

### ps

    ps                            list
    ps <filter>                   filtered
    ps <filter> | killps [-SIG]   kill procs

### log

Used to create a record of work by appending commands and messages to ./run.sh
from bash history.

    log          	   show recent commands and select which are recorded
    log some message   append echo message to run.sh
    log <N>      	   append Nth cmd from last. e.g. ``log 1``    adds last cmd


### ap

Unify apt-get, apt-cache and dpkg on Linux, homebrew on OSX or pkgng on Freebsd.
Makes searching for needed files or packages a bit easier.

    install)  
    Install package

    reinstall)  
    Re-install package

    remove)  
    Uninstall and purge of all deps no longer required

    updatesecurity)  
    Install security updates

    search)  
    Show packages available or already installed

    ownerof)  
    Show package for file

    ineed)  
    Show packages that would provide a file if installed

    ineedbadly)  
    Show any package that contains string

    info)  
    information about package

    list)  
    show files installed by package

    *)  
    pass through any other command on to apt-get

### dbg

Unify strace|dtruss and lsof.

    trace)  
    Exec cmd and strace all child processes

    openfiles)  
    Show open files of an already running processes and its children, by name

    fileprocs)  
    Show pid's touching file

    libtree)  
    print lib dependency tree for $1 using only strings  
      dbg libtree [ignorelibs] <TARGET>  
      example:  
      dbg libtree [ld.so.1 libc.so libpthread.so.0 libc.so.6] <TARGET>  

### sshrc

carry all of the above commands with you. Will source ``myrc`` file from
humanism.sh base directory, if it exists. Personally I've set ``alias ssh=sshrc``
in myrc so that I don't forget to carry this with me.
