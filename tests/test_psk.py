import pytest
from control.server import GatewayServer
import socket
from control.cli import main as cli
from control.cli import main_test as cli_test
from control.cephutils import CephUtils
import grpc

image = "mytestdevimage"
pool = "rbd"
subsystem = "nqn.2016-06.io.spdk:cnode1"
hostnqn1 = "nqn.2014-08.org.nvmexpress:uuid:22207d09-d8af-4ed2-84ec-a6d80b0cf7eb"
hostnqn2 = "nqn.2014-08.org.nvmexpress:uuid:22207d09-d8af-4ed2-84ec-a6d80b0cf7ec"
hostnqn3 = "nqn.2014-08.org.nvmexpress:uuid:22207d09-d8af-4ed2-84ec-a6d80b0cf7ee"
hostnqn4 = "nqn.2014-08.org.nvmexpress:uuid:6488a49c-dfa3-11d4-ac31-b232c6c68a8a"
hostnqn5 = "nqn.2014-08.org.nvmexpress:uuid:22207d09-d8af-4ed2-84ec-a6d80b0cf7ef"
hostnqn6 = "nqn.2014-08.org.nvmexpress:uuid:22207d09-d8af-4ed2-84ec-a6d80b0cf7f0"
hostnqn7 = "nqn.2014-08.org.nvmexpress:uuid:22207d09-d8af-4ed2-84ec-a6d80b0cf7f1"
hostnqn8 = "nqn.2014-08.org.nvmexpress:uuid:22207d09-d8af-4ed2-84ec-a6d80b0cf7f2"
hostnqn9 = "nqn.2014-08.org.nvmexpress:uuid:22207d09-d8af-4ed2-84ec-a6d80b0cf7f3"
hostnqn10 = "nqn.2014-08.org.nvmexpress:uuid:22207d09-d8af-4ed2-84ec-a6d80b0cf7f4"
hostnqn11 = "nqn.2014-08.org.nvmexpress:uuid:22207d09-d8af-4ed2-84ec-a6d80b0cf7f5"
hostnqn12 = "nqn.2014-08.org.nvmexpress:uuid:22207d09-d8af-4ed2-84ec-a6d80b0cf7f6"

hostpsk1 = "NVMeTLSkey-1:01:YzrPElk4OYy1uUERriPwiiyEJE/+J5ckYpLB+5NHMsR2iBuT:"
hostpsk2 = \
    "NVMeTLSkey-1:02:FTFds4vH4utVcfrOforxbrWIgv+Qq4GQHgMdWwzDdDxE1bAqK2mOoyXxmbJxGeueEVVa/Q==:"
hostpsk3 = "junk"
hostpsk4 = "NVMeTLSkey-1:01:YzrPElk4OYy1uUERriPwiiyEJE/+J5ckYpLB+5NHMsR2iBuT:"

hostdhchap1 = "DHHC-1:00:MWPqcx1Ug1debg8fPIGpkqbQhLcYUt39k7UWirkblaKEH1kE:"

host_name = socket.gethostname()
addr = "127.0.0.1"
config = "ceph-nvmeof.conf"


@pytest.fixture(scope="module")
def gateway(config):
    """Sets up and tears down Gateway"""

    addr = config.get("gateway", "addr")
    port = config.getint("gateway", "port")
    config.config["gateway-logs"]["log_level"] = "debug"
    config.config["gateway"]["group"] = ""
    ceph_utils = CephUtils(config)

    with GatewayServer(config) as gateway:

        # Start gateway
        gateway.gw_logger_object.set_log_level("debug")
        ceph_utils.execute_ceph_monitor_command(
            "{" + f'"prefix":"nvme-gw create", "id": "{gateway.name}", '
            f'"pool": "{pool}", "group": ""' + "}"
        )
        gateway.serve()

        # Bind the client and Gateway
        grpc.insecure_channel(f"{addr}:{port}")
        yield gateway.gateway_rpc

        # Stop gateway
        gateway.server.stop(grace=1)
        gateway.gateway_rpc.gateway_state.delete_state()


def test_setup(caplog, gateway):
    caplog.clear()
    cli(["subsystem", "add", "--subsystem", subsystem])
    assert f"create_subsystem {subsystem}: True" in caplog.text
    caplog.clear()
    cli(["namespace", "add", "--subsystem", subsystem, "--rbd-pool", pool,
         "--rbd-image", image, "--rbd-create-image", "--size", "16MB"])
    assert f"Adding namespace 1 to {subsystem}: Successful" in caplog.text


def test_create_secure_with_any_host(caplog, gateway):
    caplog.clear()
    cli(["host", "add", "--subsystem", subsystem, "--host-nqn", "*"])
    assert f"Allowing open host access to {subsystem}: Successful" in caplog.text
    caplog.clear()
    cli(["listener", "add", "--subsystem", subsystem,
         "--host-name", host_name, "-a", addr, "-s", "5001", "--secure"])
    assert "Secure channel is only allowed for subsystems in which " \
           "\"allow any host\" is off" in caplog.text
    caplog.clear()
    cli(["host", "del", "--subsystem", subsystem, "--host-nqn", "*"])
    assert f"Disabling open host access to {subsystem}: Successful" in caplog.text


