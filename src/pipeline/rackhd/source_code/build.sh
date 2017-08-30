#!/bin/bash -e

#############################################
#
# Global Variable
############################################
REPOS=("on-http" "on-taskgraph" "on-dhcp-proxy" "on-tftp" "on-syslog")

#########################################
#
#  Usage
#
#########################################
Usage(){
    echo "Function: this script is used to clone and build(npm install) RackHD according to Manifest"
    echo "usage: $0 [arguments]"
    echo "    mandatory arguments:"
    echo "      --TARGET_DIR: the directory of the output which contains all the RackHD repositories, it's required"
    echo "      --MANIFEST_FILE, the absolute path of manifest file, it's required."
    echo "      --ON_BUILD_CONFIG_DIR, the absolute path of on-build-config, it's required."
    echo "    Optional Arguments:"
    echo "      --INTERNAL_HTTP_ZIP_FILE_URL: where a prebuild http zip file locates"
    echo "      --INTERNAL_TFTP_ZIP_FILE_URL: where a prebuild tftp zip file locates"
    echo "      --HTTP_STATIC_FILES: addtional file list of http static files to be downloaded"
    echo "      --TFTP_STATIC_FILES: addtional file list of tftp static files to be downloaded"
}

########################################
wget_download(){
    argv=($@)
    argc=$#
    retry_time=5
    remote_file=${argv[$(($argc -1 ))]} # not accurate enough..
    echo "[Info] Downloading ${remote_file}"
  
    # -c  resume getting a partially-downloaded file.
    # -nv reduce the verbose output
    # -t 5  the retry counter
    wget -c -t ${retry_time} -nv $@  # $@ means all function arguments from $1 to $n
  
    if [ $? -ne 0 ]; then
        echo "[Error]: wget download failed: ${remote_file}"
        exit 2
    else
        echo "[Info] wget download successfully ${remote_file}"
    fi
    local_file=${remote_file##*/}
    if [[ $remote_file == *zip* ]]; then
        echo "[Info] Checking zip file integrity for ${remote_file}"
        unzip -t $local_file
        if [ $? -ne 0 ]; then
            echo "[Error] the download file(${remote_file}) is incompleted !"
            exit 3
        fi
    fi
}

dlHttpFiles() {
    dir=${TARGET_DIR}/on-http/static/http/common
    mkdir -p ${dir} && cd ${dir}
    if [ -n "${INTERNAL_HTTP_ZIP_FILE_URL}" ]; then
        # use INTERNAL TEMP SOURCE
        wget_download ${INTERNAL_HTTP_ZIP_FILE_URL}
        unzip common.zip && mv common/* . && rm -rf common
    else
        # pull down index from bintray repo and parse files from index
        wget_download --no-check-certificate https://dl.bintray.com/rackhd/binary/builds/ && \
            exec  cat index.html |grep -o href=.*\"|sed 's/href=//' | sed 's/"//g' > files
        for i in `cat ./files`; do
            wget_download --no-check-certificate https://dl.bintray.com/rackhd/binary/builds/${i}
        done
        # attempt to pull down user specified static files
        for i in ${HTTP_STATIC_FILES}; do
            wget_download --no-check-certificate https://bintray.com/artifact/download/rackhd/binary/builds/${i}
        done
    fi
}

dlTftpFiles() {
    dir=${TARGET_DIR}/on-tftp/static/tftp
    mkdir -p ${dir} && cd ${dir}
    if [ -n "${INTERNAL_TFTP_ZIP_FILE_URL}" ]; then
        # use INTERNAL TEMP SOURCE
        wget_download ${INTERNAL_TFTP_ZIP_FILE_URL}
        unzip pxe.zip && mv pxe/* . && rm -rf pxe pxe.zip
    else
        # pull down index from bintray repo and parse files from index
        wget_download --no-check-certificate https://dl.bintray.com/rackhd/binary/ipxe/ && \
            exec  cat index.html |grep -o href=.*\"|sed 's/href=//' | sed 's/"//g' > files
        for i in `cat ./files`; do
            wget_download --no-check-certificate https://dl.bintray.com/rackhd/binary/ipxe/${i}
        done
        # attempt to pull down user specified static files
        for i in ${TFTP_STATIC_FILES}; do
            wget_download --no-check-certificate https://bintray.com/artifact/download/rackhd/binary/ipxe/${i}
        done
    fi
}

checkoutPackages(){
    echo "[Info]Start to check out rackhd packages...."
    pushd ${ON_BUILD_CONFIG_DIR}
    ./build-release-tools/HWIMO-BUILD ./build-release-tools/application/reprove.py \
    --manifest ${MANIFEST_FILE} \
    --builddir ${TARGET_DIR} \
    --jobs 8 \
    --force \
    checkout \
    packagerefs
}

buildPackages(){
    echo "[Info]Start to run npm install...."
    local pid_arr=()
    local cnt=0
    #### NPM Install Parallel ######
    for i in ${REPOS[@]}; do
        pushd ${TARGET_DIR}/${i}
        echo "[${i}]: running :  npm install --production"
        npm install --production &
        # run in background, save its PID into pid_array
        pid_arr[$cnt]=$!
        cnt=$(( $cnt + 1 ))
        popd
    done

    ## Wait for background npm install to finish ###
    for index in $(seq 0 $(( ${#pid_arr[*]} -1 ))  );
    do
        wait ${pid_arr[$index]} # Wait for background running 'npm install' process
        echo "[${REPOS[$index]}]: finished :  npm install"
        if [ "$?" != "0" ] ; then
            echo "[Error] npm install failed for repo:" ${REPOS[$index]} ", Abort !"
            exit 3
        fi
    done
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
            --TARGET_DIR )                  shift
                                            TARGET_DIR=$1
                                            ;;
            --MANIFEST_FILE )               shift
                                            MANIFEST_FILE=$1
                                            ;;
            --ON_BUILD_CONFIG_DIR )         shift
                                            ON_BUILD_CONFIG_DIR=$1
                                            ;;
            --INTERNAL_HTTP_ZIP_FILE_URL )  shift
                                            INTERNAL_HTTP_ZIP_FILE_URL=$1
                                            ;;
            --INTERNAL_TFTP_ZIP_FILE_URL )  shift
                                            INTERNAL_TFTP_ZIP_FILE_URL=$1
                                            ;;
            --HTTP_STATIC_FILES )           shift
                                            HTTP_STATIC_FILES=$1
                                            ;;
            --TFTP_STATIC_FILES )           shift
                                            TFTP_STATIC_FILES=$1
                                            ;;
            * )                             Usage
                                            exit 1
        esac
        shift
    done

    if [ ! -n "${TARGET_DIR}" ] ; then 
        echo "[Error]Arguments TARGET_DIR is required!"
        Usage
        exit 1
    fi

    if [ ! -n "${MANIFEST_FILE}" ]; then
        echo "[Error]Arguments MANIFEST_FILE is required"
        Usage
        exit 1
    fi

    if [ ! -n "${ON_BUILD_CONFIG_DIR}" ]; then
        echo "[Error]Arguments ON_BUILD_CONFIG_DIR is required"
        Usage
        exit 1
    fi
}

########################################################
#
# Main
#
######################################################
main(){
    parseArguments "$@"
    checkoutPackages
    buildPackages
    dlTftpFiles
    dlHttpFiles
}

main "$@"
