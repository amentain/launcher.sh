#!/usr/bin/env bash

old_cwd=`pwd`
this_script="$0"
this=`basename $0`
workingdir=$(cd "$(cd "$(dirname "$this_script")"; pwd -P)"; pwd)

LOG_DIR="$workingdir/logs"

if [ $# -gt 0 -a $(id -un) != "www" ]; then
    printf "Using sudo -u www...\n\n\n"
    sudo -u www $0 $@
    exit $?
fi

daemons=(
    "sample"
)

artifacts=(
    "./jar/sample.jar"
)

params=(
    "-Xmx5120m -Xms512m"
)

args=(
    "arg"
)


cd "$workingdir"
. ./etc/launcher.lib-sh

function _exit {
    cd ${old_cwd}
    exit $1
}

function _usage {
    local daemon=$1
    cat <<EOF
BidStreet Daemon Launcher: ${daemon}
    Usage:
    ${this_script} start       - to start ${daemon} in background
    ${this_script} stop        - to stop ${daemon}

    ${this_script} run         - to start ${daemon} in the current console
    ${this_script} stop force  - to kill ${daemon}
EOF
    _exit 1
}

function _usageDaemon {
    local daemon=$1
    cat <<EOF
BidStreet Daemon Launcher

    daemons: ${daemons[@]}
          or all

    Usage:
    ${this_script} #daemon# start       - to start daemon in background
    ${this_script} #daemon# stop        - to stop daemon

    ${this_script} #daemon# run         - to start daemon in the current console
    ${this_script} #daemon# stop force  - to kill daemon
EOF
    _exit 1
}

function _getDaemon {
    local daemon=$1
    local d
    for ((d=0; d < ${#daemons[*]}; d++))
    do
        if [ "$daemon" = "${daemons[d]}" ]; then
            echo $d
            return 0;
        fi
    done
    return 1
}

function _runCommand {
    command_name=$1
    command_sub_name=$2

    case "$command_name" in
        start|run)
            debug=0
            if [ "$command_name" == "run" ]; then
                debug=1
            fi
            startDaemon_java "$daemon" "$jar" "$debug"
            return $?
        ;;

        stop)
            force=0
            if [ "command_sub_name" == "force" ]; then
                force=1
            fi

            stopDaemon "$daemon" "$force"
        ;;

        restart)
            force=0
            if [ "command_sub_name" == "force" ]; then
                force=1
            fi

            stopDaemon "$daemon" "$force"
            startDaemon_java "$daemon" "$jar" "0"
            return $?
        ;;

        *)
            _usage
        ;;
    esac
}

function _getDaemonParams() {
    local d=$1
    jar=${artifacts[d]}
    daemon=${daemons[d]}
    param=${params[d]}
    arg=${args[d]}
}

daemon=$1; shift
if [ "$daemon" = "all" ]; then
    for ((d=0; d < ${#daemons[*]}; d++))
    do
        _getDaemonParams ${d}
        _runCommand "$1" "$2"
    done
else
    d=`_getDaemon ${daemon}`
    if [ $? -ne 0 ]; then
        if [ "xx$daemon" != "xx" ]; then
            printf "no $daemon found\n\n\n"
        fi
        _usageDaemon
    fi

    _getDaemonParams ${d}
    _runCommand "$1" "$2"
fi
