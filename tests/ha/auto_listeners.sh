#!/bin/bash
set -xe


GW1_NAME=$(docker ps --format '{{.ID}}\t{{.Names}}' | awk '$2 ~ /nvmeof/ && $2 ~ /1/ {print $1}')
GW2_NAME=$(docker ps --format '{{.ID}}\t{{.Names}}' | awk '$2 ~ /nvmeof/ && $2 ~ /2/ {print $1}')
# GW3_NAME=$(docker ps --format '{{.ID}}\t{{.Names}}' | awk '$2 ~ /nvmeof/ && $2 ~ /3/ {print $1}')

ip1="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$GW1_NAME")"
ip2="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$GW2_NAME")"
#ip3="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$GW3_NAME")"

NUM_SUBSYSTEMS=2
NQN1="nqn.2016-06.io.spdk:cnode01"
NQN2="nqn.2016-06.io.spdk:cnode02"
# NQN3="nqn.2016-06.io.spdk:cnode3"

SUBNET=$(echo $ip1 | grep -oE "^([0-9]{1,3}\.){3}")
SUBNET="${SUBNET}0/24"

echo "Subnet $SUBNET would be used to create 2 subsystems $NQN1 and $NQN2"

# HOSTNQN1="${NQN1}:host"
# HOSTNQN2="${NQN2}:host"



test_auto_listeners()
 {  
   # Parameters: secure (boolean)

   # CHECK 1: list listeners
    for i in $(seq $NUM_SUBSYSTEMS); do
      NQN="nqn.2016-06.io.spdk:cnode0$i"
      docker compose run -T --rm nvmeof-cli --server-address $ip2 --server-port 5500 --output stdio --format json listener list -n $NQN > /tmp/listeners.txt 
      # listener_list=$(docker compose run -T --rm nvmeof-cli --server-address $ip2 --server-port 5500 --output stdio --format json listener list -n $NQN)
      # echo "list listeners: "  $listener_list

      cat /tmp/listeners.txt
      [[ `cat /tmp/listeners.txt | jq -r '.status'` == "0" ]]
      [[ `cat /tmp/listeners.txt | jq -r '.listeners[0].trtype'` == "TCP" ]]
      [[ `cat /tmp/listeners.txt | jq -r '.listeners[0].adrfam'` == "ipv4" ]]
      [[ `cat /tmp/listeners.txt | jq -r '.listeners[0].traddr'` == "$ip1" ]]
      [[ `cat /tmp/listeners.txt | jq -r '.listeners[0].trsvcid'` == "4420" ]]
      [[ `cat /tmp/listeners.txt | jq -r '.listeners[0].secure'` == "false" ]]
      [[ `cat /tmp/listeners.txt | jq -r '.listeners[0].active'` == "true" ]]
      [[ `cat /tmp/listeners.txt | jq -r '.listeners[0].manual'` == "false" ]]
      [[ `cat /tmp/listeners.txt | jq -r '.listeners[1].trtype'` == "TCP" ]]
      [[ `cat /tmp/listeners.txt | jq -r '.listeners[1].adrfam'` == "ipv4" ]]
      [[ `cat /tmp/listeners.txt | jq -r '.listeners[1].traddr'` == "$ip2" ]]
      [[ `cat /tmp/listeners.txt | jq -r '.listeners[1].trsvcid'` == "4420" ]]
      [[ `cat /tmp/listeners.txt | jq -r '.listeners[1].secure'` == "false" ]]
      [[ `cat /tmp/listeners.txt | jq -r '.listeners[1].active'` == "true" ]]
      [[ `cat /tmp/listeners.txt | jq -r '.listeners[1].manual'` == "false" ]]
      [[ `cat /tmp/listeners.txt | jq -r '.listeners[2]'` == "null" ]]
      hostname20=`cat /tmp/listeners.txt | jq -r '.listeners[0].host_name'`
      hostname21=`cat /tmp/listeners.txt | jq -r '.listeners[1].host_name'`
      hostname22=`cat /tmp/listeners.txt | jq -r '.listeners[2].host_name'`

      # CHECK 2: gw listener_info
      docker compose run -T --rm nvmeof-cli --server-address $ip2 --server-port 5500 --output stdio --format json gw listener_info -n $NQN > /tmp/listeners.txt 
      cat /tmp/gw_listeners.txt
      [[ `cat /tmp/gw_listeners.txt | jq -r '.status'` == "0" ]]
      [[ `cat /tmp/gw_listeners.txt | jq -r '.gw_listeners[0].listener.trtype'` == "TCP" ]]
      [[ `cat /tmp/gw_listeners.txt | jq -r '.gw_listeners[0].listener.adrfam'` == "ipv4" ]]
      [[ `cat /tmp/gw_listeners.txt | jq -r '.gw_listeners[0].listener.traddr'` == "2001:db8::3" ]]
      [[ `cat /tmp/gw_listeners.txt | jq -r '.gw_listeners[0].listener.trsvcid'` == "4420" ]]
      [[ `cat /tmp/gw_listeners.txt | jq -r '.gw_listeners[0].listener.secure'` == "false" ]]
      [[ `cat /tmp/gw_listeners.txt | jq -r '.gw_listeners[0].listener.active'` == "true" ]]
      [[ `cat /tmp/gw_listeners.txt | jq -r '.gw_listeners[1].listener.trtype'` == "TCP" ]]
      [[ `cat /tmp/gw_listeners.txt | jq -r '.gw_listeners[1].listener.adrfam'` == "ipv4" ]]
      [[ `cat /tmp/gw_listeners.txt | jq -r '.gw_listeners[1].listener.traddr'` == "0.0.0.0" ]]
      [[ `cat /tmp/gw_listeners.txt | jq -r '.gw_listeners[1].listener.trsvcid'` == "4430" ]]
      [[ `cat /tmp/gw_listeners.txt | jq -r '.gw_listeners[1].listener.secure'` == "false" ]]
      [[ `cat /tmp/gw_listeners.txt | jq -r '.gw_listeners[1].listener.active'` == "true" ]]
      [[ `cat /tmp/gw_listeners.txt | jq -r '.gw_listeners[2]'` == "null" ]]


    done
    min_val=10000
    max_val=0
    for group in "${!ana_load[@]}"; do
       val=${ana_load[$group]}
       if (( val < min_val )); then
          min_val=$val
       fi
       if (( val > max_val )); then
          max_val=$val
       fi
    done
    if (( max_val - min_val > 2 )); then
       echo "ℹ️ ℹ️ Namespace ANA group Distribution issue"
       exit 1
    else
       echo "ℹ️ ℹ️ ANA Compared OK!"
    fi
}


