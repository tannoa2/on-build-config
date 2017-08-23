package pipeline.common
import java.io.File;

    //================================================================
    // it will output a manifest file({branch}-{day}), according to a template manifest (under build-release-tools/lib). and clone code to $target_dir
    //
    // Inputs:
    // 1. implicit     : template manifest file under build-release-tools/lib
    // 2. target_dir   : the dir which the code will be cloned to( clone will happen inside this function, so all thing dir will be deleted at the begining! ) , so that we can fetch the lastest commit from them
    // 3. on_build_config_dir: where on-build-config repo being cloned to ( should be prepared before using this function), so that the python scripts can be invoked
    // 4. branch       : from which branch to generate the manifest file
    // 5. date         : refer to generate_manifest.py for more detail
    // 6. timezone     : refer to generate_manifest.py for more detail
    //
    // Output:
    // 1. a manifest file generated in current dir
    // 2. return this manifest file name
    //======================================================================
    def generateManifest( String target_dir , String on_build_config_dir, String branch="master", String date="current", String timezone="+0800" ){

         sh """#!/bin/bash -ex
            ${on_build_config_dir}/build-release-tools/HWIMO-BUILD ${on_build_config_dir}/build-release-tools/application/generate_manifest.py \
            --branch $branch \
            --date $date \
            --timezone $timezone \
            --builddir $target_dir \
            --force \
            --jobs 8
            """
        // note: in sh """  """, the $ is a groovy resvered key. so you need to use \$ if you want shell logic like "echo ${shell_var}"
        fpath = sh (
                     script: """#!/bin/bash -e
                     set +x
                     arrBranch=(  \$(echo $branch | tr "/" "\n" ) )
                     slicedBranch=\${arrBranch[-1]}
                     manifest_file=\$( find -maxdepth 1 -name "\$slicedBranch-[0-9]*" -printf "%f\n" )
                     echo \$(pwd)/\$manifest_file
                     """,
                     returnStdout: true
               ).trim()
         if ( fpath == "" ){
            error("Manifest file generation failure !")
         }
         return fpath;
    }

    //==============================================================
    // publish a manifest file to Bintray
    //
    // Inputs:
    // 1. file_path:  the path (/path/to/your/file/file_name) of the manifest file
    // 2. on_build_config_dir: where on-build-config repo being cloned to ( should be prepared before using this function)
    // 3. the BINTRAY_API_KEY/BINTRAY_USERNAME will be obtained from Jenkins Credential Plugin
    //
    // Output:  N/A
    //===============================================================
    def publishManifest(String file_path, String on_build_config_dir ){
        withCredentials([
                usernamePassword(credentialsId: 'a94afe79-82f5-495a-877c-183567c51e0b',
                passwordVariable: 'BINTRAY_API_KEY',
                usernameVariable: 'BINTRAY_USERNAME')
        ]){
              String BINTRAY_SUBJECT = "rackhd"
              String BINTRAY_REPO = "binary"
              sh """#!/bin/bash -e
                    if [ ! -f $file_path ]; then
                        echo "[Error] $file_path not existing, abort! "
                        exit -1
                    fi

                    file_name=\$(basename $file_path)

                    ${on_build_config_dir}/build-release-tools/pushToBintray.sh \
                    --user $BINTRAY_USERNAME \
                    --api_key $BINTRAY_API_KEY \
                    --subject $BINTRAY_SUBJECT \
                    --repo $BINTRAY_REPO \
                    --package manifest \
                    --version \$file_name \
                    --file_path $file_path
              """

       }
    }
    //=============================================================
    // download a manifest from URL
    //
    // Inputs:
    // 1. url : the URL to be downloaded, typically from Bintray
    // 2. target_dir: the target folder to be downloaded( NOTE: it will always be a folder instead of a file! ), if folder not exist, wget will create for you if appliable.
    //
    // Outputs:
    // the path (/path/to/manifest_fname) of the downloaded file
    //
    //=============================================================
    def downloadManifest(String url, String target_dir){
        fname= sh ( script:  """var=$url &&   echo \"\${var##*/}\"  """, returnStdout: true ).trim()
        sh 'wget --retry-connrefused --waitretry=1 --read-timeout=20 --timeout=15 -t 1 ' +  "$url" + ' -P ' + "${target_dir}"

        return target_dir +  File.separator + fname 
    }


    // ==================================================================
    // stash a manifest file: to save the file(s) in Jenkins server for later usage from other vmslave
    //
    // Inputs: 
    // stash_name   : the "key" of the locker
    // manifest_path: where the manifest file is located
    //
    // Output:
    // a Groovy Map, in which the "stash_name" is the key, and "stash_path" is the path (useful to find the files after unstash)
    // ==================================================================
    def stashManifest(String stash_name, String manifest_path){
        file_path = manifest_path
        // using regex to check if manifest_path is absolute path, Note: Java File.isAbsolute is restriced in Jenkins runtime
        is_relative_path= sh (  returnStdout: true ,
                      script: """#!/bin/bash -e
                      if [[  \"$manifest_path\" != /* ]] || [ \"\$(basename $manifest_path)\" == $manifest_path ] ; then
                            echo yes;
                      fi""").trim()
        if ( is_relative_path != "yes" )
        {
             // *******************
             // NOTE: Jenkins Stash has limitation, it can't stash file either from a absolute path or file outside the Jenkins $WORKSPACE
             // here, WORKSPACE is a build-in variable in Jenkins runtime
             // *******************
             // and we will have to make it flat
             sh "cp $manifest_path $WORKSPACE"
             file_path = sh ( script: "echo \$(basename $manifest_path)",  returnStdout: true ).trim()
        }
        stash name: stash_name, includes: file_path
        manifest_dict = [:]
        manifest_dict["stash_name"] = stash_name
        manifest_dict["stash_path"] = file_path 
        return manifest_dict
    }

    //=============================================================
    // unstash a manifest file: to fetch the file(s) from Jenkins server
    //
    // Inputs:
    //  manifest_dict: the Groovy Map return from stashManifest()
    //  target_dir   : the target dir where the files being unstash (if not existing, Jenkins will create it for you)
    // Output:
    //  the path of the unstashed file
    //=============================================================
    def unstashManifest(Map manifest_dict, String target_dir){
        String stash_name    = manifest_dict["stash_name"]
        String manifest_path = manifest_dict["stash_path"]
        dir(target_dir){
            // if the target_dir was not existing, Groovy will create the folder for you
            unstash "$stash_name"
        }
        manifest_path = target_dir + File.separator + manifest_path
        return manifest_path.trim()
    }


    // ===================================================================
    // clone git repos and checkout branch accroding to manifest file
    // typically, target_dir= ${WORKSPACE}/build-deps
    //
    // Inputs:
    //  manifest_path: the manifest file's path
    //  target_dir :   where the codes being clonded to( Warning! All content under this folder will be deleted before clone!)
    //  on_build_config_dir:  where on-build-config repo being cloned to ( should be prepared before using this function)
    //
    // Output:   N/A
    // ===================================================================
    def checkoutAccordingToManifest(String manifest_path, String target_dir, String on_build_config_dir)
    {
        
        sh """#!/bin/bash -ex
        pushd $on_build_config_dir
        ./build-release-tools/HWIMO-BUILD ./build-release-tools/application/reprove.py \
        --manifest ${manifest_path} \
        --builddir ${target_dir} \
        --jobs 8 \
        --force \
        checkout \
        packagerefs
        """

        
    }
    // ===================================================================
    // checkout according to manifest, and return a specific repo's path
    //
    // Inputs:
    //  manifest_path : the manifest file's path
    //  target_dir    : where the codes being clonded to
    //  on_build_config_dir:  where on-build-config repo being cloned to ( should be prepared before using this function)
    //  repo_name     : if specific desired repo's name. its path will be returned in this function.
    //
    // Output:
    //  the specific repo's path
    // ===================================================================
    def checkoutTargetRepo(String manifest_path, String target_dir, String on_build_config_dir, String repo_name ){
        checkoutAccordingToManifest( manifest_path,  target_dir, on_build_config_dir  )
        String repo_dir =   target_dir + File.separator + repo_name
        return repo_dir
    }




