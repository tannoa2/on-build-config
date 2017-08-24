#!/bin/bash -e
set -x
#############################################
#
# Global Variable
############################################


#########################################
#
#  Usage
#
#########################################
Usage(){
    echo "function: this script is used to deploy rackhd within ova"
    echo "usage: $0 [options] [arguments]"
    echo "  options:"
    echo "    -h     : give this help list"
    echo "    cleanup: remove the existing rackhd ova vm"
    echo "    deploy : deploy a rackhd ova and run it"
    echo "    exportLog : export log file from ova to target log directory"
    echo "    mandatory arguments:"
    echo "      -w, --WORKSPACE: the directory of workspace( where the code will be cloned to and staging folder), it's required for deploy"
    echo "      -p, --SUDO_PASSWORD: password of current user which has sudo privilege, it's required."
    echo "      -l, --LOG_DIR: , The directory for putting log file. It's required for exportLog."
    echo "      -i, --OVA_IMAGE_PATH: The path of rackhd ova"
    echo "                       It can be a local ova file path or a ova url."
    echo "      -n, --NODE_NAME: The VM that connected to rackhd ova"
    echo "      -h, --ESXI_HOST: The host ip of Esxi that rackhd ova deployed to."
    echo "      -eu, --ESXI_USER: The username of Esxi that rackhd ova deployed to."
    echo "      -ep, --ESXI_PASS: The password of Esxi that rackhd ova deployed to."
    echo "      -d, --DATASTORE: Datastore name for ova deployment."
    echo "      -o, --OVA_INTERNAL_IP: The ova eth1 IP for ssh login or other usage."
    echo "      -g, --OVA_GATEWAY: The gateway IP for ova vm."
    echo "      -ni, --OVA_NET_INTERFACE: The netcard name of ova vm which to connect gateway."
    echo "      -ou, --OVA_USER: The username of OVA."
    echo "      -op, --OVA_PASSWORD: The password of OVA."
    echo "    Optional Arguments:"
    echo "      -b, --ON_BUILD_CONFIG_DIR: The directory of repository on-build-config"
    echo "                       If it's not provided, the script will clone the latest repository on-build-config under $WORKSPACE"
    echo "      -e EXTERNAL_VSWITCH: The vswith which connects to external network with dhcp server.
                                  If set this variable, ova eht0 will be connected to this vswitch."
    echo "      -s, --DNS_SERVER_IP: The dns server ip for ova vm."
}

############################################
#
# Clean Up if you want to destroy possible exist rackhd ova vm
#
###########################################
cleanUp(){
    set +e
    echo "*****************************************************************************************************"
    echo "Start to clean up environment: delete possible ova instance, stop port forwarding legacy."
    echo "*******exportLog**********************************************************************************************"
    ova_name=("${NODE_NAME}-ova-for-post-test")
    pushd ${ON_BUILD_CONFIG_DIR}/deployment/
        ./vm_control.sh "${ESXI_HOST},${ESXI_USER},${ESXI_PASS},delete,1,${ova_name}_*"
    popd
    echo $SUDO_PASSWORD |sudo -S pkill socat
    echo "*****************************************************************************************************"
    echo "End to clean up environment: delete possible ova instance, stop port forwarding legacy."
    echo "*****************************************************************************************************"
    set -e
}

##############################################
#
# Back up exist dir or file
#
#############################################
backupFile(){
    local new_name=$( basename $1 )_$(date "+%Y-%m-%d-%H-%M-%S")
    if [ -d $1 ];then
        echo "[Warning]: $1 already exists, it will be moved to $WORKSPACE/$new_name !"
        mv $1 $WORKSPACE/$new_name
    fi
    if [ -f $1 ];then
        echo "[Warning]: $1 already exists, it will be moved to $WORKSPACE/$new_name !"
        mv $1 $WORKSPACE/$new_name
    fi
}