echo "ℹ️ ℹ️ Start test:  create additional 2 subsystems with auto listeners:"

docker compose run -T --rm nvmeof-cli --server-address $ip1 --server-port 5500 subsystem add -n $NQN1 --no-group-append --network-mask $SUBNET --no-group-append
docker compose run -T --rm nvmeof-cli --server-address $ip1 --server-port 5500 subsystem add -n $NQN2 --no-group-append --network-mask $SUBNET --secure-listeners --no-group-append

#docker compose run -T --rm nvmeof-cli --server-address $ip1 --server-port 5500 subsystem add -n $NQN3 --no-group-append
sleep 2
# docker compose run --rm nvmeof-cli --server-address $ip1 --server-port 5500 host add --subsystem $NQN1 --host-nqn "*"
# docker compose run --rm nvmeof-cli --server-address $ip1 --server-port 5500 host add --subsystem $NQN2 --host-nqn "*"

# docker compose  run --rm nvmeof-cli --server-address $ip1  --server-port 5500 listener add  --subsystem $NQN2 --host-name $GW1_NAME --traddr $ip1 --trsvcid 4420
# docker compose  run --rm nvmeof-cli --server-address $ip1  --server-port 5500 listener add  --subsystem $NQN3 --host-name $GW1_NAME --traddr $ip1 --trsvcid 4420
# docker compose  run --rm nvmeof-cli --server-address $ip2  --server-port 5500 listener add  --subsystem $NQN2 --host-name $GW2_NAME --traddr $ip2 --trsvcid 4420
# docker compose  run --rm nvmeof-cli --server-address $ip2  --server-port 5500 listener add  --subsystem $NQN3 --host-name $GW2_NAME --traddr $ip2 --trsvcid 4420

docker compose run -T --rm nvmeof-cli --server-address $ip1 --server-port 5500 --output stdio --format json subsystem list

for i in $(seq $NUM_SUBSYSTEMS); do
   NQN="nqn.2016-06.io.spdk:cnode0$i"
   docker compose run -T --rm nvmeof-cli --server-address $ip1 --server-port 5500 --output stdio --format json listener list -n $NQN
   docker compose run -T --rm nvmeof-cli --server-address $ip2 --server-port 5500 --output stdio --format json listener list -n $NQN
   docker compose run -T --rm nvmeof-cli --server-address $ip2 --server-port 5500 --output stdio --format json gw listener_info -n $NQN
