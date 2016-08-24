#!/usr/bin/env bash

xdl_conf="some.daemon.ini"

#if [ $# -gt 0 -a $(id -un) != "www" ]; then
#    printf "Using sudo -u www...\n\n\n"
#    sudo -u www $0 $@
#    exit $?
#fi

. ./lib.launcher.sh
