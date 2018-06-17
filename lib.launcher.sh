#!/usr/bin/env bash

: ${debug=0}
: ${verbose=0}
: ${this_script="$0"}
: ${workingdir=$(cd "$(cd "$(dirname "$this_script")"; pwd -P)"; pwd)}

: ${xdl_tmp="/tmp/launcher.sh"}
: ${xdl_log_dir="${workingdir}/logs"}
: ${xdl_conf="launcher.sample.ini"}

: ${xdl_api_mode=0}

xdl_home="https://github.com/amentain/launcher.sh"
xdl_latest_release="https://api.github.com/repos/amentain/launcher.sh/releases/latest"
xdl_latest_release_cacheTime=$(( 2 * 60 * 60 ))
xdl_version="0.5.0"

xdl_install_path="${BASH_SOURCE}"

###### Debug + Error reporting ###########################################################################
function error {
    local call=`caller 0 | head -n 1`
    local func=`echo ${call} | awk '{ print $2; }'`
    local file=`echo ${call} | awk '{ print $3; }'`; file=`basename ${file}`

    printf "\nERROR [%s > %s]: %s.\n" "$file" "$func" "$1" >&2
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
        eval ${cmd}
    fi
}

function bytes2human() {
    # converts a byte count to a human readable format in IEC binary notation (base-1024), rounded to two decimal places for anything larger than a byte. switchable to padded format and base-1000 if desired.
    local L_BYTES="${1:-0}"
    local L_PAD="${2:-no}"
    local L_BASE="${3:-1024}"
    BYTESTOHUMAN_RESULT=$(awk -v bytes="${L_BYTES}" -v pad="${L_PAD}" -v base="${L_BASE}" 'function human(x, pad, base) {
         if(base!=1024)base=1000
         basesuf=(base==1024)?"iB":"B"

         s="BKMGTEPYZ"
         while (x>=base && length(s)>1)
               {x/=base; s=substr(s,2)}
         s=substr(s,1,1)

         xf=(pad=="yes") ? ((s=="B")?"%5d   ":"%8.2f") : ((s=="B")?"%d":"%.2f")
         s=(s!="B") ? (s basesuf) : ((pad=="no") ? s : ((basesuf=="iB")?(s "  "):(s " ")))

         return sprintf( (xf " %s\n"), x, s)
      }
      BEGIN{print human(bytes, pad, base)}')
    return $?
}

###### INI #############################################################################################
function __ini_get()
{
    local inifile="$1"
    local prefix="$2"

    while IFS='= ' read var val
    do
        if [[ ${var} == \[*] ]]
        then
            section=`echo "$var" | tr -d "[] "`
        elif [[ "${val}" ]]
        then
            if [ $(echo "${var}" | grep -oE '[#;]+' | wc -l) -eq 0 ]; then
                eval ${prefix}${section}_${var}="${val}"
            fi
        fi
    done < ${inifile}
}

function __ini_get_sections
{
    local inifile="$1"
    local prefix="$2"

    while IFS='= ' read var val
    do
        if [[ ${var} == \[*] ]]
        then
            section=`echo "$var" | tr -d "[] "`
            echo ${prefix}${section}
        fi
    done < ${inifile}
}

###### Daemon start & stop ###############################################################################
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
    echo "/tmp/`echo $1 | tr -d '"' | tr ' ' '_'`.pid"
}

###### Daemon start & stop ###############################################################################
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
    local DEBUG=${3:0}
    if [ "xx$DAEMON" = "xx" ]; then
        error "no DAEMON" 1
    fi
    if [ "xx$JRUN" = "xx" ]; then
        error "no JRUN" 1
    fi

    if [ $(echo ${JRUN} | grep .jar | wc -l) -gt 0 ]; then
        # jar mode
        if ! [ -f "$JRUN" ]; then
            error "Can't find JAR: ${JRUN}" 1
        fi
        JRUN="-jar $JRUN"
    fi

    local PID_FILE=`__getPID "$DAEMON"`
    if check_alive "$PID_FILE" ; then
        echo "$DAEMON is already running with PID `cat ${PID_FILE}`"
        return 1
    fi

    echo "Starting $DAEMON..."
    local LOG_PREFIX="${xdl_log_dir}/`echo ${DAEMON} | tr " " "_"`"
    if [ ${DEBUG} -ne 1 ]; then
        rotateLogs "${LOG_PREFIX}"

        nohup java $params $JRUN $args > "${LOG_PREFIX}-output.log" 2> "${LOG_PREFIX}-error.log" &
        echo $! > ${PID_FILE}
        echo "Done [$!], see $DAEMON log at ${LOG_PREFIX}-*.log"
    else
        echo java $params $JRUN $args
        java $params $JRUN $args || return $?
    fi
}