done


docker compose run -T --rm nvmeof-cli --server-address $ip2 --server-port 5500 --output stdio --format json listener list -n "nqn.2016-06.io.spdk:cnode1"
docker compose run -T --rm nvmeof-cli --server-address $ip1 --server-port 5500 --output stdio --format json gw listener_info -n "nqn.2016-06.io.spdk:cnode1"
docker compose run -T --rm nvmeof-cli --server-address $ip2 --server-port 5500 --output stdio --format json gw listener_info -n "nqn.2016-06.io.spdk:cnode1"
# echo "ℹ️ ℹ️  Create namespaces with explicit LB = 1"

# for i in $(seq $NUM_SUBSYSTEMS); do
#    NQN="nqn.2016-06.io.spdk:cnode$i"
#    for num in $(seq $MAX_NAMESPACE);
#    do
#    image_name="demo_image$(expr \( $num + 5 \) \* $i)"
#    echo $image_name
#    docker compose  run --rm nvmeof-cli --server-address $ip2 --server-port 5500 namespace add --subsystem $NQN --rbd-pool rbd --rbd-image $image_name  --size 10M --rbd-create-image -l 1 --force
#    done
# done

# echo "ℹ️ ℹ️  Wait for rebalance "
# sleep 250

# test_auto_listeners 2

docker compose exec -T ceph ceph nvme-gw delete $GW1_NAME rbd ''
echo "ℹ️ ℹ️  Wait for scale-down rebalance "
sleep 110
# test_auto_listeners 1
docker compose run -T --rm nvmeof-cli --server-address $ip1 --server-port 5500 --output stdio --format json subsystem list
for i in $(seq $NUM_SUBSYSTEMS); do
   NQN="nqn.2016-06.io.spdk:cnode0$i"
   docker compose run -T --rm nvmeof-cli --server-address $ip1 --server-port 5500 --output stdio --format json listener list -n $NQN
   docker compose run -T --rm nvmeof-cli --server-address $ip2 --server-port 5500 --output stdio --format json listener list -n $NQN
   docker compose run -T --rm nvmeof-cli --server-address $ip2 --server-port 5500 --output stdio --format json gw listener_info -n $NQN
done
docker compose run -T --rm nvmeof-cli --server-address $ip2 --server-port 5500 --output stdio --format json listener list -n "nqn.2016-06.io.spdk:cnode1"
docker compose run -T --rm nvmeof-cli --server-address $ip1 --server-port 5500 --output stdio --format json gw listener_info -n "nqn.2016-06.io.spdk:cnode1"
docker compose run -T --rm nvmeof-cli --server-address $ip2 --server-port 5500 --output stdio --format json gw listener_info -n "nqn.2016-06.io.spdk:cnode1"




docker compose exec -T ceph ceph nvme-gw create $GW1_NAME rbd ''
echo "ℹ️ ℹ️  Wait for rebalance after create GW"
sleep 200
# test_auto_listeners 2
docker compose run -T --rm nvmeof-cli --server-address $ip1 --server-port 5500 --output stdio --format json subsystem list
for i in $(seq $NUM_SUBSYSTEMS); do
   NQN="nqn.2016-06.io.spdk:cnode0$i"
   docker compose run -T --rm nvmeof-cli --server-address $ip1 --server-port 5500 --output stdio --format json listener list -n $NQN
   docker compose run -T --rm nvmeof-cli --server-address $ip2 --server-port 5500 --output stdio --format json listener list -n $NQN
   docker compose run -T --rm nvmeof-cli --server-address $ip2 --server-port 5500 --output stdio --format json gw listener_info -n $NQN
done
docker compose run -T --rm nvmeof-cli --server-address $ip2 --server-port 5500 --output stdio --format json listener list -n "nqn.2016-06.io.spdk:cnode1"
docker compose run -T --rm nvmeof-cli --server-address $ip1 --server-port 5500 --output stdio --format json gw listener_info -n "nqn.2016-06.io.spdk:cnode1"
docker compose run -T --rm nvmeof-cli --server-address $ip2 --server-port 5500 --output stdio --format json gw listener_info -n "nqn.2016-06.io.spdk:cnode1"
#

############################################################################################

echo "ℹ️ ℹ️  test passed"
exit 0
