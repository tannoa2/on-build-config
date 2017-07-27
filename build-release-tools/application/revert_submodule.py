#!/usr/bin/env python
# Copyright 2015-2016, EMC, Inc.

"""
The script will update the version of submodule of every project.

usage:
./on-build-config/build-release-tools/HWIMO-BUILD on-build-config/build-release-tools/application/revert_submodule.py
--build-dir d/ \
--publish \
--version release1.2\
--git-credential https://github.com,GITHUB \

The required parameters: 
build-dir: The top directory which stores all the cloned repositories
version: The new release version

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
import time
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
    parser.add_argument("--manifest",
                        help="manifest file",
                        action="append")
    parser.add_argument("--version",
                        help="The new release version",
                        action="append")



    parsed_args = parser.parse_args(args)
    return parsed_args

def get_current_submodule_list(submodules,repo_dir):
    """
    Parse the repo url to get the repo folder name
    """
    submodule_folders = []
    if len(submodules) == 0:
        return None
    try:
       submodules_list = submodules.split('\n')
       for item in submodules_list :
           if len(item)!= 0:
              submodule_item_list = item.split()
              submodule_folders.append(submodule_item_list[1])
    except KeyError as error:
        print "Fail to process the submodules of this repo name {0}".format(repo_dir)
    return submodule_folders
       
def get_previous_id(commit_info) :
    """
    Function is used to get the last commit id of update submodule
    """
    try:
        commit_info_list = commit_info.split('\n')
        item = commit_info_list[0]
        if len(item) != 0:
            item_list = item.split()
            return item_list[1]

    except Exception,e:
        return None
def subModulesExist(repo_dir,repo_operator):
    repo_operator.submodule_init(repo_dir)
    repo_operator.submodule_update(repo_dir)
    submodules_list = repo_operator.get_current_submodule(repo_dir)
    if len(submodules_list)==0:
        return None
    else:
        return submodules_list
def revert_commit_for_submodules_update(repo_dir,repo_operator,version):
    update_commit_message="update submodule for new commit {0}".format(version)
    commit_info = repo_operator.get_commit_of_update_submodule(repo_dir,update_commit_message)
    commit_id = get_previous_id(commit_info)
    if commit_id != None:
        repo_operator.revert_to_commit(repo_dir,commit_id)
     
def main():
    # parse arguments
    args = parse_command_line(sys.argv[1:])
    if args.publish:
        if args.git_credential:
            repo_operator = RepoOperator(args.git_credential)
        else:
            print "Error occurs when get crendtail in update submodule"
            sys.exit(1)
    else:
        repo_operator = RepoOperator(args.git_credential)
    if os.path.isdir(args.build_dir):
        for filename in os.listdir(args.build_dir):
            try:
                repo_dir = os.path.join(args.build_dir, filename)
                submodules_list= subModulesExist(repo_dir,repo_operator)
                if submodules_list is None:
                    continue
                #git pull is used to get the lastest code to make sure push successfully
                test_info = repo_operator.git_pull(repo_dir,"origin","master")
                revert_commit_for_submodules_update(repo_dir,repo_operator,args.version)
                if args.publish:
                    print "start to publish  revert update submodule in {0}".format(repo_dir)
                    commit_message = "revert update submodule for new commit {}".format(args.version)
                    repo_operator.push_repo_changes(repo_dir, commit_message)
            except Exception,e:
                print "Failed to revert update submodule of {0} due to {1}".format(filename, e)
                sys.exit(1)
    else:
        print "The argument build-dir must be a directory"
        sys.exit(1)

if __name__ == "__main__":
    main()
    sys.exit(0)
