#!/bin/bash

# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.

########################################################################
#
# Description:
#   Basic networking test that checks if VMs can send and receive multicast packets
#
# Steps:
#   Use ping to test multicast
#   On the 2nd VM: ping -I eth1 224.0.0.1 -c 299 > out.client &
#   On the TEST VM: ping -I eth1 224.0.0.1 -c 299 > out.client
#   Check results:
#   On the TEST VM: cat out.client | grep 0%
#   On the 2nd VM: cat out.client | grep 0%
#   If both have 0% packet loss, test is passed
#
########################################################################
function Execute_Validate_Remote_Command(){
    cmd_to_run=$1
    ssh -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no "$remote_user"@"$STATIC_IP2" $cmd_to_run
    if [ $? -ne 0 ]; then
        LogMsg "Could not enable ALLMULTI on VM2"
        SetTestStateAborted
        exit 0
    fi
}

#list all network interfaces without eth0
function ListInterfaces() {
    # Parameter provided in constants file
    #    ipv4 is the IP Address of the interface used to communicate with the VM, which needs to remain unchanged
    #    it is not touched during this test (no dhcp or static ip assigned to it)

    if [ "${ipv4:-UNDEFINED}" = "UNDEFINED" ]; then
        msg="The test parameter ipv4 is not defined in constants file!"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateAborted
        exit 30
    else

        CheckIP "$ipv4"
        if [ 0 -ne $? ]; then
            msg="Test parameter ipv4 = $ipv4 is not a valid IP Address"
            LogMsg "$msg"
            UpdateSummary "$msg"
            SetTestStateAborted
            exit 10
        fi

        # Get the interface associated with the given ipv4
        __iface_ignore=$(ip -o addr show | grep "$ipv4" | cut -d ' ' -f2)
    fi

    GetSynthNetInterfaces
    if [ 0 -ne $? ]; then
        msg="No synthetic network interfaces found"
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateFailed
        exit 10
    fi
    # Remove interface if present
    SYNTH_NET_INTERFACES=(${SYNTH_NET_INTERFACES[@]/$__iface_ignore/})

    if [ ${#SYNTH_NET_INTERFACES[@]} -eq 0 ]; then
        msg="The only synthetic interface is the one which LIS uses to send files/commands to the VM."
        LogMsg "$msg"
        UpdateSummary "$msg"
        SetTestStateAborted
        exit 10
    fi
    LogMsg "Found ${#SYNTH_NET_INTERFACES[@]} synthetic interface(s): ${SYNTH_NET_INTERFACES[*]} in VM"
}

remote_user=$(whoami)
. net_constants.sh || {
    echo "unable to source net_constants.sh!"
    echo "TestAborted" > state.txt
    exit 0
}
# Source utils.sh
. utils.sh || {
    echo "unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 0
}
# Source constants file and initialize most common variables
UtilsInit

ListInterfaces
test_iface=${SYNTH_NET_INTERFACES[*]}
CreateIfupConfigFile $test_iface static $STATIC_IP $NETMASK
if [ $? -ne 0 ];then
    LogMsg "Could not set static IP on VM1!"
    SetTestStateAborted
    exit 0
fi

# Configure VM1
ip link set dev $test_iface allmulticast on
if [ $? -ne 0 ]; then
    LogMsg "Could not enable ALLMULTI on VM1"
    SetTestStateAborted
    exit 0
fi

# Configure VM2
Execute_Validate_Remote_Command "ip link set dev $test_iface allmulticast on"
Execute_Validate_Remote_Command "echo '1' > /proc/sys/net/ipv4/ip_forward"
Execute_Validate_Remote_Command "ip route add 224.0.0.0/4 dev $test_iface"
Execute_Validate_Remote_Command "echo '0' > /proc/sys/net/ipv4/icmp_echo_ignore_broadcasts"
Execute_Validate_Remote_Command "ping -I $test_iface 224.0.0.1 -c 299 > out.client &"

# test ping
ping -I $test_iface 224.0.0.1 -c 99 > out.client
if [ $? -ne 0 ]; then
    LogMsg "Could not start ping on VM1 (STATIC_IP: ${STATIC_IP})"
    SetTestStateFailed
    exit 0
fi

LogMsg "ping was started on both VMs. Results will be checked in a few seconds"
sleep 5

# Check results - Summary must show a 0% loss of packets
multicastSummary=$(cat out.client | grep 0%)
if [ $? -ne 0 ]; then
    LogMsg "VM1 shows that packets were lost!"
    LogMsg "${multicastSummary}"
    SetTestStateFailed
    exit 0
fi

# Turn off dependency VM
ssh -i "$HOME"/.ssh/"$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no "$remote_user"@"$STATIC_IP2" "init 0"

LogMsg "Multicast summary"
LogMsg "${multicastSummary}"
LogMsg "Multicast packets were successfully sent, 0% loss"
SetTestStateCompleted
exit 0