#!/bin/bash -e
Usage(){
    echo "function: this script is used to save a running docker container to image and push it to docker hub"
    echo "usage: $0 [arguments]"
    echo "    mandatory arguments:"
    echo "      -s, --SUDO_PASSWORD: The password of current use which has sudo privileges"
    echo "      -u, --DOCKER_USER: The username of docker hub"
    echo "      -p, --DOCKER_PASSWORD: The password of docker hub"
    echo "      -n, --DOCKER_NAME: The name of the target docker container"
    echo "      -t, --DOCKER_TAG: The tag of the image"
    echo "      -r, --TARGET_DOCKER_REPO: The target repository on docker hub"
    echo "      -o, --TARGET_OUTPUT_DIR: The directory of log files"
}

saveDocker(){
    echo $SUDO_PASSWORD |sudo -S docker login -u $DOCKER_USER -p $DOCKER_PASSWORD
    containerId=$( echo $SUDO_PASSWORD |sudo -S docker ps|grep "$DOCKER_NAME" | awk '{print $1}' )
    echo $SUDO_PASSWORD |sudo -S docker commit $containerId my/temp
    echo $SUDO_PASSWORD |sudo -S docker tag my/temp $TARGET_DOCKER_REPO/$DOCKER_TAG
    echo $SUDO_PASSWORD |sudo -S docker push $TARGET_DOCKER_REPO/$DOCKER_TAG
    echo "Please run below command to run the docker locally:" > ${TARGET_OUTPUT_DIR}/docker_tag.log
    echo "sudo docker run --net=host -d -t rackhdci/${DOCKER_TAG}" >> ${TARGET_OUTPUT_DIR}/docker_tag.log
    echo "PS: the docker require a NIC with ip 172.31.128.250" >> ${TARGET_OUTPUT_DIR}/docker_tag.log
}
###################################################################
#
#  Parse and check Arguments
#
##################################################################
parseArguments(){
    while [ "$1" != "" ]; do
        case $1 in
            -s | --SUDO_PASSWORD )          shift
                                            SUDO_PASSWORD=$1
                                            ;;
            -u | --DOCKER_USER )            shift
                                            DOCKER_USER=$1
                                            ;;
            -p | --DOCKER_PASSWORD )        shift
                                            DOCKER_PASSWORD=$1
                                            ;;
            -n | --DOCKER_NAME )            shift
                                            DOCKER_NAME="$1"
                                            ;;
            -t | --DOCKER_TAG )             shift
                                            DOCKER_TAG="${1,,}"
                                            ;;
            -r | --TARGET_DOCKER_REPO )     shift
                                            TARGET_DOCKER_REPO=$1
                                            ;;
            -o | --TARGET_OUTPUT_DIR )      shift
                                            TARGET_OUTPUT_DIR=$1
                                            ;;
            * )                             Usage
                                            exit 1
        esac
        shift
    done

    if [ ! -n "${SUDO_PASSWORD}" ]; then
        echo "[Error]Arguments -s | --SUDO_PASSWORD is required"
        Usage
        exit 1
    fi

    if [ ! -n "${DOCKER_USER}" ]; then
        echo "[Error]Arguments -u | --DOCKER_USER is required"
        Usage
        exit 1
    fi

    if [ ! -n "${DOCKER_PASSWORD}" ]; then
        echo "[Error]Arguments -p | --DOCKER_PASSWORD is required"
        Usage
        exit 1
    fi

    if [ ! -n "${DOCKER_NAME}" ]; then
        echo "[Error]Arguments -n | --DOCKER_NAME is required"
        Usage
        exit 1
    fi

    if [ ! -n "${DOCKER_TAG}" ]; then
        echo "[Error]Arguments -t | --DOCKER_TAG is required"
        Usage
        exit 1
    fi

    if [ ! -n "${TARGET_DOCKER_REPO}" ]; then
        echo "[Error]Arguments -r | --TARGET_DOCKER_REPO is required"
        Usage
        exit 1
    fi

    if [ ! -n "${TARGET_OUTPUT_DIR}" ]; then
        echo "[Error]Arguments -o | --TARGET_OUTPUT_DIR is required"
        Usage
        exit 1
    fi
    mkdir -p $TARGET_OUTPUT_DIR
}


########################################################
#
# Main
#
######################################################
main(){
    parseArguments "$@"
    saveDocker
}
main "$@"
