#!/bin/bash -e

#############################################
#
# Global Variable
############################################
RACKHD_DOCKER_NAME="my/test"
BASE_IMAGE_URL=http://rackhdci.lss.emc.com/job/Docker_Image_Build/lastSuccessfulBuild/artifact/rackhd_pipeline_docker.tar  # EMC internal Jenkins
OPERATION=""

#########################################
#
#  Usage
#
#########################################
Usage(){
    echo "function: this script is used to deploy rackhd within docker"
    echo "usage: $0 [options] [arguments]"
    echo "  options:"
    echo "    -h     : give this help list"
    echo "    cleanup: remove the running rackhd docker container and rackhd images"
    echo "    deploy : build a image with rackhd and run it"
    echo "    exportLog : export log file from docker container to target log directory"
    echo "    mandatory arguments:"
    echo "      -w, --WORKSPACE: the directory of workspace( where the code will be cloned to and staging folder), it's required for deploy"
    echo "      -p, --SUDO_PASSWORD: password of current user which has sudo privilege, it's required."
    echo "      -l, --LOG_DIR: , The directory for putting log file. It's required for exportLog."
    echo "    Optional Arguments:"
    echo "      -s, --SRC_CODE_DIR: The directory of source code which contains all the repositories of RackHD"
    echo "                       If it's not provided, the script will clone the latest source code under $WORKSPACE/build-deps"
    echo "      -f, --MANIFEST_FILE: The path of manifest file"
    echo "                       If it's not provided, the script will generate a new manifest with latest commit of repositories of RackHD"
    echo "      -b, --ON_BUILD_CONFIG_DIR: The directory of repository on-build-config"
    echo "                       If it's not provided, the script will clone the latest repository on-build-config under $WORKSPACE"
    echo "      -i, --RACKHD_IMAGE_PATH: The path of base docker image of rackhd CI test (rackhd/pipeline)"
    echo "                       If it's not provided, the script will download the image from jenkins artifacts"
}


##############################################
#
# Remove docker images after test
#
###########################################
cleanUpDockerImages(){
    set +e
    local to_be_removed="$(echo $SUDO_PASSWORD |sudo -S docker images ${RACKHD_DOCKER_NAME} -q)  \
                         $(echo $SUDO_PASSWORD |sudo -S docker images rackhd/pipeline -q)  \
                         $(echo $SUDO_PASSWORD |sudo -S docker images -f "dangling=true" -q )"
    # remove ${RACKHD_DOCKER_NAME} image,  rackhd/pipeline image and <none>:<none> images
    if [ ! -z "${to_be_removed// }" ] ; then
         echo $SUDO_PASSWORD |sudo -S docker rmi $to_be_removed
    fi
    set -e
}

##############################################
#
# Remove docker instance which are running
#
###########################################
cleanUpDockerContainer(){
    set +e
    local docker_name_key=$1
    local running_docker=$(echo $SUDO_PASSWORD |sudo -S docker ps -a |grep "$1" |awk '{print $1}')
    if [ "$running_docker" != "" ]; then
         echo $SUDO_PASSWORD |sudo -S docker stop $running_docker
         echo $SUDO_PASSWORD |sudo -S docker rm   $running_docker
    fi
    set -e
}

######################################
#
# Clean Up runnning docker instance
#
#####################################
cleanupDockers(){
    echo "CleanUp Dockers ..."
    set +e
    cleanUpDockerContainer "${RACKHD_DOCKER_NAME}"
    cleanUpDockerImages
    set -e
}


#########################################
#
# Start Host services to avoid noise
#
#######################################
startServices(){
    echo "Start Services (mongo/rabbitmq)..."
    set +e
    mongo_path=$( which mongod )
    rabbitmq_path=$( which rabbitmq-server )
    if [ ! -z "$mongo_path" ]; then
        echo $SUDO_PASSWORD |sudo -S service mongodb start
    fi
    if [ ! -z "$rabbitmq_path" ]; then
        echo $SUDO_PASSWORD |sudo -S service rabbitmq-server start
    fi
    set -e
}
#########################################
#
# Stop Host services to avoid noise, there're mongo/rabbitmq inside docker , port confliction with OS's mongo/rabbitmq will occur.
#
#######################################
stopServices(){
    echo "Stop Services (mongo/rabbitmq)..."
    set +e
    netstat -ntlp |grep ":27017 "
    mongo_port_in_use=$?
    netstat -ntlp |grep ":5672 "
    rabbitmq_port_in_use=$?
    if [ "$mongo_port_in_use" == "0" ]; then
        echo $SUDO_PASSWORD |sudo -S service mongodb stop
    fi
    if [ "$rabbitmq_port_in_use" == "0" ]; then
        echo $SUDO_PASSWORD |sudo -S service rabbitmq-server stop
    fi
    set -e
}

