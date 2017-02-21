#!/usr/bin/env bash

workingdir=$(cd "$(cd "$(dirname "${BASH_SOURCE}")"; pwd -P)"; pwd)
xdl_conf="${workingdir}/launcher.sample.ini"

. ${workingdir}/lib.launcher.sh
