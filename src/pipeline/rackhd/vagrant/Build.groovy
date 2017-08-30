package pipeline.rackhd.vagrant

def buildBoxFromOVF(String target_dir, String cache_image_dir, String os_ver, String rackhd_version, String rackhd_apt_repo, String rackhd_dir){
    // Build vagrant box
    timeout(60){
        sh """#!/bin/bash -ex
        pushd $rackhd_dir/packer
        ./build_box.sh --OS_VER $os_ver --RACKHD_VERSION $rackhd_version --DEBIAN_REPOSITORY "$rackhd_apt_repo" --CACHE_IMAGE_DIR $cache_image_dir/RackHD/packer/output-virtualbox-iso --TARGET_DIR $target_dir
        popd
        """
    }
}

def buildBoxFromISO(String target_dir, String os_ver, String rackhd_version, String rackhd_apt_repo, String rackhd_dir){
    // Build vagrant box
    timeout(60){
        sh """#!/bin/bash -ex
        pushd $rackhd_dir/packer
        ./build_box.sh --OS_VER $os_ver --RACKHD_VERSION $rackhd_version --DEBIAN_REPOSITORY "$rackhd_apt_repo" --TARGET_DIR $target_dir
        popd
        """
    }
}

def buildBox(String rackhd_url, String rackhd_commit, String rackhd_version, String rackhd_apt_repo, String os_ver, String cache_project_name=""){
    String label_name = "packer_vagrant"
    String box_name = ""
    def share_method = new pipeline.common.ShareMethod()
    lock(label:label_name,quantity:1){
        String node_name = share_method.occupyAvailableLockedResource(label_name, [])
        node(node_name){
            deleteDir()
            String rackhd_dir = "RackHD"
            String target_dir = "$WORKSPACE/vagrant"
            // Checkout RackHD
            share_method.checkout(rackhd_url, rackhd_commit, rackhd_dir)

            if(cache_project_name == ""){
                buildBoxFromISO(target_dir, os_ver, rackhd_version, rackhd_apt_repo, rackhd_dir)
            }
            else{
                String cache_image_dir = "$WORKSPACE/cache_image"
                // Copy ovf from the artifact of project VAGRANT_CACHE_BUILD
                step ([$class: 'CopyArtifact',
                projectName: "$cache_project_name",
                target: "$cache_image_dir"])
                buildBoxFromOVF(target_dir, cache_image_dir, os_ver, rackhd_version, rackhd_apt_repo, rackhd_dir)
            }
            dir(target_dir){
                box_name = sh( returnStdout: true, script: 'find -name *.box  -printf %f' ).trim()
                stash name: "vagrant", includes: "$box_name"
            }
            archiveArtifacts "vagrant/*.box, vagrant/*.log"
        }
    }
    vagrant_dict = [:]
    vagrant_dict["stash_name"] = "vagrant"
    vagrant_dict["stash_path"] = "$box_name"
    return vagrant_dict
}

