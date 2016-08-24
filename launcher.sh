#!/usr/bin/env bash

#daemon_conf="kavanga-dsp.ini"


this_script="$0"
this=`basename $0`
workingdir=$(cd "$(cd "$(dirname "$this_script")"; pwd -P)"; pwd)

LOG_DIR="$workingdir/logs"

#if [ $# -gt 0 -a $(id -un) != "www" ]; then
#    printf "Using sudo -u www...\n\n\n"
#    sudo -u www $0 $@
#    exit $?
#fi

cd "$workingdir"
. ./lib.launcher.sh
