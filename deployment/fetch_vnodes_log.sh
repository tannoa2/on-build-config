#!/bin/bash -x
set +e

Usage(){
    set +x
    echo "function: this script is used to take vnc record and fetch sol log from virtual nodes"
    echo "usage: $0 [options] [arguments]"
    echo "  options:"
    echo "    -h     : Give this help list"
    echo "    start  : Start to take vnc record and fetch sol log"
    echo "    stop   : Stop taking vnc record and fetching sol log"
    echo "    mandatory arguments:"
    echo "      -l, --LOG_DIR: The directory of flv files and log files"
    echo "    Optional Arguments:"
    echo "      -b, --ON_BUILD_CONFIG_DIR: The directory of on-build-config. It's required for start"
    echo "      -a, --BMC_ACCOUNT_LIST: The list of bmc account, such as 'admin:admin root:root'. It's required for start"
    set -x
}

vncRecordStart(){
    pushd ${ON_BUILD_CONFIG_DIR}/deployment
    export fname_prefix="vNode"
    if [ ! -z $BUILD_ID ]; then
        export fname_prefix=${fname_prefix}_b${BUILD_ID}
    fi
    bash vnc_record.sh "${BMC_ACCOUNT_LIST}" ${LOG_DIR} $fname_prefix &
    popd
}

vncRecordStop(){
    #sleep 2 sec to ensure FLV finishes the disk I/O before VM destroyed
    pkill -f flvrec.py
    sleep 2
}

fetchSolLogStart(){
    pushd ${ON_BUILD_CONFIG_DIR}/deployment
    bash generate_sol_log.sh "${BMC_ACCOUNT_LIST}" ${LOG_DIR} > ${LOG_DIR}/sol_script.log &
    popd
}

decodeSolLog(){
    # Convert raw sol logs into html by ansi2html tool
    pushd ${LOG_DIR}
    for file in `ls *sol.log.raw`; do
        # decode to utf-8 before, because ansi2html will broke when finding invalid char
        iconv -f "windows-1252" -t "UTF-8" $file -o new_$file
        if [ -f new_$file ];then
            ansi2html < new_$file > ${LOG_DIR}/${file%.*}
            rm $file
            rm new_$file
        fi
    done
    popd
}

fetchSolLogStop(){
    pkill -f SCREEN
}

###################################################################
#
#  Parse and check Arguments
#
##################################################################
parseArguments(){
    while [ "$1" != "" ]; do
        case $1 in
            -l | --LOG_DIR )                shift
                                            LOG_DIR=$1
                                            ;;
            -a | --BMC_ACCOUNT_LIST )       shift
                                            BMC_ACCOUNT_LIST=$1
                                            ;;
            -b | --ON_BUILD_CONFIG_DIR )    shift
                                            ON_BUILD_CONFIG_DIR=$1
                                            ;;
            * )                             Usage
                                            exit 1
        esac
        shift
    done

    if [ ! -n "${LOG_DIR}" ]; then
        echo "[Error]Arguments -l | --LOG_DIR is required"
        Usage
        exit 1
    fi

    if [ ${OPERATION,,} == "start" ]; then
        if [ ! -n "${BMC_ACCOUNT_LIST}" ]; then
            echo "[Error]Arguments -a | --BMC_ACCOUNT_LIST is required"
            Usage
            exit 1
        fi
        if [ ! -n "${ON_BUILD_CONFIG_DIR}" ]; then
            echo "[Error]Arguments -b | --ON_BUILD_CONFIG_DIR is required"
            Usage
            exit 1
        fi
    fi

    mkdir -p ${LOG_DIR}
}


######################################################
#
# Main
#
######################################################
OPERATION=$1
case "$1" in
  start)
      shift
      parseArguments $@
      vncRecordStart
      fetchSolLogStart
  ;;

  stop)
      shift
      parseArguments $@
      vncRecordStop
      fetchSolLogStop
      decodeSolLog
  ;;

  -h|--help|help)
    Usage
    exit 0
  ;;

  *)
    Usage
    exit 1
  ;;
esac