function startDaemon_node {
    local DAEMON="$1"
    local NODE_FILE="$2"
    local DEBUG=${3:0}
    if [ "xx$DAEMON" = "xx" ]; then
        error "no DAEMON" 1
    fi
    if [ "xx$NODE_FILE" = "xx" ]; then
        error "no NODE_FILE" 1
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
    local LOG_PREFIX="${xdl_log_dir}/`echo ${DAEMON} | tr " " "_"`"
    if [ ${DEBUG} -ne 1 ]; then
        rotateLogs "${LOG_PREFIX}"

        nohup node $params "$NODE_FILE" $args > "${LOG_PREFIX}-output.log" 2> "${LOG_PREFIX}-error.log" &
        echo $! > ${PID_FILE}
        echo "Done [$!], see $DAEMON log at ${LOG_PREFIX}-*.log"
    else
        echo node $params "$NODE_FILE" $args
        node $params "$NODE_FILE" $args || return $?
    fi
}

function startDaemon_plain {
    local DAEMON="$1"
    local DAEMON_FILE="$2"
    local DEBUG=${3:0}
    if [ "xx$DAEMON" = "xx" ]; then
        error "no DAEMON" 1
    fi
    if [ "xx$DAEMON_FILE" = "xx" ]; then
        error "no DAEMON_FILE" 1
    fi
    if ! [ -f "$DAEMON_FILE" ]; then
        error "Can't find DAEMON_FILE: $DAEMON_FILE" 1
    fi

    local PID_FILE=`__getPID "$DAEMON"`
    if check_alive "$PID_FILE" ; then
        echo "$DAEMON is already running with PID `cat ${PID_FILE}`"
        return 1
    fi

    echo "Starting $DAEMON..."
    local LOG_PREFIX="${xdl_log_dir}/`echo ${DAEMON} | tr " " "_"`"
    if [ ${DEBUG} -ne 1 ]; then
        rotateLogs "${LOG_PREFIX}"

        nohup ${DAEMON_FILE} ${params} ${args} > "${LOG_PREFIX}-output.log" 2> "${LOG_PREFIX}-error.log" &
        echo $! > ${PID_FILE}
        echo "Done [$!], see $DAEMON log at ${LOG_PREFIX}-*.log"
    else
        echo ${DAEMON_FILE} $params $args || return $?
        ${DAEMON_FILE} $params $args || return $?
    fi
}

