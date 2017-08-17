package pipeline.rackhd.source_code

def build(String library_dir, String manifest_path, String target_dir){
    /*
    build rackhd
    :library_dir: the directory of on-build-config
    :manifest_path: the absolute path of manifest file
    */
    retry(3){
        withCredentials([
            string(credentialsId: 'INTERNAL_HTTP_ZIP_FILE_URL', variable: 'INTERNAL_HTTP_ZIP_FILE_URL'),
            string(credentialsId: 'INTERNAL_TFTP_ZIP_FILE_URL', variable: 'INTERNAL_TFTP_ZIP_FILE_URL')])
        {
            sh """#!/bin/bash -ex
            rm -rf $target_dir
            mkdir -p $target_dir
            bash $library_dir/src/pipeline/rackhd/source_code/build.sh --TARGET_DIR $target_dir --MANIFEST_FILE $manifest_path --ON_BUILD_CONFIG_DIR $library_dir --INTERNAL_HTTP_ZIP_FILE_URL $INTERNAL_HTTP_ZIP_FILE_URL --INTERNAL_TFTP_ZIP_FILE_URL $INTERNAL_TFTP_ZIP_FILE_URL
            """
        }
    }
}
return this
