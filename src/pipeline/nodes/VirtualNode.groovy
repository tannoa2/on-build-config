package pipeline.nodes

def getVNodes(){
    def virtual_nodes = [:]
    def config_path = "pipeline/nodes/virtual_nodes.json"
    def share_method = new pipeline.common.ShareMethod()
    def vnodes = share_method.parseJsonResource(config_path)
    def names = vnodes.keySet()
    for(name in names){
        int node_count = vnodes[name]["count"]
        String ova_path = vnodes[name]["ova_path"]
        for(int i=0;i<node_count;i++){
            virtual_nodes["$name$i"] = ["name":"$name$i","ova_path":"$ova_path"]
        }
    }
    return virtual_nodes
}

def deploy(String library_dir){
    withEnv([
        "ESXI_HOST=${env.ESXI_HOST}", // environment from node configure
        "DATASTORE=${env.DATASTORE}",
        "NIC=${env.NIC}"
    ]){
        withCredentials([
            usernamePassword(credentialsId: 'ESXI_CREDS',
                             passwordVariable: 'ESXI_PASS',
                             usernameVariable: 'ESXI_USER')
        ]) {
            def virtual_nodes = getVNodes()
            def names = virtual_nodes.keySet()
            for(name in names){
                def vnode_name = "$NODE_NAME-" + virtual_nodes[name]["name"]
                def switch_name = "$NODE_NAME-switch"
                def ova_path = virtual_nodes[name]["ova_path"]
                sh """#!/bin/bash -ex
                pushd $library_dir/deployment
                ./deploy_vnodes.sh deploy -h "$ESXI_HOST" -u "$ESXI_USER" -p "$ESXI_PASS" -s "$switch_name" -n "$NIC" -d "$DATASTORE" -m "" -v "$vnode_name" -o "$ova_path" -b $library_dir
                popd
                """
            }
        }
    }
}

def cleanUp(String library_dir, boolean ignore_failure){
    try{
        withEnv([
            "ESXI_HOST=${env.ESXI_HOST}"
        ]){
            withCredentials([
                usernamePassword(credentialsId: 'ESXI_CREDS',
                                 passwordVariable: 'ESXI_PASS',
                                 usernameVariable: 'ESXI_USER')
            ]) {
                def virtual_nodes = getVNodes()
                def names = virtual_nodes.keySet()
                for(name in names){
                    def vnode_name = "$NODE_NAME-" + virtual_nodes[name]["name"]
                    sh """#!/bin/bash -ex
                    pushd $library_dir/deployment
                    ./deploy_vnodes.sh cleanUp -h "$ESXI_HOST" -u "$ESXI_USER" -p "$ESXI_PASS" -v "$vnode_name" -b $library_dir
                    popd
                    """
                }
            }
        }
    }catch(error){
        if(ignore_failure){
            echo "[WARNING]: Failed to clean up virtual nodes with error: ${error}"
        } else{
            error("[ERROR]: Failed to clean up virtual nodes with error: ${error}")
        }
    }
}

def startFetchLogs(String library_dir, String target_dir){
    try{
        withCredentials([
             usernamePassword(credentialsId: 'BMC_VNODE_CREDS',
                             passwordVariable: 'BMC_VNODE_PASSWORD',
                             usernameVariable: 'BMC_VNODE_USER')
        ]) {
            dir(target_dir){
                sh """#!/bin/bash -ex
                current_dir=`pwd`
                pushd $library_dir/deployment
                ./fetch_vnodes_log.sh start --LOG_DIR \$current_dir --BMC_ACCOUNT_LIST "$BMC_VNODE_USER:$BMC_VNODE_PASSWORD" --ON_BUILD_CONFIG_DIR $library_dir
                popd
                """
            }
        }
    } catch(error){
        echo "[WARNING] Failed to fetch logs of virtual nodes with error: $error"
    }
}

def stopFetchLogs(String library_dir, String target_dir){
    try{
        dir(target_dir){
            sh """#!/bin/bash -x
            set +e
            current_dir=`pwd`
            pushd $library_dir/deployment
            ./fetch_vnodes_log.sh stop --LOG_DIR \$current_dir
            popd
            """
        }
    } catch(error){
        echo "[WARNING] Failed to stop fetching logs of virtual nodes with error: $error"
    }
}

def remoteStartFetchLogs(String target_dir, Map remote_info, String library_dir=null){
    try{
       if(library_dir == null)
       {
         library_dir = "$WORKSPACE/on-build-config"
         new pipeline.common.ShareMethod().checkoutOnBuildConfig(library_dir)
       }
        withCredentials([
             usernamePassword(credentialsId: 'BMC_VNODE_CREDS',
                             passwordVariable: 'BMC_VNODE_PASSWORD',
                             usernameVariable: 'BMC_VNODE_USER')
        ]) {
              def remote_ip = remote_info["ip"]
              def remote_user = remote_info["username"]
              def remote_pass = remote_info["password"]
              dir(target_dir){
                sh """#!/bin/bash -ex
                  current_dir=`pwd`
                  pushd $library_dir/src/pipeline/nodes/ansible
                    echo "ova-post-test ansible_host=$remote_ip ansible_user=$remote_user ansible_ssh_pass=$remote_pass ansible_become_pass=$remote_pass" > hosts
                    ansible-playbook -i hosts main.yml --tags "start" --extra-vars "library_dir=$library_dir target_dir=\$current_dir BMC_CRED=$BMC_VNODE_USER:$BMC_VNODE_PASSWORD"
                  popd
                """
              }
        }
    } catch(error){
        echo "[WARNING] Failed to fetch logs of virtual nodes with error: $error"
    }
}

def remoteStopFetchLogs(String target_dir, Map remote_info, String library_dir=null){
    try{
        if(library_dir == null)
        {
          library_dir = "$WORKSPACE/on-build-config"
          new pipeline.common.ShareMethod().checkoutOnBuildConfig(library_dir)
        }
        def remote_ip = remote_info["ip"]
        def remote_user = remote_info["username"]
        def remote_pass = remote_info["password"]
        dir(target_dir){
          sh """#!/bin/bash -ex
            current_dir=`pwd`"/"
            pushd $library_dir/src/pipeline/nodes/ansible
              echo "ova-post-test ansible_host=$remote_ip ansible_user=$remote_user ansible_ssh_pass=$remote_pass ansible_become_pass=$remote_pass" > hosts
              ansible-playbook -i hosts main.yml --tags "stop" --extra-vars "target_dir=\$current_dir library_dir=$library_dir"
            popd
          """
        }
    } catch(error){
        echo "[WARNING] Failed to stop fetching logs of virtual nodes with error: $error"
    }
}

def archiveLogsToTarget(String target_dir){
    try{
        archiveArtifacts "$target_dir/*.log, $target_dir/*.raw, $target_dir/*.flv"
    } catch(error){
        echo "[WARNING] Failed to archive logs under $target_dir with error: $error"
    }
}