##############################################
#
# Mkdir WORKSPACE if it doesn't exist as a directory
# Import library if not provided
# Import common shell method
#
#############################################
prepareEnv(){
    echo "*****************************************************************************************************"
    echo "Start to prepare environment for ova function test stack deployment."
    echo "*****************************************************************************************************"
    #############################################
    #
    # Default Parameter Checking
    #
    #############################################
    if [ -n "${WORKSPACE}" ]; then
        if [ ! -d "${WORKSPACE}" ]; then
            mkdir -p ${WORKSPACE}
        fi
    fi

    if [ ! -n "${ON_BUILD_CONFIG_DIR}" ]; then
        pushd $WORKSPACE
        backupFile on-build-config
        git clone https://github.com/RackHD/on-build-config
        ON_BUILD_CONFIG_DIR=$WORKSPACE/on-build-config
        popd
    fi

    #############################################
    #
    # Import shell shareMethod
    #
    #############################################
    source $ON_BUILD_CONFIG_DIR/shareMethod.sh

    echo "*****************************************************************************************************"
    echo "Successfully prepared environment for ova function test stack deployment."
    echo "*****************************************************************************************************"
}

###################################
#
# Deploy rackhd ova
#
#################################
deployOva(){
    echo "*****************************************************************************************************"
    echo "Start to deploy rackhd ova."
    echo "*****************************************************************************************************"
    # If using a passed in ova file from an external http server and bypassing ova build,
    # use the path as is, else get the path via ls
    if [[ "${OVA_IMAGE_PATH}" == "http"* ]]; then
        OVA="${OVA_IMAGE_PATH}"
    else
        OVA=`ls ${OVA_IMAGE_PATH}`
    fi

    if [ -n "${EXTERNAL_VSWITCH}" ]; then
    execWithTimeout "echo yes | ovftool \
      --overwrite --powerOffTarget --powerOn --skipManifestCheck \
      --net:'ADMIN=${EXTERNAL_VSWITCH}'\
      --net:'CONTROL=${NODE_NAME}-switch' \
      --datastore=${DATASTORE} \
      --name=${NODE_NAME}-ova-for-post-test \
      ${OVA} \
      vi://${ESXI_USER}:${ESXI_PASS}@${ESXI_HOST}" 300
    else
      execWithTimeout "echo yes | ovftool \
      --overwrite --powerOffTarget --powerOn --skipManifestCheck \
      --net:'CONTROL=${NODE_NAME}-switch' \
      --datastore=${DATASTORE} \
      --name=${NODE_NAME}-ova-for-post-test \
      ${OVA} \
      vi://${ESXI_USER}:${ESXI_PASS}@${ESXI_HOST}" 300
    fi

    if [ $? = 0 ]; then
        echo "[Info] Deploy OVA successfully".
    else
        echo "[Error] Deploy OVA failed."
        exit 3
    fi
    # OVA_INTERNAL_IP, eth1 IP of ova
    ssh-keygen -f "$HOME/.ssh/known_hosts" -R $OVA_INTERNAL_IP

    echo "*****************************************************************************************************"
    echo "End to deploy rackhd ova."
    echo "*****************************************************************************************************"
}

###################################
#
# Wait for rackhd services
#
#################################
waitForAPI() {
  service_normal_sentence="No auth token"
  timeout=0
  maxto=60
  set +e
  url=http://$OVA_INTERNAL_IP:8080/api/2.0/nodes
  while [ ${timeout} != ${maxto} ]; do
    api_test_result=`curl ${url}`
    echo $api_test_result | grep "$service_normal_sentence" > /dev/null  2>&1
    if [ $? = 0 ]; then
      echo "[Debug] successful.        in this retry time: OVA ansible returns: $api_test_result"
      break
    fi
    sleep 10
    timeout=`expr ${timeout} + 1`
  done
  set -e
  if [ ${timeout} == ${maxto} ]; then
    echo "Timed out waiting for RackHD API service (duration=`expr $maxto \* 10`s)."
    exit 1
  fi
}

###################################
#
# Modify the RackHD ova vm
#
#################################
configRackHDOvaVm(){
    echo "*****************************************************************************************************"
    echo "Config RackHD ova vm for function test"
    echo "*****************************************************************************************************"

    # config the OVA for post test
    pushd $ON_BUILD_CONFIG_DIR/src/pipeline/rackhd/ova/ansible
      echo "ova-post-test ansible_host=$OVA_INTERNAL_IP ansible_user=$OVA_USER ansible_ssh_pass=$OVA_PASSWORD ansible_become_pass=$OVA_PASSWORD" > hosts
      cp -f ${ON_BUILD_CONFIG_DIR}/resources/pipeline/rackhd/ova/config.json .

      if [ -z "${EXTERNAL_VSWITCH}" ]; then
        ansible-playbook -i hosts main.yml --extra-vars "ova_gateway=$OVA_GATEWAY ova_net_interface=$OVA_NET_INTERFACE dns_server_ip=$DNS_SERVER_IP"  --tags "config-gateway"
      fi
      ansible-playbook -i hosts main.yml --tags "before-test" --extra-vars "ova_gateway=$OVA_GATEWAY"
    popd
}

