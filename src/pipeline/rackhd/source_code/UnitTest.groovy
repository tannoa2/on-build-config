package pipeline.rackhd.source_code

def testWithSudo(String repo_name, String repo_dir){
    try{
        withCredentials([
            usernamePassword(credentialsId: 'ff7ab8d2-e678-41ef-a46b-dd0e780030e1',
                passwordVariable: 'SUDO_PASSWORD',
                usernameVariable: 'SUDO_USER')
        ]){
            sh """#!/bin/bash -e
            trap 'echo $SUDO_PASSWORD|sudo -S find $repo_dir -group root -exec chown -R $USER:$USER {} +' SIGINT SIGTERM SIGKILL EXIT
            pushd $repo_dir
            echo $SUDO_PASSWORD |sudo -S ./HWIMO-TEST
            popd
            """
        }
    } finally{
        dir("$WORKSPACE"){
            archiveArtifacts "$repo_name/*.xml"
            junit "$repo_name/*.xml"
        }
    }
}

def testWithoutSudo(String repo_name, String repo_dir){
    try{
        sh """#!/bin/bash -ex
        pushd $repo_dir
        ./HWIMO-TEST
        popd
        """
    } finally{
        dir("$WORKSPACE"){
            archiveArtifacts "$repo_name/*.xml"
            junit "$repo_name/*.xml"
        }
    }
}

def runTest(String repo_name, Map manifest_dict, ArrayList<String> used_resources, boolean with_sudo){
    /*
    :manifest_dict is a map contains manifest stash name and stash path:
    :repo_name is a String which is the name of the repository 
    :used_resources is a array which records the used resources
    :with_sudo is a boolean variable. If true, run unit test with sudo, otherwise not.
    */
    def share_method = new pipeline.common.ShareMethod()
    def manifest = new pipeline.common.Manifest()
    String label_name="unittest"
    try{
        lock(label:label_name,quantity:1){
            node_name = share_method.occupyAvailableLockedResource(label_name, used_resources)
            node(node_name){
                deleteDir()
                String library_dir = "$WORKSPACE/on-build-config"
                share_method.checkoutOnBuildConfig(library_dir)
                String manifest_path = manifest.unstashManifest(manifest_dict, "$WORKSPACE")
                String repo_dir = "$WORKSPACE/$repo_name"
                manifest.checkoutTargetRepo( manifest_path, repo_name, repo_dir, library_dir)
                if(with_sudo){
                    testWithSudo(repo_name, repo_dir)
                } else {
                    testWithoutSudo(repo_name, repo_dir)
                }
            }
        }
    } finally{
        used_resources.remove(node_name)
    }
}

def runTestWithSudo(String repo_name, Map manifest_dict, ArrayList<String> used_resources){
    /*
    :manifest_dict is a map contains manifest stash name and stash path:
    :repo_name is a String which is the name of the repository
    :used_resources is a array which records the used resources
    */
    runTest(repo_name, manifest_dict, used_resources, true)
}

def runTestWithoutSudo(String repo_name, Map manifest_dict, ArrayList<String> used_resources){
    /*
    :manifest_dict is a map contains manifest stash name and stash path:
    :repo_name is a String which is the name of the repository
    :used_resources is a array which records the used resources
    */
    runTest(repo_name, manifest_dict, used_resources, false)
}