############################################
#
# Clean Up if you want to stop RackHD docker and recover services
#
###########################################
cleanUp(){
    set +e
    echo "*****************************************************************************************************"
    echo "Start to clean up environment: stopping running containers, starting service mongodb and rabbitmq-server"
    echo "*****************************************************************************************************"
    cleanupDockers
    startServices
    netstat -ntlp
    echo "*****************************************************************************************************"
    echo "End to clean up environment: stopping running containers, starting service mongodb and rabbitmq-server"
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
# Clean up previous dirty space before everyting starts
# Check arguments and prepare depends repository and images
#
#############################################
prepareEnv(){
    echo "*****************************************************************************************************"
    echo "Start to clean up environment: stopping running containers, service mongodb and rabbitmq-server"
    echo "*****************************************************************************************************"
    cleanupDockers
    stopServices
    #############################################
    #
    # Default Parameter Checking
    #
    #############################################
    if [ ! -n "${WORKSPACE}" ]; then
        echo "Arguments WORKSPACE is required"
        exit 1
    else
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
    if [ ! -n "${RACKHD_IMAGE_PATH}" ]; then
        pushd $WORKSPACE
        # Auto Select the best available server to download
        set +e 
        ping -q -c 1 rackhdci.lss.emc.com > /dev/null
        if [ "$?" != "0" ]; then
           BASE_IMAGE_URL=http://147.178.202.18/job/Docker_Image_Build/lastSuccessfulBuild/artifact/rackhd_pipeline_docker.tar  # the cloud Jenkins mirror
        fi
        set -e
        download_docker_file=$( echo ${BASE_IMAGE_URL##*/} )
        backupFile $download_docker_file
        wget $BASE_IMAGE_URL
        RACKHD_IMAGE_PATH=$WORKSPACE/$download_docker_file
        popd
    fi
    if [ ! -n "${SRC_CODE_DIR}" ]; then
        if [ ! -n "${MANIFEST_FILE}" ]; then
           # Checkout RackHD source code and build them
           generateManifest # it will generate a manifest file and export the MANIFEST_FILE variable
        fi
        SRC_CODE_DIR=${WORKSPACE}/build-deps
        preparePackages $MANIFEST_FILE $SRC_CODE_DIR # it will clone and build RackHD code under ${WORKSPACE}/build-deps according to the new_manifest
    fi
    echo "*****************************************************************************************************"
    echo "End to clean up environment: stopping running containers, service mongodb and rabbitmq-server"
    echo "*****************************************************************************************************"
}

##############################################
#
# Generate a manifest file according to the latest commit of repositories of RackHD
#
#############################################
generateManifest(){
    echo "*****************************************************************************************************"
    echo "Start to generate a manifest with the latest commit of RackHD" 
    echo "*****************************************************************************************************"
    pushd $ON_BUILD_CONFIG_DIR
    # Generate a manifest file
    ./build-release-tools/HWIMO-BUILD build-release-tools/application/generate_manifest.py \
    --branch master \
    --date current \
    --timezone -0500 \
    --builddir $WORKSPACE/build-deps \
    --dest-manifest new_manifest \
    --force \
    --jobs 8
    # above script will generate a manifest file as $WORKSPACE/new_manifest
    MANIFEST_FILE=$WORKSPACE/new_manifest
    popd
    echo "*****************************************************************************************************"
    echo "End to generate manifest file"
    echo "*****************************************************************************************************"
}

##############################################
#
# Check out repositories of RackHD, build them and download static files
#
#############################################
preparePackages() {
    local manifest_file=$1
    local target_dir=$2
    echo "*****************************************************************************************************"
    echo "Start to check out RackHD source code and run npm build"
    echo "*****************************************************************************************************"
    pushd $ON_BUILD_CONFIG_DIR/src/pipeline/rackhd/source_code
    bash ./build.sh --TARGET_DIR $target_dir --MANIFEST_FILE $manifest_file --ON_BUILD_CONFIG_DIR $ON_BUILD_CONFIG_DIR
    popd
    echo "*****************************************************************************************************"
    echo "End to check out RackHD source code and run npm build"
    echo "*****************************************************************************************************"
}

###################################
#
# Modify the RackHD default Config file
#
#################################
setupRackHDConfig(){
    echo "*****************************************************************************************************"
    echo "Customize RackHD Config Files to adopt RackHD docker enviroment"
    echo "*****************************************************************************************************"
    cp ${ON_BUILD_CONFIG_DIR}/resources/pipeline/rackhd/source_code/config.json ${ON_BUILD_CONFIG_DIR}/src/pipeline/rackhd/source_code/docker/
    RACKHD_DHCP_HOST_IP=$(ifconfig | awk '/inet addr/{print substr($2,6)}' |grep -m1 172.31.128)
    sed -i "s/172.31.128.1/${RACKHD_DHCP_HOST_IP}/g" ${ON_BUILD_CONFIG_DIR}/src/pipeline/rackhd/source_code/docker/config.json
}


###################################
#
# Build docker and run it
#
#################################
dockerUp(){
    echo "*****************************************************************************************************"
    echo "Start to build and run RackHD CI docker"
    echo "*****************************************************************************************************"
    echo $SUDO_PASSWORD |sudo -S docker load -i $RACKHD_IMAGE_PATH
    pushd ${SRC_CODE_DIR}
    cp -r ${ON_BUILD_CONFIG_DIR}/src/pipeline/rackhd/source_code/docker/* .
    echo $SUDO_PASSWORD |sudo -S docker build -t my/test .
    echo $SUDO_PASSWORD |sudo -S docker run --net=host -v /etc/localtime:/etc/localtime:ro -d -t my/test
    popd
    echo "*****************************************************************************************************"
    echo "End to build and run RackHD CI docker"
    echo "*****************************************************************************************************"
}

##############################################
#
# Check the API of RackHD is accessable
#
#############################################
waitForAPI() {
    echo "*****************************************************************************************************"
    echo "Try to access the RackHD API"
    echo "*****************************************************************************************************"
    timeout=0
    maxto=60
    set +e
    url=http://localhost:9090/api/2.0/nodes #9090 is the rackhd api port which docker uses
    while [ ${timeout} != ${maxto} ]; do
        wget --retry-connrefused --waitretry=1 --read-timeout=20 --timeout=15 -t 1 --continue ${url}
        if [ $? = 0 ]; then
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
    echo "*****************************************************************************************************"
    echo "RackHD API is accessable"
    echo "*****************************************************************************************************"
}


##############################################
#
# deploy RackHD 
#
#############################################
deployRackHD(){
    # Checkout tools: on-build-config and RackHD
    prepareEnv
    # Costumrize the config.json
    setupRackHDConfig
    # Build docker image and run it
    dockerUp
    # Check the RackHD API is accessable
    waitForAPI   
}


##############################################
#
# Export log of RackHD from container
#
#############################################
exportLogs(){
    set +e
    mkdir -p ${LOG_DIR}
    containerId=$( docker ps|grep "${RACKHD_DOCKER_NAME}" | awk '{print $1}' )
    echo $SUDO_PASSWORD |sudo -S docker cp $containerId:/var/log/rackhd.log ${LOG_DIR}
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
            -s | --SRC_CODE_DIR )           shift
                                            SRC_CODE_DIR=$1
                                            ;;
            -f | --MANIFEST_FILE )          shift
                                            MANIFEST_FILE=$1
                                            ;;
            -b | --ON_BUILD_CONFIG_DIR )    shift
                                            ON_BUILD_CONFIG_DIR=$1
                                            ;;
            -i | --RACKHD_IMAGE_PATH )      shift
                                            RACKHD_IMAGE_PATH=$1
                                            ;;
            -p | --SUDO_PASSWORD )          shift
                                            SUDO_PASSWORD=$1
                                            ;;
            -l | --LOG_DIR )                shift
                                            LOG_DIR=$1
                                            ;;
            * )                             Usage
                                            exit 1
        esac
        shift
    done

    if [ ! -n "${SUDO_PASSWORD}" ]; then
        echo "[Error]Arguments -p|--SUDO_PASSWORD is required"
        Usage
        exit 1
    fi

    if [ ! -n "${WORKSPACE}" ] && [ ${OPERATION,,} == "deploy" ]; then  # ${str,,} is to_lowercase(). available for Bash 4.
        echo "[Error]Arguments -w|--WORKSPACE is required!"
        Usage
        exit 1
    fi

    if [ ! -n "${LOG_DIR}" ] && [ ${OPERATION,,} == "exportlog" ]; then  # ${str,,} is to_lowercase(). available for Bash 4.
        echo "[Error]Arguments -l|--LOG_DIR is required!"
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
  cleanUp|cleanup)
      shift
      parseArguments $@
      cleanUp
  ;;

  deploy)
      shift
      parseArguments $@
      deployRackHD
  ;;

  exportLog)
      shift
      parseArguments $@
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