portForwarding(){
    # forward ova to localhost
    # according to vagrant/mongo/config.json and cit/fit config
    socat TCP4-LISTEN:9091,forever,reuseaddr,fork TCP4:$1:5672 &
    socat TCP4-LISTEN:9090,forever,reuseaddr,fork TCP4:$1:8080 &
    socat TCP4-LISTEN:9092,forever,reuseaddr,fork TCP4:$1:9080 &
    socat TCP4-LISTEN:9093,forever,reuseaddr,fork TCP4:$1:8443 &
    ssh-keygen -f "$HOME/.ssh/known_hosts" -R [localhost]:2222
    socat TCP4-LISTEN:2222,forever,reuseaddr,fork TCP4:$1:22 &
    socat TCP4-LISTEN:37017,forever,reuseaddr,fork TCP4:$1:27017 &
    echo "Finished ova -> localhost port forwarding"
    echo "5672->9091"
    echo "8080->9090"
    echo "9080->9092"
    echo "8443->9093"
    echo "22->2222"
    echo "27017->37017"
}

##############################################
#
# deploy RackHD
#
#############################################
deployRackHD(){
    # Deploy rackhd ova and  run it
    deployOva

    # Check the RackHD API is accessable
    waitForAPI

    #Config ova vm for function test
    configRackHDOvaVm

    #Port forward for FIT to connect rackhd ova
    portForwarding $OVA_INTERNAL_IP
}

##############################################
#
# Export log of RackHD from ova
#
#############################################
exportLogs(){
    set +e
    mkdir -p ${LOG_DIR}
    LOG_DIR=`readlink -e ${LOG_DIR}`
    ansible_workspace=${ON_BUILD_CONFIG_DIR}/src/pipeline/rackhd/ova/ansible
    # fetch rackhd log
    pushd $ansible_workspace
      echo "ova-post-test ansible_host=$OVA_INTERNAL_IP ansible_user=$OVA_USER ansible_ssh_pass=$OVA_PASSWORD ansible_become_pass=$OVA_PASSWORD" > hosts
      ansible-playbook -i hosts main.yml --tags "after-test"
      mkdir -p ${WORKSPACE}/build-log
      for log in `ls *.log | xargs` ; do
        cp $log ${LOG_DIR}
      done
    popd
    echo $SUDO_PASSWORD |sudo -S chown -R $USER:$USER ${LOG_DIR}
    set -e
}

