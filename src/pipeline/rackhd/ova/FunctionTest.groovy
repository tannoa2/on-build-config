package pipeline.rackhd.ova

def keepEnv(String library_dir, boolean keep_env, int keep_minutes, String test_target, String test_name){
    if(keep_env){
        def message = "Job Name: ${env.JOB_NAME} \n" + "Build Full URL: ${env.BUILD_URL} \n" + "Status: FAILURE \n" + "Stage: $test_target/$test_name \n" + "Node Name: $NODE_NAME \n" + "Reserve Duration: $keep_minutes minutes \n"
        echo "$message"
        slackSend "$message"
        sleep time: keep_minutes, unit: 'MINUTES'
    }
}

def runTest(String stack_type, String test_name, ArrayList<String> used_resources, Map ova_dict, boolean keep_env_on_failure, int keep_minutes,String ova_url=""){
    def shareMethod = new pipeline.common.ShareMethod()
    String test_target = "ova"
    def fit_configure = new pipeline.fit.FitConfigure(stack_type, test_target, test_name)
    def fit_init_configure = new pipeline.fit.FitConfigure(stack_type, test_target, "INIT")
    fit_configure.configure()
    fit_init_configure.configure()
    String node_name = ""
    String label_name = fit_configure.getLabel()
    try{
        lock(label:label_name,quantity:1){
            node_name = shareMethod.occupyAvailableLockedResource(label_name, used_resources)
            node(node_name){
                deleteDir()
                def fit = new pipeline.fit.FIT()
                def virtual_node = new pipeline.nodes.VirtualNode()
                def rackhd_deployer = new pipeline.rackhd.ova.Deploy()
                String library_dir = "$WORKSPACE/on-build-config"
                shareMethod.checkoutOnBuildConfig(library_dir)
                String ova_path = ""
                if (ova_url != ""){
                    ova_path = ova_url
                } else {
                    ova_path = shareMethod.unstashFile(ova_dict, "$WORKSPACE")
                }

                String rackhd_dir = "$WORKSPACE/RACKHD"
                shareMethod.checkout("https://github.com/changev/RackHD.git", "debug/ssh", rackhd_dir)

                boolean ignore_failure = false
                String target_dir = test_target + "/" + test_name + "_$NODE_NAME"

                try{
                    // clean up rackhd and virtual nodes
                    rackhd_deployer.cleanUp(library_dir, ignore_failure)
                    virtual_node.cleanUp(library_dir, ignore_failure)
                    // deploy rackhd and virtual nodes
                    rackhd_deployer.deploy(library_dir, ova_path)
                    virtual_node.deploy(library_dir)
                    //----------------------------------
                    virtual_node.remoteStartFetchLogs(target_dir, ova_dict, library_dir)
                    //----------------------------------
                    // run FIT test
                    fit.run(rackhd_dir, fit_init_configure)
                    fit.run(rackhd_dir, fit_configure)
                } catch(error){
                    keepEnv(library_dir, keep_env_on_failure, keep_minutes, test_target, test_name)
                    error("[ERROR] Failed to run test $test_name against $test_target with error: $error")
                } finally{
                    // archive rackhd logs
                    rackhd_deployer.archiveLogsToTarget(library_dir, target_dir)
                    fit.archiveLogsToTarget(target_dir, fit_configure)
                    virtual_node.remoteStopFetchLogs(target_dir, ova_dict, library_dir)
                    virtual_node.archiveLogsToTarget(target_dir)
                    // clean up rackhd and virtual nodes
                    ignore_failure = true
                    rackhd_deployer.cleanUp(library_dir, ignore_failure)
                    virtual_node.cleanUp(library_dir, ignore_failure)
                    // archive logs of virtual nodes and FIT
                }
            }
        }
    } finally{
        used_resources.remove(node_name)
    }
}

return this