def test_create_secure(caplog, gateway):
    caplog.clear()
    cli(["listener", "add", "--subsystem", subsystem,
         "--host-name", host_name, "-a", addr, "-s", "5001", "--secure"])
    assert f"Adding {subsystem} listener at {addr}:5001: Successful" in caplog.text
    caplog.clear()
    cli(["host", "add", "--subsystem", subsystem, "--host-nqn", hostnqn1, "--psk", hostpsk1])
    assert f"Adding host {hostnqn1} to {subsystem}: Successful" in caplog.text
    caplog.clear()
    cli(["host", "add", "--subsystem", subsystem, "--host-nqn", hostnqn2, "--psk", hostpsk2])
    assert f"Adding host {hostnqn2} to {subsystem}: Successful" in caplog.text
    caplog.clear()
    cli(["host", "add", "--subsystem", subsystem, "--host-nqn", hostnqn4, "--psk", hostpsk4])
    assert f"Adding host {hostnqn4} to {subsystem}: Successful" in caplog.text


def test_create_not_secure(caplog, gateway):
    caplog.clear()
    cli(["listener", "add", "--subsystem", subsystem,
         "--host-name", host_name, "-a", addr, "-s", "5002"])
    assert f"Adding {subsystem} listener at {addr}:5002: Successful" in caplog.text
    caplog.clear()
    cli(["host", "add", "--subsystem", subsystem, "--host-nqn", hostnqn6])
    assert f"Adding host {hostnqn6} to {subsystem}: Successful" in caplog.text
    caplog.clear()
    cli(["host", "add", "--subsystem", subsystem, "--host-nqn", hostnqn7])
    assert f"Adding host {hostnqn7} to {subsystem}: Successful" in caplog.text


def test_create_secure_list(caplog, gateway):
    caplog.clear()
    rc = 0
    try:
        cli(["host", "add", "--subsystem", subsystem,
             "--host-nqn", hostnqn8, hostnqn9, hostnqn10, "--psk", hostpsk1])
    except SystemExit as sysex:
        rc = int(str(sysex))
        pass
    assert rc == 2
    assert "error: Can't have more than one host NQN when PSK keys are used" in caplog.text


def test_create_secure_junk_key(caplog, gateway):
    caplog.clear()
    cli(["host", "add", "--subsystem", subsystem, "--host-nqn", hostnqn3, "--psk", hostpsk3])
    assert f"Failure adding host {hostnqn3} to {subsystem}" in caplog.text


def test_create_secure_no_key(caplog, gateway):
    caplog.clear()
    rc = 0
    try:
        cli(["host", "add", "--subsystem", subsystem, "--host-nqn", hostnqn5, "--psk"])
    except SystemExit as sysex:
        rc = int(str(sysex))
        pass
    assert rc == 2
    assert "error: argument --psk/-p: expected one argument" in caplog.text


def test_list_psk_hosts(caplog, gateway):
    caplog.clear()
    hosts = cli_test(["host", "list", "--subsystem", subsystem])
    found = 0
    assert len(hosts.hosts) == 5
    for h in hosts.hosts:
        if h.nqn == hostnqn1:
            found += 1
            assert h.use_psk
        elif h.nqn == hostnqn2:
            found += 1
            assert h.use_psk
        elif h.nqn == hostnqn4:
            found += 1
            assert h.use_psk
        elif h.nqn == hostnqn6:
            found += 1
            assert not h.use_psk
        elif h.nqn == hostnqn7:
            found += 1
            assert not h.use_psk
        else:
            assert False
    assert found == 5


def test_allow_any_host_with_psk(caplog, gateway):
    caplog.clear()
    rc = 0
    try:
        cli(["host", "add", "--subsystem", subsystem, "--host-nqn", "*", "--psk", hostpsk1])
    except SystemExit as sysex:
        rc = int(str(sysex))
        pass
    assert rc == 2
    assert "error: PSK key is only allowed for specific hosts" in caplog.text


def test_psk_with_dhchap(caplog, gateway):
    caplog.clear()
    cli(["host", "add", "--subsystem", subsystem, "--host-nqn", hostnqn10,
         "--psk", hostpsk1, "--dhchap-key", hostdhchap1])
    assert f"Adding host {hostnqn10} to {subsystem}: Successful" in caplog.text
    assert f"Host {hostnqn10} has a DH-HMAC-CHAP key but subsystem {subsystem} " \
           f"has no key, a unidirectional authentication will be used" in caplog.text


def test_list_listeners(caplog, gateway):
    caplog.clear()
    listeners = cli_test(["listener", "list", "--subsystem", subsystem])
    assert len(listeners.listeners) == 2
    found = 0
    for lstnr in listeners.listeners:
        if lstnr.trsvcid == 5001:
            found += 1
            assert lstnr.secure
        elif lstnr.trsvcid == 5002:
            found += 1
            assert not lstnr.secure
        else:
            assert False
    assert found == 2


def test_add_host_with_key_host_list(caplog, gateway):
    caplog.clear()
    rc = 0
    try:
        cli(["host", "add", "--subsystem", subsystem,
             "--host-nqn", hostnqn11, hostnqn12, "--psk", "junk"])
    except SystemExit as sysex:
        rc = int(str(sysex))
        pass
    assert "Can't have more than one host NQN when PSK keys are used" in caplog.text
    assert rc == 2
