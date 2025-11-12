#!/bin/bash
set -xe


GW1_NAME=$(docker ps --format '{{.ID}}\t{{.Names}}' | awk '$2 ~ /nvmeof/ && $2 ~ /1/ {print $1}')
GW2_NAME=$(docker ps --format '{{.ID}}\t{{.Names}}' | awk '$2 ~ /nvmeof/ && $2 ~ /2/ {print $1}')

ip1="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$GW1_NAME")"
ip2="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$GW2_NAME")"

NUM_SUBSYSTEMS=3
NQN1="nqn.2016-06.io.spdk:cnode01" # auto-listeners 
NQN2="nqn.2016-06.io.spdk:cnode02" # auto-listeners with secure listeners 
NQN3="nqn.2016-06.io.spdk:cnode03" # normal listeners

SUBNET=$(echo $ip1 | grep -oE "^([0-9]{1,3}\.){3}")
SUBNET="${SUBNET}0/24"

echo "Subnet $SUBNET would be used to create 2 subsystems with auto-listeners $NQN1 (non-secure listeners) and $NQN2 (secure listeners)"
echo "And create $NQN3 with normal listeners"


test_listeners()
 {
   ip_1=$1
   ip_2=$2 # optional
   for i in $(seq $NUM_SUBSYSTEMS); do
      NQN="nqn.2016-06.io.spdk:cnode0$i"
      is_secure=false
      if [ "$NQN" -eq "$NQN2" ]; then
         is_secure=true 
      fi
      is_manual=false
      if [ "$NQN" -eq "$NQN3" ]; then
         is_manual=true
      fi 

      # CHECK 1: list listeners
      docker compose run -T --rm nvmeof-cli --server-address $ip_1 --server-port 5500 --output stdio --format json listener list -n $NQN > /tmp/listeners.txt 
      cat /tmp/listeners.txt
      [[ `cat /tmp/listeners.txt | jq -r '.status'` == "0" ]]
      [[ `cat /tmp/listeners.txt | jq -r '.listeners[0].trtype'` == "TCP" ]]
      [[ `cat /tmp/listeners.txt | jq -r '.listeners[0].adrfam'` == "ipv4" ]]
      [[ `cat /tmp/listeners.txt | jq -r '.listeners[0].traddr'` == "$ip_1" ]]
      [[ `cat /tmp/listeners.txt | jq -r '.listeners[0].trsvcid'` == "4420" ]]
      [[ `cat /tmp/listeners.txt | jq -r '.listeners[0].secure'` == "$is_secure" ]]
      [[ `cat /tmp/listeners.txt | jq -r '.listeners[0].active'` == "true" ]]
      [[ `cat /tmp/listeners.txt | jq -r '.listeners[0].manual'` == "$is_manual" ]]
      if [ -n "$ip_2" ]; then
         [[ `cat /tmp/listeners.txt | jq -r '.listeners[1].trtype'` == "TCP" ]]
         [[ `cat /tmp/listeners.txt | jq -r '.listeners[1].adrfam'` == "ipv4" ]]
         [[ `cat /tmp/listeners.txt | jq -r '.listeners[1].traddr'` == "$ip_2" ]]
         [[ `cat /tmp/listeners.txt | jq -r '.listeners[1].trsvcid'` == "4420" ]]
         [[ `cat /tmp/listeners.txt | jq -r '.listeners[1].secure'` == "$is_secure" ]]
         [[ `cat /tmp/listeners.txt | jq -r '.listeners[1].active'` == "false" ]]
         [[ `cat /tmp/listeners.txt | jq -r '.listeners[1].manual'` == "$is_manual" ]]
         [[ `cat /tmp/listeners.txt | jq -r '.listeners[2]'` == "null" ]]
      else
         [[ `cat /tmp/listeners.txt | jq -r '.listeners[1]'` == "null" ]]
      fi

      # CHECK 2: gw listener_info
      docker compose run -T --rm nvmeof-cli --server-address $ip_1 --server-port 5500 --output stdio --format json gw listener_info -n $NQN > /tmp/gw_listeners.txt
      cat /tmp/gw_listeners.txt
      [[ `cat /tmp/gw_listeners.txt | jq -r '.status'` == "0" ]]
      [[ `cat /tmp/gw_listeners.txt | jq -r '.gw_listeners[0].listener.trtype'` == "TCP" ]]
      [[ `cat /tmp/gw_listeners.txt | jq -r '.gw_listeners[0].listener.adrfam'` == "ipv4" ]]
      [[ `cat /tmp/gw_listeners.txt | jq -r '.gw_listeners[0].listener.traddr'` == "$ip_1" ]]
      [[ `cat /tmp/gw_listeners.txt | jq -r '.gw_listeners[0].listener.trsvcid'` == "4420" ]]
      [[ `cat /tmp/gw_listeners.txt | jq -r '.gw_listeners[0].listener.secure'` == "$is_secure" ]]
      [[ `cat /tmp/gw_listeners.txt | jq -r '.gw_listeners[0].listener.active'` == "true" ]]
      [[ `cat /tmp/gw_listeners.txt | jq -r '.gw_listeners[1]'` == "null" ]]

      if [ -n "$ip_2" ]; then
         docker compose run -T --rm nvmeof-cli --server-address $ip_2 --server-port 5500 --output stdio --format json gw listener_info -n $NQN > /tmp/gw_listeners.txt
         cat /tmp/gw_listeners.txt
         [[ `cat /tmp/gw_listeners.txt | jq -r '.gw_listeners[0].listener.trtype'` == "TCP" ]]
         [[ `cat /tmp/gw_listeners.txt | jq -r '.gw_listeners[0].listener.adrfam'` == "ipv4" ]]
         [[ `cat /tmp/gw_listeners.txt | jq -r '.gw_listeners[0].listener.traddr'` == "$ip_2" ]]
         [[ `cat /tmp/gw_listeners.txt | jq -r '.gw_listeners[0].listener.trsvcid'` == "4420" ]]
         [[ `cat /tmp/gw_listeners.txt | jq -r '.gw_listeners[0].listener.secure'` == "$is_secure" ]]
         [[ `cat /tmp/gw_listeners.txt | jq -r '.gw_listeners[0].listener.active'` == "true" ]]
         [[ `cat /tmp/gw_listeners.txt | jq -r '.gw_listeners[1]'` == "null" ]]
      fi
      # CHECK 3: nvme discover check
      # CHECK 4: nvme connect+list check

   done
}

