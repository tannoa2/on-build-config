package pipeline.rackhd.docker
def deploy(String library_dir, String log_dir, String rackhd_dir, String docker_tar_file){
    /*
    Deploy rackhd
    :library_dir: the directory of on-build-config
    :log_dir: the directory of log
    :rackhd_dir: the directory of rackhd located
    :docker_tar_file: where the docker image tar lies
    */
    withCredentials([
        usernamePassword(credentialsId: 'ff7ab8d2-e678-41ef-a46b-dd0e780030e1',
                         passwordVariable: 'SUDO_PASSWORD',
                         usernameVariable: 'SUDO_USER')]){
            timeout(90){
               sh """#!/bin/bash -ex
                    pushd $library_dir/src/pipeline/rackhd/docker
                    ./deploy.sh deploy -l $log_dir \
                     -r $rackhd_dir -o $library_dir \
                     -i $docker_tar_file -p $SUDO_PASSWORD
                    popd
               """
            }
        }


}

def cleanUp(String library_dir,String rackhd_dir, boolean ignore_failure){
    try{
        withCredentials([
            usernamePassword(credentialsId: 'ff7ab8d2-e678-41ef-a46b-dd0e780030e1',
                             passwordVariable: 'SUDO_PASSWORD',
                             usernameVariable: 'SUDO_USER')])
        {
            sh """#!/bin/bash -e
            pushd $library_dir/src/pipeline/rackhd/docker
            # Clean up exsiting rackhd ci docker containers and images
            ./deploy.sh cleanUp -r $rackhd_dir -p $SUDO_PASSWORD
            popd
            """
        } 
    }catch(error){
        if(ignore_failure){
            echo "[WARNING]: Failed to clean up rackhd with error: ${error}"
        } else{
            error("[ERROR]: Failed to clean up rackhd with error: ${error}")
        }
    }
}

def archiveLogsToTarget(String library_dir, String target_dir){
    try{
        withCredentials([
            usernamePassword(credentialsId: 'ff7ab8d2-e678-41ef-a46b-dd0e780030e1',
                             passwordVariable: 'SUDO_PASSWORD',
                             usernameVariable: 'SUDO_USER')])
        {
            sh """#!/bin/bash -e
            pushd $library_dir/src/pipeline/rackhd/docker
            # export log of rackhd
            ./deploy.sh exportLog -l "${WORKSPACE}/${target_dir}" -p $SUDO_PASSWORD 
            popd
            """
            archiveArtifacts "$target_dir/*.log"
            echo "[DEBUG]ArchiveArtifacts:$target_dir"
        }
    } catch(error){
        echo "[WARNING]Caught error during archive artifact of rackhd to $target_dir: ${error}"
    }
}

return this

