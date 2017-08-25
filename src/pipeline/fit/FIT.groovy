package pipeline.fit

def configControlInterfaceIp(String rackhd_dir){
    dir(rackhd_dir){
        sh '''#!/bin/bash -ex
        echo 'SetupTestsConfig ...replace the 172.31.128.1 IP in test configs with actual DHCP port IP'
        RACKHD_DHCP_HOST_IP=$(ifconfig | awk '/inet addr/{print substr($2,6)}' |grep -m1 172.31.128)
        if [ "$RACKHD_DHCP_HOST_IP" == "" ]; then
             echo "[Error] There should be a NIC with 172.31.128.xxx IP in your OS."
             exit -2
        fi
        pushd test
        find ./ -type f -exec sed -i -e "s/172.31.128.1/172.31.128.250/g" {} +
        popd
        '''
    }
}

def run(String rackhd_dir, Object fit_configure){
    withCredentials([
        usernamePassword(credentialsId: 'ff7ab8d2-e678-41ef-a46b-dd0e780030e1',
                         passwordVariable: 'SUDO_PASSWORD',
                         usernameVariable: 'SUDO_USER')])
    {
        String group = fit_configure.getGroup()
        String stack = fit_configure.getStack()
        String log_level = fit_configure.getLogLevel()
        String extra_options = fit_configure.getExtraOptions()
        try{
            sh """#!/bin/bash -ex
            pushd $rackhd_dir/test
            ./runFIT.sh -p $SUDO_PASSWORD -g "$group" -s "$stack" -v $log_level -e "$extra_options" -w $WORKSPACE
            popd
            """
        } finally{
            dir("$WORKSPACE"){
                junit 'xunit-reports/*.xml'
            }
        }
    }
}

def archiveLogsToTarget(String target_dir, Object fit_configure){
    String name = fit_configure.getName()
    try{
        dir(target_dir){
            sh """#!/bin/bash
            set +e
            mv $WORKSPACE/xunit-reports/*.xml .
            """
        }
        archiveArtifacts "$target_dir/*.xml"
    } catch(error){
        echo "[WARNING]Caught error during archive artifact for $name: $error"
    }
}

