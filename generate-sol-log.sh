#!/bin/bash

#This script runs in virtualbox or any other machines on which vnodes IP can be found through arp.
#sol log of all vnodes will be generated and published to jenkins at the same time with vagrant.log

#bmc user/password list, "u1:p1 u2:p2 ..."
#build-config will generate this list through env vars
bmc_account_list="${BMC_ACCOUNT_LIST}"

#Generate sol log for all nodes.
#Use cmd 'arp' to get vnodes' IP and cause don't know nodes' number and when the node get IP by DHCP, 
#so retry several time ensure all nodes have got IP.
handled_ip_list=""
vnode_num=0
timeout=0
maxto=20
while [ ${timeout} != ${maxto} ]; do
    ip_list=`arp | awk '{print $1}' | xargs`
    echo "IP LIST: $ip_list"
    for ip in $ip_list; do
        if [[ "${ip%%.*}" == "172" ]] && [[ "$handled_ip_list" != *"$ip"* ]]; then
            ping -c 1 -w 5 $ip
            if [ $? == 0 ]; then
                for bmc in $bmc_account_list; do
                    echo "ipmi cmd: ipmitool -I lanplus -H $ip -U XXXXX -P XXXXX -R 1 -N 3 chassis power status"
                    ipmitool -I lanplus -H $ip -U ${bmc%:*} -P ${bmc#*:} -R 1 -N 3 chassis power status |grep on
                    if [ $? == 0 ]; then
                        #raw logs saved in /home/vagrant/src/, which is the $WORKSPACE/build-deps of host.
                        #in post-deploy raw logs are convert into html by ansi2html tool
                        cmd='ipmitool -I lanplus -H ${bmc_ip} -U ${bmc_user} -P ${bmc_password} sol activate |
                                    tr 'A-Z' 'a-z' |
                                    while IFS= read -r line; do 
                                        echo "$(date) $line"; 
                                    done > /home/vagrant/src/${vnode_num}.sol.log.raw'
                        #dump cmd to cmd.sh, replace vars with actual value.
                        echo -e "bmc_ip=$ip\nbmc_user=${bmc%:*}\nbmc_password=${bmc#*:}\nvnode_num=${vnode_num}"|\
                        sed 's/[\%]/\\&/g;s/\([^=]*\)=\(.*\)/s%${\1}%\2%/' > sed.script
                        echo $cmd | sed -f sed.script > cmd.sh
                        chmod oug+x cmd.sh
                        #run cmd.sh in screen, sol activate simplely run in background can't work.
                        screen -dmS sol bash cmd.sh
                        echo "The number of vnode $ip is $vnode_num"
                        handled_ip_list="$handled_ip_list $ip"
                        vnode_num=`expr ${vnode_num} + 1`
                    fi
                done
            fi  
        fi    
    done
    #after more than 5*20 seconds all nodes are believed have got the IP by DHCP
    sleep 5
    timeout=`expr ${timeout} + 1`
done
    
