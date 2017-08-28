package pipeline.rackhd.npm


//=============================================================================================
// Publish NPM packages according to manifest file , to remote NPM registry ( it will clone code first, and run npm-publish)
//
// Inputs:
//  manifest_file - the manifest file contains all repo information(URL/commit/branch) which to be published, can be a local file or remote URL
//  is_offical_release  - the flag to tell if publishing a offical release or a dev build. the version naming will vary.
//  npm_registry  - the URL of the npm registry
//  npm_registry_token - the upload credential token of the npm registry
//  on_build_config_dir - the on-build-config dir where the python scripts come from. the on-build-config src code can be prepared before using this function, or this function will download latest src for you.)(by default: $WORKSPACE/on-build-config)
//  clone_dest_dir      - where the code will be cloned to, by default it is blank, and will use a temporary folder under /tmp to clone code.
//
// ===============================================================================================
//
//  Example Usage:
/
//  node
//    {
//        def manifest_file="https://dl.bintray.com/rackhd/binary/master-20170827"
//        def is_offical_release=false;
//
//        def npm_publisher = new pipeline.rackhd.npm.Publish()
//        withCredentials([
//                usernamePassword(credentialsId: '736849f6-ba2c-489d-b5ca-d1b1f4be2252', 
//                passwordVariable: 'NPM_TOKEN', 
//                usernameVariable: 'NPM_REGISTRY')])
//        {
//              npm_publisher.publish(manifest_file, is_offical_release, NPM_TOKEN, NPM_REGISTRY, "$WORKSPACE/on-build-config", "/tmp/clone_dir" )
//        }
//    }
//=============================================================================================
def publish(String manifest_file, Boolean is_offical_release, String  npm_registry , String npm_registry_token , String on_build_config_dir = "$WORKSPACE/on-build-config", String clone_dest_dir="" )
{
    deleteDir()

    if( false == fileExists("$on_build_config_dir/README.md")  )
    {
         // if the library folder is blank, then clone latest on-build-config in it
         def share_method = new pipeline.common.ShareMethod()
         share_method.checkoutOnBuildConfig(library_dir)
    }

    
    sh """#!/bin/bash -e

        # ------- 1 ------------
        # Pass in the Groovy Variables
        manifest_param=$manifest_file
        is_offical_release_param=$is_offical_release
        npm_registry_param=$npm_registry
        npm_token_param=$npm_registry_token
        lib_dir_param=$on_build_config_dir
        # Using passing in clone_dest_dir or using a temp folder
        if [ "$clone_dest_dir" == "" ]; then
              clone_dest_dir_param=\$(mktemp -d)
        else
              clone_dest_dir_param=$clone_dest_dir
              mkdir -p \$clone_dest_dir_param
        fi

        #------- 2 -------------
        #download or using local manifest file
        if [[ "\$manifest_param" == *"http://"* ]] || [[ "\$manifest_param" == *"https://"* ]]; then
             manifest_fname="\$clone_dest_dir_param/rackhd_manifest"
             curl -L  \$manifest_param -o \$manifest_fname
        else
             manifest_fname=\$manifest_param
        fi
         
        #------- 3 -------------
        #publish the NodeJS code in diff folders under clone_dest_dir( run npm publish inside each sub-folder) to npm registry

        \$lib_dir_param/build-release-tools/HWIMO-BUILD \
        \$lib_dir_param/build-release-tools/application/release_npm_packages.py \
        --build-directory \$clone_dest_dir_param \
        --manifest-file \$manifest_fname \
        --npm-credential \$npm_registry_param,\$npm_token_param \
        --jobs 8 \
        --is-official-release \$is_offical_release_param \
        --force

        #------- 4 ----------
        if [ "$clone_dest_dir" == "" ]; then
             rm -r \$clone_dest_dir_param # delete the temp folder
        fi

    """ 

}

