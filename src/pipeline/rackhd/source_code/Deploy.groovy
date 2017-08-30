package pipeline.rackhd.source_code

def deploy(String library_dir, String manifest_path){
    /*
    Deploy rackhd
    :library_dir: the directory of on-build-config
    :manifest_path: the absolute path of manifest file
    */
    String rackhd_code_dir = "$WORKSPACE/build-deps"
    def rackhd_builder = new pipeline.rackhd.source_code.Build()
    rackhd_builder.build(library_dir, manifest_path, rackhd_code_dir)
    withCredentials([
        usernamePassword(credentialsId: 'ff7ab8d2-e678-41ef-a46b-dd0e780030e1',
                         passwordVariable: 'SUDO_PASSWORD',
                         usernameVariable: 'SUDO_USER')])
    {
	step ([$class: 'CopyArtifact',
                projectName: 'Docker_Image_Build',
                target: "$WORKSPACE"])
        sh """#!/bin/bash -ex
        pushd $library_dir/src/pipeline/rackhd/source_code
        # Deploy image-service docker container which is from base image
        ./deploy.sh deploy -w $WORKSPACE -s $rackhd_code_dir -p $SUDO_PASSWORD -b $library_dir -i $WORKSPACE/rackhd_pipeline_docker.tar
        popd
        """
    }
}

def cleanUp(String library_dir, boolean ignore_failure){
    try{
        withCredentials([
            usernamePassword(credentialsId: 'ff7ab8d2-e678-41ef-a46b-dd0e780030e1',
                             passwordVariable: 'SUDO_PASSWORD',
                             usernameVariable: 'SUDO_USER')])
        {
            sh """#!/bin/bash -e
            pushd $library_dir/src/pipeline/rackhd/source_code
            # Clean up exsiting rackhd ci docker containers and images
            ./deploy.sh cleanUp -p $SUDO_PASSWORD
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
            dir(target_dir){
                sh """#!/bin/bash -e
                current_dir=`pwd`
                pushd $library_dir/src/pipeline/rackhd/source_code
                # export log of rackhd
                ./deploy.sh exportLog -p $SUDO_PASSWORD -l \$current_dir
                popd
                """
            }
            archiveArtifacts "$target_dir/*.log"
        }
    } catch(error){
        echo "[WARNING]Caught error during archive artifact of rackhd to $target_dir: ${error}"
    }
}

return this