function statusDaemon {
    local DAEMON=`echo $1 | sed 's/"//g'`
    if [ "xx$DAEMON" = "xx" ]; then
        error "no DAEMON" 1
    fi

    if [ "xx${XDL_STATUS_HEADER}" = "xx" ]; then
        statusHeader
    fi

    local lenDif=$(( ${XDL_STATUS_MAXLEN} - ${#DAEMON} ))
    local PID_FILE=`__getPID "$DAEMON"`
    if check_alive "$PID_FILE"; then
        local pCPU=$(ps -o "%cpu" -p `cat ${PID_FILE}` | tail -n1)
        local pMEM=$(ps -o "%mem" -p `cat ${PID_FILE}` | tail -n1)
        local pRSS=$(ps -o "rss"  -p `cat ${PID_FILE}` | tail -n1)

        bytes2human $((${pRSS} * 1024))
        printf "%s%${lenDif}s\t%d\t%s\t%s\t%s\n" "${DAEMON}" " " "`cat ${PID_FILE}`" "${pCPU}" "${pMEM}" "${BYTESTOHUMAN_RESULT}"
    else
        printf "%s%${lenDif}s\t%s\n" "${DAEMON}" " " "--"
    fi
    return 1
}

function statusHeader {
    XDL_STATUS_HEADER=yes

    local ttl="DAEMON"
    local maxLen=`__getMaxDaemonLength`
    if [ ${maxLen} -lt ${#ttl} ]; then
        maxLen=${#ttl}
    fi
    maxLen=$(( (($maxLen / 2) + 1) * 2 ))

    local lenDif=$(( maxLen - ${#ttl} ))
    printf "%s%${lenDif}s\t%s\t%s\t%s\t%s\n" "${ttl}" " " "PID" "CPU,%" "MEM,%" "RSS,bytes"

    XDL_STATUS_MAXLEN=${maxLen}
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

function rotateLogs {
    local LOG_PREFIX=$1
    local dtNow=$(date +%F_%T)

    if [ -f "${LOG_PREFIX}-output.log" ]; then
        mv -f "${LOG_PREFIX}-output.log" "${LOG_PREFIX}-output.${dtNow}.log"
        rm -f `ls ${LOG_PREFIX}-output.*.log | sort -r | sed 1,5d`
    fi

    if [ -f "${LOG_PREFIX}-error.log" ]; then
        mv -f "${LOG_PREFIX}-error.log" "${LOG_PREFIX}-error.${dtNow}.log"
        rm -f `ls ${LOG_PREFIX}-error.*.log  | sort -r | sed 1,5d`
    fi
}

###### Updated ###########################################################################################

function version_gt { test "$(echo "$@" | tr " " "\n" | sort -g | tail -n 1)" != "$1"; }

function __getLatestRelease {
    local cache="${xdl_tmp}/release.json"
    local upgrade=$1
    local force=$2

    if [ "${upgrade}" != "1" ]; then
        upgrade=0
    fi

    if [ "${force}" = "force" ]; then
        rm -f "${cache}"
    fi

    if [ -f "${cache}" ]; then
        local now=`date +%s`
        local cacheTime=`__getMTime "${cache}"`
        if [ $(($now - $cacheTime)) -gt ${xdl_latest_release_cacheTime} ]; then
            rm -f "${cache}"
        fi
    fi

    if ! [ -f "${cache}" ]; then
        wget -q -O "${cache}" "${xdl_latest_release}" || error "Can't update sorry" 1
        chmod 666 "${cache}" # global writable
        touch "${cache}" # set current date
    fi

    local rName=$(cat ${cache} | grep -F '"name":' | head -n1 | awk -F':' '{ print $2; }' | xargs | sed 's/,//g')
    local rTagName=$(cat ${cache} | grep -F '"tag_name":' | awk -F':' '{ print $2; }' | sed -E 's/[," ]//g')
    local rDescribe=$(cat ${cache} | grep -F '"body":' | awk -F':' '{ print $2; }' | xargs)
    local rURL=$(cat ${cache} | grep -F '"html_url":' | head -n1 | grep -oE 'http[^"]+')
    local dURL=$(cat ${cache} | grep -F '"browser_download_url":' | head -n1 | grep -oE 'http[^"]+')

    if version_gt ${xdl_version} ${rTagName}; then
        echo "New Release found!"
        echo
        printf "[%s] %s\n" "$rTagName" "$rName"
        echo -e ${rDescribe}
        echo
        echo ${rURL}
        echo ${dURL}

        if [ "${upgrade}" -eq 1 ]; then
            wget -q -O - "${dURL}" | bunzip2 -c > ${xdl_install_path}
        fi
    else
        echo "Already up to date"
    fi
}

function __getMTime {
    local fName="${1}"

    if [ ! -f "${fName}" ]; then
        echo "Can't read file ${fName}" >&2
        echo -1
        exit 1
    fi

    if [ $(uname) = "FreeBSD" -o $(uname) = "Darwin" ]; then
        stat -f '%Sm' -t '%s' "${fName}"
    else
        date +%s -r "${fName}"
    fi
}

###### Daemon helper #####################################################################################
function __getAvailableDaemons {

    local available_daemons=""
    for d in `__ini_get_sections "${xdl_conf}"`
    do
        local enabled=1
        local if_exists=""
        eval if_exists=\${xdml_${d}_enable_if_exist}

        if [ "xx${if_exists}" != "xx" ]; then
            if ! [ -e "${if_exists}" ]; then
                local enabled=0
            fi
        fi

        if [ ${enabled} -eq 1 ]; then
            available_daemons="${available_daemons} ${d}"
        fi
    done

    echo ${available_daemons}
}

function __getMaxDaemonLength {
    if [ "xx${XDL_MAX_DAEMON_LENGTH}" != "xx" ]; then
        echo ${XDL_MAX_DAEMON_LENGTH}
        exit 0
    fi

    local len=1
    for d in `__getAvailableDaemons`
    do
        local l=${#d}
        if [ ${len} -lt ${l} ]; then
            len=${l}
        fi
    done
    XDL_MAX_DAEMON_LENGTH=${len}
    echo ${len}
}

function __checkDaemon {
    for d in `__getAvailableDaemons`
    do
        if [ ${d} == "" ]; then
            return 0
        fi
    done
    return 1
}

function __getDaemonParams() {
    local d=$1
    daemon=${d}
    eval owner=\${xdml_${d}_owner}
    eval artifact=\${xdml_${d}_artifact}
    eval node_file=\${xdml_${d}_node_file}
    eval daemon_file=\${xdml_${d}_daemon_file}
    eval params=\${xdml_${d}_params}
    eval args=\${xdml_${d}_args}

    if [ -z "${artifact}" ]; then
        if [ -z "${node_file}" ]; then
            runner="startDaemon_plain ${daemon} ${daemon_file}";
        else
            runner="startDaemon_node ${daemon} ${node_file}";
        fi
    else
        runner="startDaemon_java ${daemon} ${artifact}";
    fi
}

function __showVersion {
    echo "Xeenon's Daemon Launcher v${xdl_version}"
    echo
}

function __showUsage {
    local dmCount=${dmCount:-0}

    __showVersion

    if [ ${dmCount} -eq 0 ]; then
        echo "no daemons available"
        echo "or no daemons configured"
        echo "${xdl_home}"
        echo
        exit 1
    fi

    local cmd="${this_script}"
    if [ ${dmCount} -gt 1 ]; then
        cmd="${cmd} #daemon#"
        printf "daemons:\n   ${dmList}\n"
        printf "   or all\n"
    else
        printf "daemon: ${dmList}\n"
    fi

    echo
    echo "Usage:"
    echo "${cmd} start       - to start daemon in background"
    echo "${cmd} stop        - to stop daemon"
    echo "${cmd} status      - displays daemon status"
    echo "${cmd} restart     - to stop and start daemon"
    echo
    echo "${cmd} run         - to start daemon in the current console"
    echo "${cmd} stop force  - to kill daemon"
    echo
    echo "Misc:"
    echo "${this_script} update  - checks for launcher updates"
    echo "${this_script} upgrade - upgrade current launcher installation"
    echo "${this_script} version - show version"

    exit 1
}

###### Command runner ####################################################################################
function __runDaemonCommand {
    local command_name=$1
    local command_sub_name=$2
    local run_cmd_1=""
    local run_cmd_2=""
    local debug=0

    case "$command_name" in
        start|run)
            if [ "$command_name" == "run" ]; then
                debug=1
            fi
            run_cmd_1="${runner} $debug"
        ;;

        status)
            run_cmd_1="statusDaemon \"$daemon\""
        ;;

        stop)
            force=0
            if [ "${command_sub_name}" == "force" ]; then
                force=1
            fi

            run_cmd_1="stopDaemon \"$daemon\" \"$force\""
        ;;

        restart)
            force=0
            if [ "command_sub_name" == "force" ]; then
                force=1
            fi

            run_cmd_1="stopDaemon \"$daemon\" \"$force\""
            run_cmd_2="${runner} $debug"
        ;;

        *)
            __showUsage
            return 1
        ;;
    esac

    if [ "${command_name}" = "status" -o "xx${owner}" = "xx" -o $(id -un) = "${owner}" ];
    then
        ${run_cmd_1}
        ${run_cmd_2}
        return $?
    else
        printf "Using sudo -u ${owner}...\n"
        sudo -H -u ${owner} bash <<RUN
debug="${debug}"
verbose="${verbose}"
this_script="${this_script}"
workingdir="${workingdir}"

xdl_tmp="${xdl_tmp}"
xdl_log_dir="${xdl_log_dir}"
xdl_conf="${xdl_conf}"

xdl_api_mode=1

. ${xdl_install_path}

${run_cmd_1}
${run_cmd_2}
exit \$?
RUN
        return $?
    fi
}

# home sweet home
cd ${workingdir}

# api or not api?
if [ ${xdl_api_mode} -ne 1 ]; then
    # Testing tmp access
    mkdir -p ${xdl_tmp} || error "TMP is not writable: can't write to ${xdl_tmp}" 2
    chmod 777 ${xdl_tmp} # global writable

    # Check & parse ini
    dmList=""
    dmCount=0
    if [ -f "${xdl_conf}" ]; then
        __ini_get "${xdl_conf}" "xdml_"
        dmList=`__getAvailableDaemons`
        dmCount=$(( `echo ${dmList} | wc -w` * 1 ))
    fi

    # Check input params
    if [ "xx$1" == "xx" ]; then
        __showUsage
    fi

    first=$1; shift
    case "${first}" in
        "all")
            # Check available daemons
            if [ ${dmCount} -eq 0 ]; then
                __showUsage
            fi

            for d in ${dmList}
            do
                __getDaemonParams ${d}
                __runDaemonCommand $@
            done
        ;;

        "update")
            __getLatestRelease 0 $@
        ;;

        "upgrade")
            __getLatestRelease 1 $@
        ;;

        "version")
            __showVersion
        ;;

        "install")
            echo "Not implemented"
            exit 1
        ;;

        *)
            # Check available daemons
            if [ ${dmCount} -eq 0 ]; then
                __showUsage
            fi

            if [ ${dmCount} -eq 1 ];
            then
                __getDaemonParams ${dmList}
                if [ "${first}" == "${dmList}" ]; then
                    __runDaemonCommand $@
                else
                    __runDaemonCommand "${first}" $@
                fi
            else

                if __checkDaemon ${first}; then
                    printf "no daemon \"${first}\" found\n\n\n"
                    __showUsage
                fi

                __getDaemonParams ${first}
                __runDaemonCommand $@
            fi
        ;;
    esac
fi
