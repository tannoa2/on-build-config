#!/bin/bash -x

set +e

buildOva(){
  # If OVA_CACHE_BUILD is not used, cache_image directory does not exist
  if [ -d  $WORKSPACE/$CACHE_IMAGE_DIR/RackHD/packer/ ] ; then
      echo "Copy Cache images from PACKER_CACHE_BUILD job archiving"
      mv $WORKSPACE/$CACHE_IMAGE_DIR/RackHD/packer/* $RACKHD_DIR/packer/
      ls $RACKHD_DIR/packer/*
  fi

  vmware -v

  echo using artifactory : $ARTIFACTORY_URL

  source ./$ON_BUILD_CONFIG_DIR/shareMethod.sh $ON_BUILD_CONFIG_DIR

  pushd $RACKHD_DIR/packer/ansible/roles/rackhd-builds/tasks
  sed -i "s#https://dl.bintray.com/rackhd/debian trusty release#${ARTIFACTORY_URL}/${STAGE_REPO_NAME} ${DEB_DISTRIBUTION} ${DEB_COMPONENT}#" main.yml
  sed -i "s#https://dl.bintray.com/rackhd/debian trusty main#${ARTIFACTORY_URL}/${STAGE_REPO_NAME} ${DEB_DISTRIBUTION} ${DEB_COMPONENT}#" main.yml
  popd

  echo "kill previous running packer instances"

  set +e
  pkill packer
  pkill vmware
  set -e

  pushd $RACKHD_DIR/packer
  echo "Start to packer build .."

  export PACKER_CACHE_DIR=$HOME/.packer_cache
  #export vars to build ova
  if [ "${IS_OFFICIAL_RELEASE}" == true ]; then
      export ANSIBLE_PLAYBOOK=rackhd_release
  else
      export ANSIBLE_PLAYBOOK=rackhd_ci_builds
  fi

  if [ "$BUILD_TYPE" == "vmware" ] &&  [ -f output-vmware-iso/*.vmx ]; then
       echo "Build from template cache"
       export BUILD_STAGE=BUILD_FINAL
  else
       echo "Build from begining"
       export BUILD_STAGE=BUILD_ALL
  fi

  export RACKHD_VERSION=$RACKHD_VERSION
  #export end

  ./HWIMO-BUILD

  mv rackhd-${OS_VER}.ova rackhd-${OS_VER}-${RACKHD_VERSION}.ova

  popd
}


###################################################################
#
#  Parse and check Arguments
#
##################################################################
parseArguments(){
    while [ "$1" != "" ]; do
        case $1 in
            --WORKSPACE )                   shift
                                            WORKSPACE=$1
                                            ;;
            --CACHE_IMAGE_DIR )             shift
                                            CACHE_IMAGE_DIR=$1
                                            ;;
            --RACKHD_DIR )                  shift
                                            RACKHD_DIR=$1
                                            ;;
            --ON_BUILD_CONFIG_DIR )         shift
                                            ON_BUILD_CONFIG_DIR=$1
                                            ;;
            --IS_OFFICIAL_RELEASE )         shift
                                            IS_OFFICIAL_RELEASE=$1
                                            ;;
            --BUILD_TYPE )  shift
                                            BUILD_TYPE=$1
                                            ;;
            --RACKHD_VERSION )              shift
                                            RACKHD_VERSION=$1
                                            ;;
            --OS_VER )                      shift
                                            OS_VER=$1
                                            ;;
            --ARTIFACTORY_URL )             shift
                                            ARTIFACTORY_URL=$1
                                            ;;
            --STAGE_REPO_NAME )             shift
                                            STAGE_REPO_NAME=$1
                                            ;;
            --DEB_DISTRIBUTION )            shift
                                            DEB_DISTRIBUTION=$1
                                            ;;
            --DEB_COMPONENT )               shift
                                            DEB_COMPONENT=$1
                                            ;;
            * )                             echo "Arguments mssing! Please check the parameters."
                                            exit 1
        esac
        shift
    done

    if [ ! -n "${STAGE_REPO_NAME}" ] ; then
        echo "[Error]Arguments STAGE_REPO_NAME is required!"
        Usage
        exit 1
    fi

    if [ ! -n "${DEB_DISTRIBUTION}" ]; then
        echo "[Error]Arguments DEB_DISTRIBUTION is required"
        Usage
        exit 1
    fi

    if [ ! -n "${DEB_COMPONENT}" ]; then
        echo "[Error]Arguments DEB_COMPONENT is required"
        Usage
        exit 1
    fi

    if [ ! -n "${ON_BUILD_CONFIG_DIR}" ]; then
        echo "[Error]Arguments ON_BUILD_CONFIG_DIR is required"
        Usage
        exit 1
    fi
}

parseArguments "$@"
buildOva
