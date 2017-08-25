#!/bin/bash -ex


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
    echo "    deploy : load a image tar with rackhd and run it"
    echo "    exportLog : export docker running log to workspace directory"
    echo "    mandatory arguments:"
    echo "      -r, --RACKHD_DIR: , The directory for RACKHD. It's required."
    echo "      -o, --ON_BUILD_CONFIG_DIR: The directory of repository on-build-config"
    echo "      -i, --RACKHD_DOCKER_IMAGE: The tar file contains all docker images exported by 'docker save' "    
    echo "      -p, --SUDO_PASSWORD:Password of current user which has sudo privilege, it's required."
    echo "      -l, --LOG_DIR: , The directory for putting log file. It's required for exportLog."
    echo "    Optional Arguments:"
}



##############################################
#
# Remove docker images after test
#
##############################################
cleanUpDockerImages(){
    set +e
    local keyword=$1
    matched_img=$(echo $SUDO_PASSWORD |sudo -S docker images | grep ${keyword} | awk '{print $3}' | sort | uniq)
    local to_be_removed="$(echo $matched_img)  \
                         $(echo $SUDO_PASSWORD |sudo -S docker images -f "dangling=true" -q )"
    # remove ${RACKHD_DOCKER_NAME} image,  rackhd/pipeline image and <none>:<none> images
    if [ ! -z "${to_be_removed// }" ] ; then
         echo $SUDO_PASSWORD |sudo -S docker rmi -f $to_be_removed 
    fi
    set -e
    echo "Clean up docker images done."
}

##############################################
#
# Remove docker instance which are running
#
##############################################
stopAndRemoveRunningContainers(){
# if the $1 is blank, will stop all running containers.
    set +e
    local docker_name_key=$1
    local running_docker=$(echo $SUDO_PASSWORD |sudo -S docker ps -a |grep "$docker_name_key" |awk '{print $1}')
    if [ "$running_docker" != "" ]; then
         echo $SUDO_PASSWORD |sudo -S docker stop $running_docker
         echo $SUDO_PASSWORD |sudo -S docker rm   $running_docker
    fi
    set -e
    echo "Stop and remove running containers done."
}


cleanUp(){
    # Clean UP. (was in Jenkins job post-build, avoid failure impacts build status.)
    set +e
    set -x
    local rackhd_dir=$1
    echo "Show local docker images"
    echo $SUDO_PASSWORD |sudo -S docker ps
    echo $SUDO_PASSWORD |sudo -S docker images
    pushd $rackhd_dir

    echo "Stop & rm all docker running containers " 
    echo $SUDO_PASSWORD |sudo -S docker-compose -f ${rackhd_dir}/docker/docker-compose.yml stop 
    echo $SUDO_PASSWORD |sudo -S docker-compose -f ${rackhd_dir}/docker/docker-compose.yml rm

    echo "Chown rackhd/files volume on hosts"
    echo $SUDO_PASSWORD |sudo -S chown -R $USER:$USER ${rackhd_dir}
    echo "Clean Up all docker images in local repo"
    cleanUpDockerImages none
    # clean images by order, on-core should be last one because others depends on it
    cleanUpDockerImages on-taskgraph
    cleanUpDockerImages on-http
    cleanUpDockerImages on-tftp
    cleanUpDockerImages on-dhcp-proxy
    cleanUpDockerImages on-syslog
    cleanUpDockerImages on-tasks
    cleanUpDockerImages files
    cleanUpDockerImages isc-dhcp-server
    cleanUpDockerImages on-wss
    cleanUpDockerImages on-statsd
    cleanUpDockerImages on-core
    cleanUpDockerImages rackhd

    echo "clean up /var/lib/docker/volumes"
    volume=$(echo $SUDO_PASSWORD |sudo -S docker volume ls -qf dangling=true)
    echo "[DEBUG] volume need rm: $volume"
    if [ -n "$volume" ]; then
      echo $SUDO_PASSWORD |sudo -S docker volume rm $volume
    fi
    echo "Clean up done."
}

##############################################
#
# deploy RackHD 
#
##############################################
deployRackHD(){
    local rackhd_dir=$1
    local on_build_config_dir=$2
    local rackhd_docker_images=$3
    local log_dir=$4

    # CleanUp & stop service
    prepareEnv ${rackhd_dir}
    # Customize the config.json
    setupRackHDConfig  ${on_build_config_dir} ${rackhd_dir}
    # Customize the docker-compose.yml
    setupDockerComposeConfig ${rackhd_docker_images} ${rackhd_dir}
    # Build docker image and run it
    dockerUp ${log_dir} ${rackhd_dir}
    echo "Deploy RackHD done."
}

prepareEnv(){
    echo "*****************************************************************************************************"
    echo "Start to clean up environment: stopping running containers, service mongodb and rabbitmq-server"
    echo "*****************************************************************************************************"
    cleanUp $1
    stopServices
    echo "Prepare Env done."
}

#########################################
#
# Stop Host services to avoid noise, there're mongo/rabbitmq inside docker , port confliction with OS's mongo/rabbitmq will occur.
#
#########################################
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
    echo "Stop services done."
}

