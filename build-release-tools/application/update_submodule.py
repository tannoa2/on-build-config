#!/usr/bin/env python
# Copyright 2015-2016, EMC, Inc.

"""
The script will update the version of submodule in all projects.  

usage:
./on-build-config/build-release-tools/HWIMO-BUILD on-build-config/build-release-tools/application/update_submodule.py
--build-dir d/ \
--manifest manifest \
--publish \
--version release1.2\
--git-credential https://github.com,GITHUB \

The required parameters: 
build-dir: The top directory which stores all the cloned repositories
version: The new release version
manifest: The manifest file , script will get the commit-id in manifest
The optional parameters:
publish: If true, the updated changlog will be push to github.
git-credential: url, credentials pair for the access to github repos.
                For example: https://github.com,GITHUB
                GITHUB is an environment variable: GITHUB=username:password
                If parameter publish is true, the parameter is required.
"""
import os
import sys
import argparse
from manifest import Manifest

try:
    from RepositoryOperator import RepoOperator
    import common
except ImportError as import_err:
    print import_err
    sys.exit(1)


def parse_command_line(args):
    """
    Parse script arguments.
    :return: Parsed args for assignment
    """
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest",
                        required=True,
                        help="the new manifest file",
                        action="store")
    parser.add_argument("--build-dir",
                        required=True,
                        help="Top level directory that stores all the cloned repositories.",
                        action="store")
    parser.add_argument("--publish",
                        help="Push the new manifest to github",
                        action='store_true')
    parser.add_argument("--git-credential",
                        help="Git credential for CI services",
                        action="append")
    parser.add_argument("--version",
                        help="The new release version",
                        action="append")


    parsed_args = parser.parse_args(args)
    return parsed_args
      
def get_manifest_commit_id(module_name,manifest) :
    """
    Function is used to get the manifest commit id in manifest file
    """
    repositories = manifest.repositories
    module_name = module_name + ".git"
    for repo in repositories :
        if module_name in repo.get("repository"):
            return repo.get("commit-id")

def main():
    # parse arguments
    args = parse_command_line(sys.argv[1:])
    try:
            manifest = Manifest(args.manifest)
            manifest.validate_manifest()
    except KeyError as error:
            print "Failed to create a Manifest instance for the manifest file {0} \nERROR:\n{1}"\
                  .format(args.manifest, error.message)
            sys.exit(1)


    if args.publish:
        if args.git_credential:
            repo_operator = RepoOperator(args.git_credential)
        else:
            print "Error occurs when get crendtail in update submodule"
            sys.exit(1)
    else:
        repo_operator = RepoOperator(args.git_credential)
    if os.path.isdir(args.build_dir):
        print args.build_dir
        for filename in os.listdir(args.build_dir):
            try:
                repo_dir = os.path.join(args.build_dir, filename)
                repo_operator.submodule_init(repo_dir)
                repo_operator.submodule_update(repo_dir) 
                submodules_list = repo_operator.get_current_submodule(repo_dir)
                if len(submodules_list)==0:
                    continue;
                for key in submodules_list:
                    commit_id = get_manifest_commit_id(key,manifest)
                    if commit_id != None:
                        sub_dir = repo_dir+"/"+key
                        repo_operator.checkout_to_commit(sub_dir,commit_id)
                if args.publish:
                    print "start to publish  update submodule in {0}".format(repo_dir)
                    commit_message = "update submodule for new commit {0}".format(args.version)
                    repo_operator.push_repo_changes(repo_dir, commit_message)
            except Exception,e:
                print "Failed to update submodule of {0} due to {1}".format(filename, e)
                sys.exit(1)
    else:
        print "The argument build-dir must be a directory"
        sys.exit(1)

if __name__ == "__main__":
    main()
    sys.exit(0)
