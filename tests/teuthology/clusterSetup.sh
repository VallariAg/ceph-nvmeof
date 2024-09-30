#!/bin/bash

NVMEOF_VERSION=$1
if [ "$2" = "latest" ]; then
    CEPH_SHA=$(curl -s https://shaman.ceph.com/api/repos/ceph/main/latest/centos/9/ | jq -r ".[] | select(.archs[] == \"$(uname -m)\" and .status == \"ready\") | .sha1")
else
    CEPH_SHA=$2
fi

IP_ADDRESS=$(hostname -I)
HOSTNAME=$(hostname)

# install cephadm
mkdir /cephadm
cd /cephadm
curl --silent --remote-name --location https://download.ceph.com/rpm-18.2.2/el9/noarch/cephadm
chmod +x cephadm

# bootstrap ceph cluster
sudo ./cephadm --image quay.ceph.io/ceph-ci/ceph:$CEPH_SHA \
    bootstrap \
    --single-host-defaults \
    --mon-ip $IP_ADDRESS \
    --allow-mismatched-release

sleep 30

# setup cluster
sudo ./cephadm shell ceph orch device ls 
sudo ./cephadm shell ceph orch device zap $HOSTNAME /dev/nvme0n1 --force
sleep 20
sudo ./cephadm shell ceph orch apply osd --all-available-devices
sleep 20
sudo ./cephadm shell ceph orch device ls
sudo ./cephadm shell ceph config set global log_to_file true
sudo ./cephadm shell ceph config set global mon_cluster_log_to_file true


# setup nvmeof
sudo ./cephadm shell ceph -s
sudo ./cephadm shell ceph config set mgr mgr/cephadm/container_image_nvmeof quay.io/ceph/nvmeof:latest
sudo ./cephadm shell ceph config get mgr mgr/cephadm/container_image_nvmeof
sudo ./cephadm shell ceph osd pool create mypool
sudo ./cephadm shell rbd pool init -p mypool
sudo ./cephadm shell ceph orch apply nvmeof mypool mygroup --placement="smithi188"
sleep 20
sudo ./cephadm shell ceph orch ls
sudo ./cephadm shell ceph orch ps
sudo ./cephadm shell rbd create mypool/myimage --size 8Gi
sudo ./cephadm shell rbd ls mypool
sudo ./cephadm shell ceph -s


# echo 'line 1, '"${kernel}"'
# line 2,
# line 3, '"${distro}"'
# line 4' > /etc/ceph/nvmeof.env

# echo '
# NVMEOF_GATEWAY_IP_ADDRESSES='"${$IP_ADDRESS}"'
# NVMEOF_GATEWAY_NAMES={",".join(gateway_names)}
# NVMEOF_DEFAULT_GATEWAY_IP_ADDRESS='"${$IP_ADDRESS}"'
# NVMEOF_CLI_IMAGE="{self.cli_image}"
# NVMEOF_SUBSYSTEMS_PREFIX={self.nqn_prefix}
# NVMEOF_SUBSYSTEMS_COUNT={self.subsystems_count}
# NVMEOF_NAMESPACES_COUNT={self.namespaces_count}
# NVMEOF_PORT={self.port}
# NVMEOF_SRPORT={self.srport}
# ' > /etc/ceph/nvmeof.env


