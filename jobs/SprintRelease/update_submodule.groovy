
def submodule(String operation)
{


  node{
    withEnv([
        "tag_name=${tag_name}",
        "JUMP_VERSION=${JUMP_VERSION}",
        "BINTRAY_SUBJECT=${env.BINTRAY_SUBJECT}",
        "OPERATION=${operation}"])
    {
        deleteDir()
        dir("build-config"){
            checkout scm
        }
    
        withCredentials([
            usernameColonPassword(credentialsId: 'GITHUB_USER_PASSWORD_OF_JENKINSRHD',
                                  variable: 'JENKINSRHD_GITHUB_CREDS'),
            usernamePassword(credentialsId: 'a94afe79-82f5-495a-877c-183567c51e0b', 
                             passwordVariable: 'BINTRAY_API_KEY', 
                             usernameVariable: 'BINTRAY_USERNAME')
        ]){
            int retry_times = 3
            stage("${OPERATION} submodule"){
                withEnv(["MANIFEST_FILE_URL=${MANIFEST_FILE_URL}"]){
                    retry(retry_times){
                        timeout(5){
                            sh '''#!/bin/bash -ex
                            # Checkout code according to manifest file
                            curl --user $BINTRAY_USERNAME:$BINTRAY_API_KEY -L "$MANIFEST_FILE_URL" -o rackhd-manifest
                            pwd
                            ls -al
                            ./build-config/build-release-tools/HWIMO-BUILD build-config/build-release-tools/application/reprove.py \
                            --manifest rackhd-manifest \
                            --builddir b \
                            --git-credential https://github.com,JENKINSRHD_GITHUB_CREDS \
                            --jobs 8 \
                            --force \
                            checkout
                            '''
                        }
                    }

                    retry(retry_times){
                        timeout(5){
                            sh '''#!/bin/bash -ex
                            # Update the submodule according to the manifest file.
                            ./build-config/build-release-tools/HWIMO-BUILD build-config/build-release-tools/application/${OPERATION}_submodule.py \
                            --build-dir b \
                            --manifest rackhd-manifest \
                            --publish \
                            --version ${tag_name}\
                            --git-credential https://github.com,JENKINSRHD_GITHUB_CREDS
                            '''
                        }
                    }
                }
            }
            stage("Update Manifest"){
                retry(retry_times){
                    timeout(3){
                        sh './build-config/jobs/SprintRelease/update_manifest.sh'
                    }
                }
                // inject properties file as environment variables
                if(fileExists ('downstream_file')) {
                    def props = readProperties file: 'downstream_file';
                    if(props['MANIFEST_FILE_URL']) {
                        env.MANIFEST_FILE_URL = "${props.MANIFEST_FILE_URL}";
                    }
                    else{
                        error("Failed to Update manifest")
                    }
                }
            }
        }
    }
  }
}
return this