###################################
#
# Modify the RackHD default Config file
#
###################################
setupRackHDConfig(){
    local on_build_config_dir=$1
    local rackhd_dir=$2

    echo "*****************************************************************************************************"
    echo "Customize RackHD Config Files to adopt RackHD docker enviroment"
    echo "*****************************************************************************************************"
    local rackhd_dhcp_host_ip=$(ifconfig | awk '/inet addr/{print substr($2,6)}' |grep 172.31.128)

    find ${on_build_config_dir} -type f -exec sed -i -e "s/172.31.128.1/${rackhd_dhcp_host_ip}/g" {} \;
    # this step must behind sed replace
    # replace default config json with the one which is for test.
    cp -f ${on_build_config_dir}/vagrant/config/mongo/config.json ${rackhd_dir}/docker/monorail/config.json
    #if clone file name is not repo name, this scirpt should be edited.
    echo "Setup RackHD config done."

}

####################################################
#
# Modify the docker-compose.yml default Config file
#
####################################################
setupDockerComposeConfig(){

    local rackhd_docker_images=${1} # the tar file contains all docker images exported by "docker save"
    local rackhd_dir=${2}
    local build_record=""

    local tmp_file=$(mktemp)
    # load docker images , for each on-xxx, there will be 2 tags: date-hash and nightly
    # so in this case, we only put the date-hash tags in the output file( to help to create build_record file)

    echo $SUDO_PASSWORD |sudo -S docker load -i $rackhd_docker_images | grep "UTC" | tee ${tmp_file}

    if [ $? -ne 0 ]; then
        echo "[Error] Docker Load fail, aborted!"
        exit -2
    fi
    local tmp_build_record=$(mktemp)
    repo_list=""
    # This path is followed when using the prebuilt images to get image tag
    while IFS=:  read -r load imagename tag 
    do
       repo_list="$repo_list ${imagename}:${tag}"
    done < ${tmp_file}

    echo $repo_list >> ${tmp_build_record}
    build_record=${tmp_build_record}

    image_list=$(head -n 1 $build_record)

    for repo_tag in $image_list; do
        repo=${repo_tag%:*}
        sed -i "s#${repo}.*#${repo_tag}#g" ${rackhd_dir}/docker/docker-compose.yml
    done
    echo "Setup docker compose config done."
}

dockerUp(){
    local log_dir=$1
    local rackhd_dir=${2}

    mkdir -p ${log_dir}
    set +e
    echo $SUDO_PASSWORD |sudo -S docker pull mongo:latest
    echo $SUDO_PASSWORD |sudo -S docker pull rabbitmq:management
    set -e

    echo $SUDO_PASSWORD |sudo -S docker-compose -f ${rackhd_dir}/docker/docker-compose.yml up > ${log_dir}/rackhd.log &
    echo "Docker up done."
}


##############################################
#
# Export docker running log to workspace
#
##############################################
exportLogs(){
    local log_dir=$1
    set +e
    mkdir -p ${log_dir}
    echo "Export logs start" >> ${log_dir}/export.log
    containerId=$(echo $SUDO_PASSWORD |sudo -S docker ps|grep "mongo"| head -n1 | awk '{print $1}' )
    echo "[DEBUG] mongo containerId:${containerId} "
    #echo $SUDO_PASSWORD |sudo -S docker cp   $containerId:/var/log/mongodb/mongodb.log ${log_dir}
    if [ -n "$containerId" ]; then
        echo $SUDO_PASSWORD |sudo -S docker logs $containerId >> ${log_dir}/mongodb.log
    fi
    echo $SUDO_PASSWORD |sudo -S chown -R $USER:$USER ${log_dir}
    set -e
    echo "Export logs done."
}


checkMandatoryParam(){
    #
    #    $1 : parameter name
    #    $2 : this param is only mandatory when operation in a list
    #
    local var_name=$1
    eval var=\$$var_name
    if [ *"$OPERATION"* != $2 ]; then
       # This Parameter is not mandatory when operation = $OPERATION
       return 
    fi
    if [ ! -n "$var" ]; then
        echo "[Error]Arguments $var_name is required"
        Usage
        exit 1
    fi
    echo "Check mandatory param done."
}

###################################################################
#
#  Parse and check Arguments
#
###################################################################
parseArguments(){
    while [ "$1" != "" ]; do
        case $1 in
            -r | --RACKHD_DIR )             shift
                                            RACKHD_DIR=$1
                                            ;;
            -o | --ON_BUILD_CONFIG_DIR )    shift
                                            ON_BUILD_CONFIG_DIR=$1
                                            ;;
            -i | --RACKHD_DOCKER_IMAGE )    shift
                                            RACKHD_DOCKER_IMAGE=$1
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

    checkMandatoryParam "RACKHD_DIR"            "deploy,cleanUp"
    checkMandatoryParam "ON_BUILD_CONFIG_DIR"   "deploy"
    checkMandatoryParam "RACKHD_DOCKER_IMAGE"   "deploy"
    checkMandatoryParam "SUDO_PASSWORD"         "deploy,cleanUp,exportLog"
    checkMandatoryParam "LOG_DIR"               "deploy,exportLog"
    echo "Parse arguments done."
}


########################################################
#
# Main
#
########################################################
OPERATION=$1
case "$1" in
  cleanUp|cleanup)
      shift
      parseArguments $@
      cleanUp $RACKHD_DIR
  ;;

  deploy)
      shift
      parseArguments $@
      deployRackHD $RACKHD_DIR $ON_BUILD_CONFIG_DIR $RACKHD_DOCKER_IMAGE $LOG_DIR
  ;;

  exportLog|exportlog)
      shift
      parseArguments $@
      exportLogs $LOG_DIR
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
echo "Main done."