// Unit Test as below , also can be an example //
/*
node {
        
        __on_build_config_dir="/tmp/x/on-build-config"
        sh "pushd $__on_build_config_dir/../  && git clone https://github.com/rackhd/on-build-config.git  && popd"
        _src_dir            ="/tmp/x/src"

        fname = generateManifest( _src_dir ,__on_build_config_dir )
        echo "$fname has been generated "

        publishManifest( fname, __on_build_config_dir )
        echo "published $fname to bintray"


        df = downloadManifest( "https://dl.bintray.com/rackhd/binary/master-20170821", "/tmp/x" )
        echo "Downloaded $df"

        dict = stashManifest('stash_manifest', df   )

        echo "Test different input type for stash"
        sh "cp $df ./test.manifest"
        sh "mkdir -p ttt && cp $df ./ttt/test.manifest"
        dict2 = stashManifest('stash_manifest2', "test.manifest"  )
        dict3 = stashManifest('stash_manifest3', "ttt/test.manifest"  )

        node("vmslave18") {
            sh 'mkdir -p /tmp/peter'
                mfile = unstashManifest( dict, "/tmp/peter")
                sh "mkdir -p /tmp/peter/src"
                sh 'cd /tmp/peter && git clone https://github.com/rackhd/on-build-config.git '
                ret = checkoutTargetRepo( mfile, "/tmp/peter/src", "/tmp/peter/on-build-config", "on-http" )
                echo "Result = $ret"
        }
}
*/