###################################################################
#
#  Parse and check Arguments
#
##################################################################
parseArguments(){
    while [ "$1" != "" ]; do
        case $1 in
            -w | --WORKSPACE )              shift
                                            WORKSPACE=$1
                                            ;;
            -b | --ON_BUILD_CONFIG_DIR )    shift
                                            ON_BUILD_CONFIG_DIR=$1
                                            ;;
            -i | --OVA_IMAGE_PATH )         shift
                                            OVA_IMAGE_PATH=$1
                                            ;;
            -p | --SUDO_PASSWORD )          shift
                                            SUDO_PASSWORD=$1
                                            ;;
            -l | --LOG_DIR )                shift
                                            LOG_DIR=$1
                                            ;;
            -e | --EXTERNAL_VSWITCH )       shift
                                            EXTERNAL_VSWITCH=$1
                                            ;;
            -n | --NODE_NAME )              shift
                                            NODE_NAME=$1
                                            ;;
            -d | --DATASTORE )              shift
                                            DATASTORE=$1
                                            ;;
            -eu | --ESXI_USER )              shift
                                            ESXI_USER=$1
                                            ;;
            -ep | --ESXI_PASS )              shift
                                            ESXI_PASS=$1
                                            ;;
            -h | --ESXI_HOST )              shift
                                            ESXI_HOST=$1
                                            ;;
            -o | --OVA_INTERNAL_IP )        shift
                                            OVA_INTERNAL_IP=$1
                                            ;;
            -g | --OVA_GATEWAY )            shift
                                            OVA_GATEWAY=$1
                                            ;;
            -ni | --OVA_NET_INTERFACE )     shift
                                            OVA_NET_INTERFACE=$1
                                            ;;
            -s | --DNS_SERVER_IP )          shift
                                            DNS_SERVER_IP=$1
                                            ;;
            -ou | --OVA_USER )              shift
                                            OVA_USER=$1
                                            ;;
            -op | --OVA_PASSWORD )           shift
                                            OVA_PASSWORD=$1
                                            ;;
            * )                             Usage
                                            exit 1
        esac
        shift
    done

    if [ ! -n "${OVA_IMAGE_PATH}" ] && [ ${OPERATION,,} == "deploy" ]; then
        echo "[Error]Arguments -i|--OVA_IMAGE_PATH is required"
        Usage
        exit 1
    fi

    if [ ! -n "${NODE_NAME}" ] && [ ${OPERATION,,} != "exportlog" ]; then
        echo "[Error]Arguments -n|--NODE_NAME is required"
        Usage
        exit 1
    fi

    if [ ! -n "${ESXI_HOST}" ] && [ ${OPERATION,,} != "exportlog" ]; then
        echo "[Error]Arguments -h|--ESXI_HOST is required"
        Usage
        exit 1
    fi

    if [ ! -n "${ESXI_USER}" ] && [ ${OPERATION,,} != "exportlog" ]; then
        echo "[Error]Arguments -eu|--ESXI_USER is required"
        Usage
        exit 1
    fi

    if [ ! -n "${ESXI_PASS}" ] && [ ${OPERATION,,} != "exportlog" ]; then
        echo "[Error]Arguments -p|--ESXI_PASS is required"
        Usage
        exit 1
    fi

    if [ ! -n "${DATASTORE}" ] && [ ${OPERATION,,} == "deploy" ]; then
        echo "[Error]Arguments -d|--DATASTORE is required"
        Usage
        exit 1
    fi

    if [ ! -n "${OVA_INTERNAL_IP}" ] && [ ${OPERATION,,} != "cleanup" ]; then
        echo "[Error]Arguments -o|--OVA_INTERNAL_IP is required"
        Usage
        exit 1
    fi

    if [ ! -n "${OVA_GATEWAY}" ] && [ ${OPERATION,,} == "deploy" ]; then
        echo "[Error]Arguments -g|--OVA_GATEWAY is required"
        Usage
        exit 1
    fi

    if [ ! -n "${SUDO_PASSWORD}" ]; then
        echo "[Error]Arguments -p|--SUDO_PASSWORD is required"
        Usage
        exit 1
    fi

    if [ ! -n "${WORKSPACE}" ] && [ ${OPERATION,,} != "cleanup" ]; then  # ${str,,} is to_lowercase(). available for Bash 4.
        echo "[Error]Arguments -w|--WORKSPACE is required!"
        Usage
        exit 1
    fi

    if [ ! -n "${LOG_DIR}" ] && [ ${OPERATION,,} == "exportlog" ]; then  # ${str,,} is to_lowercase(). available for Bash 4.
        echo "[Error]Arguments -l|--LOG_DIR is required!"
        Usage
        exit 1
    fi

    if [ ! -n "${OVA_USER}" ] && [ ${OPERATION,,} != "cleanup" ]; then  # ${str,,} is to_lowercase(). available for Bash 4.
        echo "[Error]Arguments -ou|--OVA_USER is required!"
        Usage
        exit 1
    fi

    if [ ! -n "${OVA_PASSWORD}" ] && [ ${OPERATION,,} != "cleanup" ]; then  # ${str,,} is to_lowercase(). available for Bash 4.
        echo "[Error]Arguments -op|--OVA_PASSWORD is required!"
        Usage
        exit 1
    fi
}


########################################################
#
# Main
#
######################################################
OPERATION=$1
case "$1" in
  cleanUp)
      shift
      parseArguments $@
      prepareEnv
      cleanUp
  ;;

  deploy)
      shift
      parseArguments $@
      prepareEnv
      deployRackHD
  ;;

  exportLog)
      shift
      parseArguments $@
      prepareEnv
      exportLogs
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
