#!/usr/bin/env bash

workingdir=$(cd "$(cd "$(dirname "${BASH_SOURCE}")"; pwd -P)"; pwd)
xdl_conf="${workingdir}/launcher.sample.ini"

#if [ $# -gt 0 -a $(id -un) != "www" ]; then
#    printf "Using sudo -u www...\n\n\n"
#    sudo -u www $0 $@
#    exit $?
#fi

. ${workingdir}/lib.launcher.sh