# TEST 1: create auto-listeners and verify
echo "ℹ️ ℹ️ Start test (setup step):  create 2 subsystems with auto listeners and 1 normal subsystem with manual listeners:"

docker compose run -T --rm nvmeof-cli --server-address $ip2 --server-port 5500 subsystem add -n $NQN1 --no-group-append --network-mask $SUBNET
docker compose run -T --rm nvmeof-cli --server-address $ip2 --server-port 5500 subsystem add -n $NQN2 --no-group-append --network-mask $SUBNET --secure-listeners

docker compose run -T --rm nvmeof-cli --server-address $ip2 --server-port 5500 subsystem add -n $NQN3 --no-group-append
docker compose run --rm nvmeof-cli --server-address $ip2  --server-port 5500 listener add  --subsystem $NQN3 --host-name $GW1_NAME --traddr $ip1 --trsvcid 4420
docker compose run --rm nvmeof-cli --server-address $ip2  --server-port 5500 listener add  --subsystem $NQN3 --host-name $GW2_NAME --traddr $ip2 --trsvcid 4420

docker compose run -T --rm nvmeof-cli --server-address $ip2 --server-port 5500 --output stdio --format json subsystem list

echo "ℹ️ ℹ️  Create hosts"
for i in $(seq $NUM_SUBSYSTEMS); do
   NQN="nqn.2016-06.io.spdk:cnode0$i"
   docker compose run --rm nvmeof-cli --server-address $ip2 --server-port 5500 host add --subsystem $NQN --host-nqn ${NQN}host
done

echo "ℹ️ ℹ️  Create namespaces"
for i in $(seq $NUM_SUBSYSTEMS); do
   NQN="nqn.2016-06.io.spdk:cnode0$i"
   for num in $(seq 3); do
      image_name="demo_image$(expr \( $num + 5 \) \* $i)"
      echo $image_name
      docker compose  run --rm nvmeof-cli --server-address $ip2 --server-port 5500 namespace add --subsystem $NQN --rbd-pool rbd --rbd-image $image_name --size 10M --rbd-create-image --force
   done
done

test_listeners $ip2 $ip1


# TEST 2: scale-up / scale-down and verify
echo "ℹ️ ℹ️ Test auto-listeners for scale-up and scale-down"

docker compose exec -T ceph ceph nvme-gw delete $GW1_NAME rbd ''
echo "ℹ️  Wait for scale-down"
sleep 110

test_listeners $ip2

docker compose exec -T ceph ceph nvme-gw create $GW1_NAME rbd ''
echo "ℹ️ Wait for scale up"
sleep 200
test_listeners $ip2 $ip1


############################################################################################

echo "ℹ️ ℹ️  test passed"
exit 0
