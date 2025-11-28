import pytest
from control.server import GatewayServer
import socket
from control.cli import main as cli
from control.cli import main_test as cli_test
from control.cephutils import CephUtils
import grpc
from control.proto import gateway_pb2_grpc as pb2_grpc
import time

pool = "rbd"
subsystem = "nqn.2016-06.io.spdk:cnode1"
subsystem2 = "nqn.2016-06.io.spdk:cnode2"
subsystem3 = "nqn.2016-06.io.spdk:cnode3"

host_name = socket.gethostname()
addr = "127.0.0.1"
addr_ipv6 = "::1"
# server_addr_ipv6 = "2001:db8::3"
# listener_list = [["-a", addr, "-s", "5001", "-f", "ipv4"], ["-a", addr, "-s", "5002"]]
# listener_list_no_port = [["-a", addr]]
# listener_list_invalid_adrfam = [["-a", addr, "-s", "5013", "--adrfam", "JUNK"]]
# listener_list_no_adrfam = [["-a", addr, "-s", "5053"]]
# listener_list_ipv6 = [["-a", addr_ipv6, "-s", "5003", "--adrfam", "ipv6"],
#                       ["-a", addr_ipv6, "-s", "5004", "--adrfam", "IPV6"]]
# listener_list_discovery = [["-n", discovery_nqn, "-t", host_name, "-a", addr, "-s", "5012"]]
# listener_list_negative_port = [["-t", host_name, "-a", addr, "-s", "-2000"]]
# listener_list_big_port = [["-t", host_name, "-a", addr, "-s", "70000"]]
# listener_list_wrong_host = [["-t", "WRONG", "-a", addr, "-s", "5015", "-f", "ipv4"]]
# listener_list_bad_ips = [["127.1.1.1", 5011, "ipv4"],
#                          ["[fe80::a00:27ff:fe38:1d48]", 5022, "ipv6"],
#                          [addr, 5033, "ipv6"],
#                          [f"[{addr_ipv6}]", 5044, "ipv4"]]
config = "ceph-nvmeof.conf"
group_name = "GROUPNAME"


@pytest.fixture(scope="module")
def gateway(config):
    """Sets up and tears down Gateway"""

    addr = config.get("gateway", "addr")
    port = config.getint("gateway", "port")
    config.config["gateway"]["group"] = group_name
    # config.config["gateway"]["max_namespaces_with_netmask"] = "3"
    # config.config["gateway"]["max_hosts_per_namespace"] = "3"
    # config.config["gateway"]["max_subsystems"] = "4"
    # config.config["gateway"]["max_namespaces"] = "12"
    # config.config["gateway"]["max_namespaces_per_subsystem"] = "11"
    # config.config["gateway"]["max_hosts_per_subsystem"] = "4"
    # config.config["gateway"]["max_hosts"] = "6"
    config.config["gateway-logs"]["log_level"] = "debug"
    # config.config["gateway"]["enable_prometheus_exporter"] = False
    ceph_utils = CephUtils(config)

    with GatewayServer(config) as gateway:

        # Start gateway
        gateway.gw_logger_object.set_log_level("debug")
        ceph_utils.execute_ceph_monitor_command(
            "{" + f'"prefix":"nvme-gw create", "id": "{gateway.name}", "pool": "{pool}", '
            f'"group": "{group_name}"' + "}"
        )
        gateway.serve()
        # gateway.keep_alive()

        # Bind the client and Gateway
        channel = grpc.insecure_channel(f"{addr}:{port}")
        stub = pb2_grpc.GatewayStub(channel)
        yield gateway.gateway_rpc, stub

        # Stop gateway
        gateway.server.stop(grace=1)
        gateway.gateway_rpc.gateway_state.delete_state()


class TestAutoListener:
    def test_auto_listener_ipv4(self, caplog, gateway):
        cli(["subsystem", "list"])
        caplog.clear()
        cli(["subsystem", "add", "--subsystem", subsystem, "--no-group-append",
             '--network-mask', f'{addr}/24'])
        assert f"Adding subsystem {subsystem}: Successful" in caplog.text
        assert "ipv4" in caplog.text.lower()
        assert f"Automatically created listener at {addr}:4420 for {subsystem}"

    def test_auto_listener_secure(self, caplog, gateway):
        caplog.clear()
        cli(["subsystem", "add", "--subsystem", subsystem2, "--no-group-append",
             '--network-mask', f'{addr}/24', '--secure-listeners'])
        assert f"Adding subsystem {subsystem2}: Successful" in caplog.text
        assert "ipv4" in caplog.text.lower()
        assert f"Automatically created listener at {addr}:4420 for {subsystem2}"

    def test_auto_listener_ipv6(self, caplog, gateway):
        caplog.clear()
        cli(["subsystem", "add", "--subsystem", subsystem3, "--no-group-append",
             '--network-mask', f'{addr_ipv6}/120'])
        assert f"Adding subsystem {subsystem3}: Successful" in caplog.text
        assert "ipv6" in caplog.text.lower()
        assert f"Automatically created listener at {addr_ipv6}:4420 for {subsystem3}"

    def test_auto_listener_list_ipv4(self, caplog, gateway):
        cli(["subsystem", "list"])
        time.sleep(30)
        caplog.clear()
        listeners = cli_test(["listener", "list", "--subsystem", subsystem])
        print("VALLARI_DEBUG")
        print(listeners)
        print(socket.gethostname())
        print(host_name)
        # assert listeners.status == 0
        # assert listeners.listeners[0].host_name == host_name
        assert listeners.listeners[0].trtype == "TCP"
        assert listeners.listeners[0].traddr == addr
        assert listeners.listeners[0].trsvcid == 4420
        assert listeners.listeners[0].active
        assert not listeners.listeners[0].secure
        assert not listeners.listeners[0].manual

    def test_auto_listener_list_secure(self, caplog, gateway):
        caplog.clear()
        listeners = cli_test(["listener", "list", "--subsystem", subsystem2])
        print(listeners)
        # assert listeners.listeners[1].host_name == host_name
        assert listeners.listeners[0].trtype == "TCP"
        assert listeners.listeners[0].traddr == addr
        assert listeners.listeners[0].trsvcid == 4420
        assert listeners.listeners[0].active
        assert listeners.listeners[0].secure
        assert not listeners.listeners[0].manual

    def test_auto_listener_list_ipv6(self, caplog, gateway):
        caplog.clear()
        listeners = cli_test(["listener", "list", "--subsystem", subsystem3])
        # assert listeners.listeners[0].host_name == host_name
        assert listeners.listeners[0].trtype == "TCP"
        assert listeners.listeners[0].traddr == addr_ipv6
        assert listeners.listeners[0].trsvcid == 4420
        assert listeners.listeners[0].active
        assert not listeners.listeners[0].secure
        assert not listeners.listeners[0].manual
