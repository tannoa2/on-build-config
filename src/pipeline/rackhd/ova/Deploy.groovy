package pipeline.rackhd.ova

def deploy(String library_dir, String ova_path){
    /*
    Deploy rackhd
    :library_dir: the directory of on-build-config
    :ova_path: the absolute path of ova
    */

    withEnv([
        "EXTERNAL_VSWITCH=${env.EXTERNAL_VSWITCH}",
        "NODE_NAME=${env.NODE_NAME}",
        "DATASTORE=${env.DATASTORE}",
        "OVA_NET_INTERFACE=${env.OVA_NET_INTERFACE}",
        "DNS_SERVER_IP=${env.DNS_SERVER_IP}",
        "OVA_GATEWAY=${env.OVA_GATEWAY}",
        "ESXI_HOST=${env.ESXI_HOST}"
        ])
    {
        withCredentials([
            usernamePassword(credentialsId: 'OVA_CREDS',
                            passwordVariable: 'OVA_PASSWORD',
                            usernameVariable: 'OVA_USER'),
            usernamePassword(credentialsId: 'ESXI_CREDS',
                            passwordVariable: 'ESXI_PASS',
                            usernameVariable: 'ESXI_USER'),
            usernamePassword(credentialsId: 'ff7ab8d2-e678-41ef-a46b-dd0e780030e1',
                             passwordVariable: 'SUDO_PASSWORD',
                             usernameVariable: 'SUDO_USER'),
            string(credentialsId: 'vCenter_IP', variable: 'VCENTER_IP'),
            string(credentialsId: 'Deployed_OVA_INTERNAL_IP', variable: 'OVA_INTERNAL_IP')
        ]){
          sh """#!/bin/bash -ex
          pushd $library_dir/src/pipeline/rackhd/ova
          # Deploy rackhd ova
          if [ $EXTERNAL_VSWITCH == "null" ] || [ $EXTERNAL_VSWITCH == "" ]; then
              echo "Deploy ova with gateway network"
              EXTERNAL_VSWITCH="" \
              ./deploy.sh deploy -w $WORKSPACE -p $SUDO_PASSWORD -b $library_dir \
                                 -i $ova_path -n $NODE_NAME \
                                 -d $DATASTORE -eu $ESXI_USER -ep $ESXI_PASS -h $ESXI_HOST \
                                 -o $OVA_INTERNAL_IP -g $OVA_GATEWAY -ni $OVA_NET_INTERFACE \
                                 -ou $OVA_USER -op $OVA_PASSWORD -s $DNS_SERVER_IP
          else
             echo "Deploy ova with dhcp network"
            ./deploy.sh deploy -w $WORKSPACE -p $SUDO_PASSWORD -b $library_dir \
                               -i $ova_path  -n $NODE_NAME -d $DATASTORE \
                               -eu $ESXI_USER -ep $ESXI_PASS -h $ESXI_HOST \
                               -o $OVA_INTERNAL_IP -g $OVA_GATEWAY \
                               -ou $OVA_USER -op $OVA_PASSWORD
          fi
          popd
          """
        }
    }
}

def cleanUp(String library_dir, boolean ignore_failure=false){
    try{
        withEnv([
            "ESXI_HOST=${env.ESXI_HOST}",
            "NODE_NAME=${env.NODE_NAME}"
          ]){

        }
        withCredentials([
            usernamePassword(credentialsId: 'ESXI_CREDS',
                            passwordVariable: 'ESXI_PASS',
                            usernameVariable: 'ESXI_USER'),
            usernamePassword(credentialsId: 'ff7ab8d2-e678-41ef-a46b-dd0e780030e1',
                             passwordVariable: 'SUDO_PASSWORD',
                             usernameVariable: 'SUDO_USER')])
        {
            sh """#!/bin/bash -e
            pushd $library_dir/src/pipeline/rackhd/ova
            # Clean up exsiting ova
            ./deploy.sh cleanUp -p $SUDO_PASSWORD -b $library_dir -n $NODE_NAME \
                                -eu $ESXI_USER -ep $ESXI_PASS -h $ESXI_HOST
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
                           usernameVariable: 'SUDO_USER'),
          usernamePassword(credentialsId: 'OVA_CREDS',
                           passwordVariable: 'OVA_PASSWORD',
                           usernameVariable: 'OVA_USER'),
          string(credentialsId: 'Deployed_OVA_INTERNAL_IP', variable: 'OVA_INTERNAL_IP')])
      {
          dir(target_dir){
            sh """#!/bin/bash -e
            current_dir=`pwd`
            pushd $library_dir/src/pipeline/rackhd/ova
            # export log of rackhd
            ./deploy.sh exportLog -w $WORKSPACE -l \$current_dir -b $library_dir -p $SUDO_PASSWORD \
                                  -o $OVA_INTERNAL_IP -ou $OVA_USER -op $OVA_PASSWORD


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
