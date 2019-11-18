#!/bin/bash
# This script configures a Mellanox card wit a number of VFs in switchdev mode in a host

set -e

usage() {
	echo "$0 PCIADDR [NUM_VFs]"
	echo "	PCIADDR: The PCI address of the PF, e.g: 0000:40:00.0"
	echo "	NUM_VFS (defaul = 4): Number of VFs to configure"
	exit 1
}
error() {
	echo $@
	exit 1
}

# FIXME: Not working right now
# The problem is we don't really know the switchid until the interface is configured and we can
# run ip link. So using the udev script at plugin time is not possible
#gen_udev_script() {
#	pf=$1
#	switchid=$(ip -d link show ${pf} | sed -n 's/.* switchid \([^ ]*\).*/\1/p')
#	[ -z ${switchid} ]  && error "cannot get switchid"
#	cat <<EOF > /etc/udev/rules.d/82-net-setup-link-mlx.rules
#SUBSYSTEM=="net", ACTION=="add", ATTR{phys_switch_id}=="${switchid}", ATTR{phys_port_name}!="", NAME="\$attr{phys_port_name}"
#EOF
#
#}

get_eswitch_mode() {
	echo $(devlink dev eswitch show pci/$(get_pci_addr ${pf}) | cut -d ' ' -f 3)
}

set_eswitch_mode() {
	pf=$1
	mode=$2
	devlink dev eswitch set pci/$(get_pci_addr ${pf})  mode ${mode}
#	devlink dev eswitch set pci/$(get_pci_addr ${pf})  encap disable
}

tc_offload() {
	pf=$1
	val=$(ethtool -k $pf | grep hw-tc-offload: | cut -d ':' -f 2 | tr -d '[:space:]')
	echo val
}

set_tc_offload() {
	pf=$1
	ethtool -K $pf hw-tc-offload on
}

get_pci_addr() {
	pf=$1
	vf=$2
	if [ -z $vf ]; then
		echo $(basename $(readlink /sys/class/net/${pf}/device))
	else
		echo $(basename $(readlink /sys/class/net/${pf}/device/virtfn${vf}))
	fi
}

# The the device name of the representor
get_representor() {
	pf=$1
	vfid=$2

	switchid=$(ip -d link show ${pf} | sed -n 's/.* switchid \([^ ]*\).*/\1/p')
	# FXME: The following code including pf0 is not portable
	portname="pf0vf${vfid}"
	for dev in $(ls -x /sys/class/net); do
		[[ -f /sys/class/net/${dev}/phys_port_name ]] || continue
		[[ -f /sys/class/net/${dev}/phys_switch_id ]] || continue
		phys_port_name=$(cat /sys/class/net/${dev}/phys_port_name 2> /dev/null || true)
		phys_switch_id=$(cat /sys/class/net/${dev}/phys_switch_id 2> /dev/null || true)
		if [ "${phys_port_name}" == "$portname" ] && [ "${phys_switch_id}" == "${switchid}" ]; then
			echo "$dev"
			return
		fi
	done
}

get_hardcoded_vlan() {
	vfid=$1
	let vlan_id=100+10*${vfid}
	echo ${vlan_id}
}

PCI_ADDR=$1
NUM_VFS=${2:-4}

[ -z ${PCI_ADDR} ] && usage

PF=$(ls -x /sys/bus/pci/devices/${PCI_ADDR}/net/)
echo 0 > /sys/class/net/${PF}/device/sriov_numvfs
PF=$(ls -x /sys/bus/pci/devices/${PCI_ADDR}/net/)
echo 4 > /sys/class/net/${PF}/device/sriov_numvfs
PF=$(ls -x /sys/bus/pci/devices/${PCI_ADDR}/net/)

num_vfs=$(cat /sys/class/net/${PF}/device/sriov_numvfs)
for i in $(seq 0 $(($num_vfs -1))); do
	echo "Unbinding VF ${i}"
	pci_addr=$(get_pci_addr ${PF} $i)
	echo $pci_addr >  /sys/bus/pci/drivers/mlx5_core/unbind
done
echo "Setting switchdev_mode"

set_eswitch_mode ${PF} switchdev
sleep 5
PF=$(ls -x /sys/bus/pci/devices/${PCI_ADDR}/net/)
nmcli device set ${PF} managed no
#gen_udev_script ${PF}
set_tc_offload ${PF}

for i in $(seq 0 $(($num_vfs -1))); do
	echo "Binding VF ${i}"
	pci_addr=$(get_pci_addr ${PF} $i)
	echo $pci_addr >  /sys/bus/pci/drivers/mlx5_core/bind
	#echo "Waiting for vf ${i} dev to be available "
	sleep 3
	devname=$(ls -x /sys/class/net/${PF}/device/virtfn${i}/net)
	[ -z "$devname" ] && error "Cannot get VF network device"
        set_tc_offload ${devname}
	nmcli device set ${devname} managed no
done


# TC
tc qdisc add dev ${PF} ingress
systemctl stop openvswitch

#OVS
#systemctl start openvswitch
#ovs-vsctl del-br br0
#ovs-vsctl add-br br0
#ovs-vsctl set Open_vSwitch . other_config:hw-offload=true
#systemctl start openvswitch
#ovs-vsctl add-port br0 ${PF}


for i in $(seq 0 $(($num_vfs -1))); do
	devname=$(ls -x /sys/class/net/${PF}/device/virtfn${i}/net)
	rep=$(get_representor ${PF} $i)
	vlan_id=$(get_hardcoded_vlan $i)
	echo "Configuring ${devname} (rep: ${rep} ) with vlan  ${vlan_id}"
	set_tc_offload ${rep}
	nmcli device set ${rep} managed no
	# TC
	tc qdisc add dev ${rep} ingress
	tc filter add dev ${PF} ingress prio 2 protocol 802.1Q flower skip_sw vlan_id ${vlan_id} action vlan pop action mirred egress redirect dev ${rep}
	tc filter add dev ${rep} ingress prio 2 flower skip_sw action vlan push id ${vlan_id} action mirred egress redirect dev ${PF}
        # OVS
	#ovs-vsctl add-port br0 ${rep} tag=${vlan_id}
done




