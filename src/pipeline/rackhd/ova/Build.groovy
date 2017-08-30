package pipeline.rackhd.ova

def execute(){
  def shareMethod = new pipeline.common.ShareMethod()

  def label_name = "packer_ova"
  lock(label: label_name, quantity: 1){
    node_name = shareMethod.occupyAvailableLockedResource(label_name, [])
    node(node_name){
      ws{
          withEnv([
              "RACKHD_COMMIT=${env.RACKHD_COMMIT}",
              "RACKHD_VERSION=${env.RACKHD_VERSION}",
              "IS_OFFICIAL_RELEASE=${env.IS_OFFICIAL_RELEASE}",
              "OVA_CACHE_BUILD=${env.OVA_CACHE_BUILD}",
              "OS_VER=${env.OS_VER}",
              "BUILD_TYPE=vmware",
              "ARTIFACTORY_URL=${env.ARTIFACTORY_URL}",
              "STAGE_REPO_NAME=${env.STAGE_REPO_NAME}",
              "DEB_COMPONENT=${env.DEB_COMPONENT}",
              "DEB_DISTRIBUTION=trusty"]) {

              deleteDir()

              def libDir = "$WORKSPACE/on-build-config"
              shareMethod.checkoutOnBuildConfig(libDir)

              // clone packer scripts
              def url = "https://github.com/RackHD/RackHD.git"
              def branch = "${env.RACKHD_COMMIT}"
              def rackhdDir = "build"
              def cacheImageDir = "cache_image"
              shareMethod.checkout(url, branch, rackhdDir)

              // Test jenkins server doesn't use OVA cache build
              if ("$OVA_CACHE_BUILD" == "true"){
                  shareMethod.copyArtifact("$OVA_CACHE_BUILD", cacheImageDir)
              }

              timeout(180){
                  sh """#!/bin/bash
                  set -x
                  ./on-build-config/src/pipeline/rackhd/ova/build.sh \
                  --WORKSPACE $WORKSPACE \
                  --CACHE_IMAGE_DIR $cacheImageDir \
                  --RACKHD_DIR $rackhdDir \
                  --ON_BUILD_CONFIG_DIR $libDir \
                  --IS_OFFICIAL_RELEASE $IS_OFFICIAL_RELEASE \
                  --BUILD_TYPE $BUILD_TYPE \
                  --RACKHD_VERSION $RACKHD_VERSION \
                  --OS_VER $OS_VER \
                  --ARTIFACTORY_URL $ARTIFACTORY_URL \
                  --STAGE_REPO_NAME $STAGE_REPO_NAME \
                  --DEB_DISTRIBUTION $DEB_DISTRIBUTION \
                  --DEB_COMPONENT $DEB_COMPONENT
                  """
              }
              sh """cd $rackhdDir/packer && touch a.ova"""
              stash name: 'ova', includes: """$rackhdDir/packer/*.ova"""
              archiveArtifacts """$rackhdDir/packer/*.ova, $rackhdDir/packer/*.log, $rackhdDir/packer/*.md5, $rackhdDir/packer/*.sha"""

              env.OVA_STASH_NAME="ova"
              env.OVA_PATH="$rackhdDir/packer/*.ova"
          }
      }
    }
  }
}
