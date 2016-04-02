#!/usr/bin/env bash

###### Debug + Error ${jar}rting #######################################################################
function error {
    local cal=`caller 0 | head -n 1`
    local fun=`echo $cal | awk '{ print $2; }'`
    local file=`echo $cal | awk '{ print $3; }'`; file=`basename $file`

    printf "\nERROR [%s > %s]: %s.\n" "$file" "$fun" "$1" >&2
    if [ "x$2" != "x" ]; then
        (
            printf "\nBASH_SOURCE : $BASH_SOURCE\n"
            printf "\nBacktrace:\n"
            caller 0
            printf "\n"
        ) >&2
        exit $2
    fi
}

function debug {
    if [ ${verbose} ]; then
        local cmd="printf"
        while (( "$#" )); do
            cmd="$cmd \"$1\""
            shift
        done
        eval $cmd
    fi
}

###### Daemon start & stop #######################################################################
function __findJAR {
    local jar="$1"
    local location
    if [ -f "$jar" ]; then
        error "no JAR" 1
    fi

    find "${workingdir}" -name "$jar" | head -n1
    return $?
}

function __getPID {
    echo "/tmp/`echo $1 | tr " " "_"`.pid"
}

###### Daemon start & stop #######################################################################
function check_alive {
    local PID_FILE="$1"
    if [ "xx$PID_FILE" = "xx" ]; then
        error "no PID_FILE" 1
    fi

    local ps_alive=1
    if [ -f "$PID_FILE" ] ; then
       if ps -p `cat ${PID_FILE}` >/dev/null 2>&1; then
          ps_alive=0;
       else
          rm -f ${PID_FILE}
       fi
    fi

    return ${ps_alive}
}

function startDaemon_java {
    local DAEMON="$1"
    local JRUN="$2"
    local DEBUG="${3:0}"
    if [ "xx$DAEMON" = "xx" ]; then
        error "no DAEMON" 1
    fi
    if [ "xx$JRUN" = "xx" ]; then
        error "no JRUN" 1
    fi

    if [ $(echo $JRUN | grep .jar | wc -l) -gt 0 ]; then
        # jar mode
        if ! [ -f "$JRUN" ]; then
            error "Can't find JAR_FILE: ${JAR_FILE}" 1
        fi
        JRUN="-jar $JRUN"
    fi

    local PID_FILE=`__getPID "$DAEMON"`
    if check_alive "$PID_FILE" ; then
        echo "$DAEMON is already running with PID `cat ${PID_FILE}`"
        return 1
    fi

    echo "Starting $DAEMON..."
    local LOG_PREFIX="$LOG_DIR/`echo ${DAEMON} | tr " " "_"`"
    if [ "${DEBUG}" -ne 1 ]; then
        nohup java $param $JRUN $arg > "${LOG_PREFIX}-output.log" 2> "${LOG_PREFIX}-error.log" &
        echo $! > ${PID_FILE}
        echo "Done [$!], see $DAEMON log at ${LOG_PREFIX}-*.log"
    else
        echo java $param $JRUN $arg
        java $param $JRUN $arg || return $?
    fi
}

function startDaemon_node {
    local DAEMON="$1"
    local NODE_FILE="$2"
    local DEBUG="${3:0}"
    if [ "xx$DAEMON" = "xx" ]; then
        error "no DAEMON" 1
    fi
    if [ "xx$NODE_FILE" = "xx" ]; then
        error "no JAR_FILE" 1
    fi
    if ! [ -f "$NODE_FILE" ]; then
        error "Can't find NODE_FILE: $NODE_FILE" 1
    fi

    local PID_FILE=`__getPID "$DAEMON"`
    if check_alive "$PID_FILE" ; then
        echo "$DAEMON is already running with PID `cat ${PID_FILE}`"
        return 1
    fi

    echo "Starting $DAEMON..."
    local LOG_PREFIX="$LOG_DIR/`echo ${DAEMON} | tr " " "_"`"
    if [ ${DEBUG} -ne 1 ]; then
        nohup node $param "$NODE_FILE" $arg > "${LOG_PREFIX}-output.log" 2> "${LOG_PREFIX}-error.log" &
        echo $! > ${PID_FILE}
        echo "Done [$!], see $DAEMON log at ${LOG_PREFIX}-*.log"
    else
        node $param "$NODE_FILE" $arg || return $?
    fi
}

function stopDaemon {
    local DAEMON="$1"
    local FORCE="${2:0}"
    if [ "xx$DAEMON" = "xx" ]; then
        error "no DAEMON" 1
    fi

    local PID_FILE=`__getPID "$DAEMON"`
    if check_alive "$PID_FILE"; then
        echo -n "Stopping $DAEMON [`cat ${PID_FILE}`]"
        kill `cat ${PID_FILE}`
        for i in {1..10}; do
            echo -n "."
            if check_alive "$PID_FILE"
                then sleep 1;
                else break;
            fi
        done
        echo

        if check_alive "$PID_FILE"; then
            echo "Can't stop $DAEMON"
            if [ ${FORCE} -eq 1 ]; then
                echo "Forcing KILL $DAEMON [`cat ${PID_FILE}`]"
                kill -KILL `cat ${PID_FILE}`
                if check_alive "$PID_FILE"; then
                    echo "$DAEMON doesn't want to die :("
                    return 1
                else
                    echo "Stopped"
                    rm -f ${PID_FILE}
                    return 0
                fi
            else
                return 1
            fi
        else
            echo "Stopped"
            rm -f ${PID_FILE}
            return 0
        fi
    else
        echo "$PID_FILE not found, nothing to stop."
    fi
    return 1
}