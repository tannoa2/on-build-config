package pipeline.common

def checkout(String url, String branch, String target_dir){
    checkout(
    [$class: 'GitSCM', branches: [[name: branch]],
    extensions: [[$class: 'RelativeTargetDirectory', relativeTargetDir: target_dir]],
    userRemoteConfigs: [[url: url]]])
}

def checkout(String url, String branch){
    checkout(
    [$class: 'GitSCM', branches: [[name: branch]],
    userRemoteConfigs: [[url: url]]])
}

def checkout(String url){
    checkout(url, "master")
}

def checkoutOnBuildConfig(String target_dir){
    String scm_url = scm.getUserRemoteConfigs()[0].getUrl()
    if(scm_url.contains("on-build-config")){
        dir(target_dir){
            checkout scm
        }
    } else{
        checkout("https://github.com/RackHD/on-build-config", "master", target_dir)
    }
}

def getLockedResourceName(String label_name){
    // Get the resource name whose label contains the parameter label_name
    // The locked resources of the build
    def resources=org.jenkins.plugins.lockableresources.LockableResourcesManager.class.get().getResourcesFromBuild(currentBuild.getRawBuild())
    def resources_name=[]
    for(int i=0;i<resources.size();i++){
        String labels = resources[i].getLabels();
        List label_names = Arrays.asList(labels.split("\\s+"));
        for(int j=0;j<label_names.size();j++){
            if(label_names[j]==label_name){
                resources_name.add(resources[i].getName());
            }
        }
    }
    return resources_name
}

def occupyAvailableLockedResource(String label_name, ArrayList<String> used_resources){
     // The locked resources whose label contains the parameter label_name
    resources = getLockedResourceName(label_name)
    def available_resources = resources - used_resources
    if(available_resources.size > 0){
        used_resources.add(available_resources[0])
        String resource_name = available_resources[0]
        return resource_name
    }
    else{
        error("There is no available resources for $label_name")
    }
}

def parseJsonResource(String resource_path){
    //Parse json file under resources directory to a dictionary
    //And return the dictionary
    def json_text = libraryResource(resource_path)
    def props = readJSON text: json_text
    return props
}

def saveDockerImage(String library_dir, String docker_name, String docker_tag, String target_docker_repo, String target_output_dir){
    withCredentials([
        usernamePassword(credentialsId: 'ff7ab8d2-e678-41ef-a46b-dd0e780030e1',
                         passwordVariable: 'SUDO_PASSWORD',
                         usernameVariable: 'SUDO_USER'),
        usernamePassword(credentialsId: 'rackhd-ci-docker-hub',
                         passwordVariable: 'DOCKERHUB_PASS',
                         usernameVariable: 'DOCKERHUB_USER')
    ]){
        dir("$target_output_dir"){
            sh """#!/bin/bash -ex
            current_dir=`pwd`
            pushd $library_dir/src/pipeline/common
            ./save_docker.sh -s $SUDO_PASSWORD -u $DOCKERHUB_USER -p $DOCKERHUB_PASS -r $target_docker_repo -n $docker_name -t $docker_tag -o \$current_dir
            popd
            """
        }
        archiveArtifacts "$target_output_dir/docker_tag.log"
    }
}

def sendResultToSlack(){
    try{
        if ("${currentBuild.result}" != "SUCCESS"){
            currentBuild.result = "FAILURE"
        }
        def message = "Job Name: ${env.JOB_NAME} \n" + "Build Full URL: ${env.BUILD_URL} \n" + "Status: " + currentBuild.result + "\n"
        echo "[INFO] Send message to slack:\n$message"
        slackSend "$message"
    } catch(error){
        echo "[WARNING] Caught: ${error}"
    }
}

def sendResultToMysql(boolean sendJenkinsBuildResults, boolean sendTestResults){
    try{
        if ("${currentBuild.result}" != "SUCCESS"){
            currentBuild.result = "FAILURE"
        }
        step([$class: 'VTestResultsAnalyzerStep', sendJenkinsBuildResults: sendJenkinsBuildResults, sendTestResults: sendTestResults])
    } catch(error){
        echo "[WARNING] Caught: ${error}"
    }
}

def unstashFile(Map stash_dict, String target_dir){
    String stash_name = stash_dict["stash_name"]
    String stash_path = stash_dict["stash_path"]
    dir(target_dir){
        unstash "$stash_name"

     }
    file_path = target_dir + File.separator + stash_path
    return file_path
}



