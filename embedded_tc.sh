#!/bin/bash
# This script configures a Mellanox Bluefield card with a number of VFs using
# hardcoded vlans
# EMBEDDED CPU mode is assumed. Please ensure this
#
set -e

NUM_VFS=8
DEV=enp66s0f0

MLX_MGT_MAC=00:1a:ca:ff:ff:02

add_udev_rule (){
	cat >/etc/udev/rules.d/91-tmfifo_net.rules <<EOF
SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="00:1a:ca:ff:ff:02", ATTR{type}=="1", NAME="tmfifo_net0"
EOF
	chmod +x /etc/udev/rules.d/91-tmfifo_net.rules
        udevadm control --reload-rules
}

nic_conf () {
	add_udev_rule
        modinfo rshim-net
        if [ $? != 0 ]; then
		echo "Build and install mellanox rshim drivers first"
		exit 1
	fi
        # Reload the driver to ensure the interface get's renamed
	modprobe -r rshim-net || true
	modprobe -r rshim || true
	modprobe -r rshim-pcie || true
	modprobe -v rshim
	modprobe -v rshim-net
	modprobe -v rshim-pcie
	sleep 5
	ip link set tmfifo_net0 up
	nmcli device set tmfifo_net0 managed no
	# The internal IP address is hardcoded to 192.168.100.2
	ip addr add 192.168.100.1/30 dev tmfifo_net0
}

run_in_nic () {
	local cmd=$@
	#echo "Running command ${cmd}"
	local out=$(eval ssh root@192.168.100.2 -o StrictHostKeyChecking=no $cmd)
	local ret=$?
	if [ $ret != 0 ]; then
		echo "Command failed returned ${ret}"
		echo "stout: $out"
	fi
	echo "${out}"
}

get_hardcoded_vlan() {
	local vfid=$1
	let vlan_id=100+10*${vfid}
	echo ${vlan_id}
}

echo 0 > /sys/class/net/${DEV}/device/sriov_numvfs
echo ${NUM_VFS} > /sys/class/net/${DEV}/device/sriov_numvfs

echo "Configuring NIC management interface"
nic_conf

echo "Setting flow sterring rules"

run_in_nic "tc qdisc add dev p0 ingress"
run_in_nic "tc filter del dev p0 ingress"
run_in_nic "systemctl stop openvswitch"

for i in $(seq 0 $((${NUM_VFS} -1))); do
	run_in_nic "tc qdisc del dev pf0vf${i} ingress"
	run_in_nic "tc qdisc add dev pf0vf${i} ingress"
	vlan_id=$(get_hardcoded_vlan ${i})

        echo "Configuring VF ${i} with vlan ${vlan_id} "
	run_in_nic "tc filter add dev pf0vf${i} parent ffff: \
		flower \
		skip_sw \
		action vlan push id ${vlan_id} \
		action mirred egress redirect dev p0"

	run_in_nic "tc filter add dev p0 protocol 802.1Q parent ffff: \
		flower \
		skip_sw \
		vlan_id ${vlan_id} \
		vlan_prio 0 \
		action vlan pop \
		action mirred egress redirect dev pf0vf${i}"
done

