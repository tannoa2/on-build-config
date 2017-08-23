#!/bin/bash -ex

##########################################
#
# Download pre-build static file from deb
#
##########################################
downloadOnImagebuilderFromDeb() {
    if [ $# -lt 5 ]; then
        echo "[Error] Wrong usage of $0. Abort "
        exit -1
    fi
    local artifactory_url=${1%/}  #remove the trailing slash
    local deb_version=$2  # the specific version to be downloaded
    local stage_repo=$3   # the remote repo name in cloud artifactory, like rackhd_staging
    local target_on_http_static_folder=$4  # where to put the on-http static files
    local target_on_tftp_static_folder=$5  # where to put the on-tftp static files
    ### TODO ###################
    #if artifactory_url == null
    #  build from skcretch
    ############################

    local work_dir=$(mktemp -d)
    pushd $work_dir

    # Download the staging on-imagebuilder.deb
    local remote_deb_file_path=${stage_repo}/pool/o
    #the remote deb file name
    local deb_name=on-imagebuilder_${deb_version}_all.deb
    local local_deb_fname=local-on-imaegbuilder-${deb_version}.deb

    echo "[Info] Downloading on-imagebuilder deb , version = $on_imagebuilder_version ... URL: ${artifactory_url}/${remote_deb_file_path}/${deb_name}"

    #Download the deb package to local folder (the URL is senstive to duplicated splash)
    wget -c -t 5 -nv ${artifactory_url}/${remote_deb_file_path}/${deb_name} -O ${local_deb_fname}

    # Extact the deb content into a folder
    if [ "$(which dpkg-deb)" == "" ]; then
         echo $SUDO_PASSWORD |sudo -S apt-get install -y dpkg
    fi

    #using dpkg-deb -x to extract the deb file, they will be in $work_dir/var/renasar/on-xxx/static/..
    dpkg-deb -x $local_deb_fname $work_dir

    common_path=${work_dir}/var/renasar/on-http/static/http/common
    pxe_path=${work_dir}/var/renasar/on-tftp/static/tftp/
    #copy static files to destination
    mv ${common_path}/* $target_on_http_static_folder
    mv ${pxe_path}/*    $target_on_tftp_static_folder

    popd
    #clean up
    rm -r ${work_dir}
}
                                       

cloneCodeFromManifest(){
    local build_config_dir=$1
    local manifest_url=$2
    local dest_dir=$3
    #download manifest
    local_manifest_file=$(mktemp)
    if [[ $manifest_url == *"http"* ]]; then
        echo "using manifest URL : $manifest_url ,save to $local_manifest_file"
        curl -L "$manifest_url" -o ${local_manifest_file}
    else
        if [ -f $manifest_url ]; then
            echo "using manifest path : $manifest_url"
            local_manifest_file=$manifest_url
        else
            echo "[Error] local manifest file not exist : $manifest_url . Abort !"
            exit -1
        fi
    fi

    #clone
    ${build_config_dir}/build-release-tools/HWIMO-BUILD ${build_config_dir}/build-release-tools/application/reprove.py \
    --manifest ${local_manifest_file} \
    --builddir ${dest_dir} \
    --jobs 8 \
    --force \
    checkout \
    packagerefs-commit
    mv $local_manifest_file  ${dest_dir}
}



# calculate tag
# input: repo directory with on-xxx src code inside it
# input: RACKHD_CHANGELOG_VERSION in global var 
# output: PKG_TAG as a global var
tagCalculate() {
    local repo=$1
    local rackhd_changelog_version=$2
    pushd $repo
        #Get package version from debian/changelog
        local CHANGELOG_VERSION=""

        if [ -f "debian/changelog" ]; then
            CHANGELOG_VERSION=$(dpkg-parsechangelog --show-field Version)
        elif [ -f "debianstatic/$repo/changelog" ]; then
            cp -rf debianstatic/$repo ./debian
            CHANGELOG_VERSION=$(dpkg-parsechangelog --show-field Version)
            rm -rf debian
        else
            CHANGELOG_VERSION=$rackhd_changelog_version
        fi
        local GIT_COMMIT_DATE=$(git show -s --pretty="format:%ci")
        local DATE_STRING="$(date -d "$GIT_COMMIT_DATE" -u +"%Y%m%dUTC")"
        local GIT_COMMIT_HASH=$(git show -s --pretty="format:%h")
        PKG_TAG="$CHANGELOG_VERSION-$DATE_STRING-$GIT_COMMIT_HASH"
    popd
}

buildOnCore() {
    local commitstring_file=$1
    local on_core_tag=$2
    echo "[DEBUG]build on-core"
    pushd on-core
        addCommitString ${commitstring_file}
        docker build -t rackhd/on-core${on_core_tag} .
    popd
}

buildOnTasks() {
    local commitstring_file=$1
    local on_core_tag=$2
    local on_tasks_tag=$3
    echo "[DEBUG]build on-tasks"
    pushd on-tasks
        addCommitString ${commitstring_file}
        sed -i "s/^FROM rackhd\/on-core:\${tag}/FROM rackhd\/on-core${on_core_tag}/" Dockerfile
        docker build -t rackhd/on-tasks${on_tasks_tag} .
    popd
}

buildOnImagebuilder() {
    local commitstring_file=$1
    local repo="on-imagebuilder"
    echo "[DEBUG]build on-imagebuilder"
    PKG_TAG=""
    tagCalculate $repo $RACKHD_CHANGELOG_VERSION
    pushd $repo
        addCommitString ${commitstring_file}
        echo "Building rackhd/$repo:${PKG_TAG}"
        cp Dockerfile ../Dockerfile.bak
        cp ${commitstring_file} ./common/
        docker build -t rackhd/files:${PKG_TAG} .
    popd
}

buildCommon() {
    local repo=$1
    local commitstring_file=$2
    local on_core_tag=$3
    local on_tasks_tag=$4
    echo "[DEBUG]build $repo"

    if [ ! -d $repo ]; then
        echo "Repo directory of $repo does not exist"
        popd > /dev/null 2>&1
        exit 1
    fi
    PKG_TAG=""
    tagCalculate $repo $RACKHD_CHANGELOG_VERSION
    pushd $repo
        addCommitString ${commitstring_file}

        echo "Building rackhd/$repo:${PKG_TAG}"
        cp Dockerfile ../Dockerfile.bak
        #Based on newly build upstream image to build
        sed -i "s/^FROM rackhd\/on-core:\${tag}/FROM rackhd\/on-core${on_core_tag}/" Dockerfile
        sed -i "s/^FROM rackhd\/on-tasks:\${tag}/FROM rackhd\/on-tasks${on_tasks_tag}/" Dockerfile
        docker build -t rackhd/$repo:${PKG_TAG} .
        mv ../Dockerfile.bak Dockerfile
    popd    
}

###################################
#
#  it will build docker images ...
#
#  Input : workspace - where the src code repos are cloned to.
#  Input : build_record_file - the file contains a list of the docker images:tags 
###################################

doBuild() {
    local workspace=$1
    local build_record_file=$2
    local commitstring_file="commitstring.txt" 
    pushd ${workspace}
    # List order is important, on-tasks image build is based on on-core image, 
    # on-http and on-taskgraph ard based on on-tasks image 
    # others are based on on-core image
    # repos=$(echo "on-imagebuilder on-core on-syslog on-dhcp-proxy on-tftp on-wss on-statsd on-tasks on-taskgraph on-http")

    #Set an empty TAG before each build

    tagCalculate "./on-core" $RACKHD_CHANGELOG_VERSION
    local ON_CORE_TAG=:${PKG_TAG}

    tagCalculate "./on-tasks" $RACKHD_CHANGELOG_VERSION
    local ON_TASKS_TAG=:${PKG_TAG}

    local repos_tags=""

    buildOnCore ${commitstring_file} ${ON_CORE_TAG}
    repos_tags=$repos_tags"rackhd/on-core"${ON_CORE_TAG}" "

    buildOnTasks ${commitstring_file} ${ON_CORE_TAG} ${ON_TASKS_TAG}
    repos_tags=$repos_tags"rackhd/on-tasks"${ON_TASKS_TAG}" "

    buildOnImagebuilder ${commitstring_file}
    repos_tags=$repos_tags"rackhd/files":${PKG_TAG}" "

    local repos=$(echo "on-syslog on-dhcp-proxy on-tftp on-wss on-statsd on-taskgraph on-http")
    for repo in $repos;do
        buildCommon ${repo} ${commitstring_file} ${ON_CORE_TAG} ${ON_TASKS_TAG}
        repos_tags=$repos_tags"rackhd/"$repo:${PKG_TAG}" "
    done

    # write build list to a file for guiding image push. 
    echo "Imagename:tag list of this build is $repos_tags"
    echo $repos_tags >> ${build_record_file}

    popd
}

# Add version/commit in commitstring.txt for docker image build.
addCommitString(){
    git log -n 1 --pretty=format:%h.%ai.%s > ${1}
}

buildDockers() {
    #when run this script locally use default value
    local clone_dir=$1
    local basedir=$(cd $(dirname "$0");pwd)
    local clone_dir=${clone_dir:=$(dirname $(dirname $basedir))}

    local build_record_file=${2}
    # Build begins

    pushd ${clone_dir}/RackHD
        #get rackhd changelog Version
        RACKHD_CHANGELOG_VERSION=$(dpkg-parsechangelog --show-field Version)
    popd

    #record all image:tag of each build
    if [ -f   $build_record_file   ];then
        rm    $build_record_file
        touch $build_record_file
    fi

    doBuild $clone_dir $build_record_file
    # Build ends
}


#########################################
#
#  Usage
#
#########################################
Usage(){
    echo "Function: this script is used to build RackHD docker according to Manifest"
    echo "usage: $0 [arguments]"
    echo "    Optional Arguments:"
    echo "      --MANIFEST_FILE (default: blank): the URL of manifest file, if it's not given, it's assumed that all on-xxx code has been cloned into CLONE_DIR."
    echo "      --CLONE_DIR (default: /tmp/b)   : where the RackHD on-xx code will be cloned to(according to manifest) , or where those code have been cloned."
    echo "      --ARTIFACTORY_URL (default: EMC Artifactory): from where to download the pre-build on-imagebuilder static files" 
    echo "      --STAGE_REPO_NAME (default: rackhd-staging): the artifactory repo which the on-imagebuilder static files locate" 
    echo "      --WORKDIR(default: false): where the docker image tar package & the build_record file save."
}


###################################################################
#
#  Parse and check Arguments
#
##################################################################
parseArguments(){
    while [ "$1" != "" ]; do
        case $1 in
            --MANIFEST_FILE )           shift
                                            MANIFEST_FILE=$1
                                            ;;
            --ARTIFACTORY_URL )             shift
                                            ARTIFACTORY_URL=$1
                                            ;;                                            
            --STAGE_REPO_NAME )             shift
                                            STAGE_REPO_NAME=$1
                                            ;; 
            --CLONE_DIR )                   shift
                                            CLONE_DIR=$1
                                            ;;     
            --WORKDIR)                      shift 
                                            WORKDIR=$1
                                            ;;                  
            * )
                                            Usage
                                            exit 1
        esac
        shift
    done
    if [ ! -n "${CLONE_DIR}" ] ; then 
        echo "[Using default value] CLONE_DIR=$WORKDIR/b !"
        CLONE_DIR=$WORKDIR/b
    fi
    if [ "${CLONE_DIR:0:1}" == "." ]; then
        echo "[Warning] the CLONE_DIR will be located under $WORKDIR."
        CLONE_DIR=${WORKDIR}${CLONEDIR}
    fi
    if [ ! -n "${ARTIFACTORY_URL}" ] ; then 
        echo "[Using default value] ARTIFACTORY_URL=http://afeossand1.cec.lab.emc.com/artifactory  !"
        ARTIFACTORY_URL="http://afeossand1.cec.lab.emc.com/artifactory"
    fi
    if [ ! -n "${STAGE_REPO_NAME}" ] ; then 
        echo "[Using default value] STAGE_REPO_NAME=rackhd-staging!"
        STAGE_REPO_NAME=rackhd-staging
    fi

    if [ ! -n "${MANIFEST_FILE}" ]; then
        echo "[NOTE] it's assumed all RackHD sub repos are already cloned in $CLONE_DIR"
    fi
    if [ ! -n "${WORKDIR}" ]; then
        echo "[Error]Arguments WORKDIR is required"
        exit 1
    fi 

}


########################################################
#
# Main
#
########################################################

main(){
    echo "docker build start to parse arguments."
    parseArguments "$@"

    local basedir=$(cd $(dirname "$0");pwd)
    local on_build_config_dir=${basedir}/../../../../

    echo "clone code from manifest start."
    # if MANIFEST_FILE is blank, then we use local dir instead of re-clone
    if [ -n "$MANIFEST_FILE" ]; then
         cloneCodeFromManifest "$on_build_config_dir"  "$MANIFEST_FILE"  $CLONE_DIR
    fi

    echo using artifactory : $ARTIFACTORY_URL

    echo "on-imagebuilder-versino generator start."
    # rsync -r $CLONE_DIR/RackHD/ ./build/ #######TODO, we need to find out what's the purpose of ./build and rsync###########
    local on_imagebuilder_version=$( ${on_build_config_dir}/build-release-tools/HWIMO-BUILD \
    ${on_build_config_dir}/build-release-tools/application/version_generator.py \
    --repo-dir $CLONE_DIR/on-imagebuilder)

    #Download static files from Artifactory

    #build static files
    local http_static_dir=$CLONE_DIR/on-imagebuilder/common
    rm    -rf $http_static_dir
    mkdir -p $http_static_dir
    local tftp_static_dir=$CLONE_DIR/on-imagebuilder/pxe
    rm    -rf $tftp_static_dir
    mkdir -p $tftp_static_dir

    #Download deb,
    #put the microkernel static files into them, so that they can be consumed in later docker-build step
    echo "Downloading static files from Artifactory."
    downloadOnImagebuilderFromDeb ${ARTIFACTORY_URL}  \
                                  ${on_imagebuilder_version} \
                                  ${STAGE_REPO_NAME}  \
                                  ${http_static_dir} \
                                  ${tftp_static_dir}

    #docker images build
    echo "docker images build start."
    local build_rec=${WORKDIR}/build_record
    buildDockers $CLONE_DIR build_rec

    # save docker image to tar
    echo "save docker image to tar:rackhd_docker_images.tar."
    local image_list=`cat ${build_rec} | xargs`
    docker save -o ${WORKDIR}/rackhd_docker_images.tar $image_list

    echo "$0 done."
}

main "$@"
