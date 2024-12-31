import pytest
from control.server import GatewayServer
from control.cli import main as cli
from control.cli import main_test as cli_test
import grpc
import os
import shutil
import stat
import gzip
import glob

config = "ceph-nvmeof.conf"
subsystem_prefix = "nqn.2016-06.io.spdk:cnode"


def clear_log_files():
    files = os.listdir("/var/log/ceph")
    for f in files:
        fpath = "/var/log/ceph/" + f
        statinfo = os.stat(fpath)
        if stat.S_ISDIR(statinfo.st_mode):
            print(f"Deleting directory {fpath}")
            shutil.rmtree(fpath, ignore_errors=True)
        else:
            print(f"Deleting file {fpath}")
            os.remove(fpath)


@pytest.fixture(scope="function")
def gateway(config, request):
    """Sets up and tears down Gateway"""

    addr = config.get("gateway", "addr")
    port = config.getint("gateway", "port")
    config.config["gateway-logs"]["log_files_enabled"] = "True"
    config.config["gateway-logs"]["max_log_file_size_in_mb"] = "10"
    config.config["gateway-logs"]["log_files_rotation_enabled"] = "True"
    config.config["gateway"]["name"] = request.node.name.replace("_", "-")
    config.config["spdk"]["log_file_dir"] = "/var/log/ceph"
    if request.node.name == "test_log_files_disabled":
        config.config["gateway-logs"]["log_files_enabled"] = "False"
    elif request.node.name == "test_log_files_rotation":
        config.config["gateway-logs"]["max_log_file_size_in_mb"] = "1"
    elif request.node.name == "test_log_files_disable_rotation":
        config.config["gateway-logs"]["max_log_file_size_in_mb"] = "1"
        config.config["gateway-logs"]["log_files_rotation_enabled"] = "False"
    elif request.node.name == "test_no_spdk_log":
        config.config["spdk"]["log_file_dir"] = ""

    with GatewayServer(config) as gateway:

        # Start gateway
        gateway.set_group_id(0)
        gateway.serve()

        # Bind the client and Gateway
        grpc.insecure_channel(f"{addr}:{port}")
        yield gateway

        # Stop gateway
        gateway.server.stop(grace=1)
        gateway.gateway_rpc.gateway_state.delete_state()
    clear_log_files()


def test_log_files(gateway):
    gw = gateway
    look_for = f"/var/log/ceph/nvmeof-{gw.name}"
    tree_list = os.walk("/var/log/ceph")
    for rootdir, subdirs, files in tree_list:
        if rootdir == "/var/log/ceph":
            pass
        elif rootdir == look_for:
            assert "nvmeof-log" in files
        else:
            assert "nvmeof-log.gz" in files or "nvmeof-log.0" in files
    with open(f"/var/log/ceph/nvmeof-{gw.name}/nvmeof-log", "r") as f:
        assert f"Starting gateway {gw.name}" in f.read()
    spdk_files = glob.glob("/var/log/ceph/spdk*")
    assert len(spdk_files) == 1
    assert f"spdk-{gw.name}" in spdk_files[0]


def test_log_files_disabled(gateway):
    cli(["subsystem", "add", "--subsystem", subsystem_prefix + "1"])
    subs_list = cli_test(["--format", "text", "subsystem", "list"])
    assert subs_list is not None
    assert subs_list.status == 0
    assert len(subs_list.subsystems) == 1
    assert subs_list.subsystems[0].nqn == subsystem_prefix + "1"
    files = glob.glob("/var/log/ceph/nvme*")
    assert files == []


def test_log_files_rotation(gateway):
    gw = gateway
    files = glob.glob("/var/log/ceph/nvme*")
    assert len(files) == 1
    assert f"nvmeof-{gw.name}" in files[0]
    cli(["subsystem", "add", "--subsystem", subsystem_prefix + "2"])
    cli(["subsystem", "add", "--subsystem", subsystem_prefix + "3"])
    cli(["subsystem", "add", "--subsystem", subsystem_prefix + "4"])
    for i in range(2000):
        cli(["subsystem", "list"])
    files = glob.glob("/var/log/ceph/nvme*")
    assert len(files) == 1
    assert f"nvmeof-{gw.name}" in files[0]
    files = os.listdir(f"/var/log/ceph/nvmeof-{gw.name}")
    assert len(files) > 1
    assert "nvmeof-log.1" in files
    logfile = None
    if "nvmeof-log.3" in files:
        logfile = "nvmeof-log.3"
    elif "nvmeof-log.2" in files:
        logfile = "nvmeof-log.2"
    elif "nvmeof-log.1" in files:
        logfile = "nvmeof-log.1"
    elif "nvmeof-log.0" in files:
        logfile = "nvmeof-log.0"
    elif "nvmeof-log.gz" in files:
        logfile = "nvmeof-log.gz"
    if logfile:
        with gzip.open(f"/var/log/ceph/nvmeof-{gw.name}/{logfile}", mode="rb") as f:
            check_for = bytes(f"Starting gateway {gw.name}", "utf-8")
            assert check_for in f.read()


def test_log_files_disable_rotation(gateway):
    gw = gateway
    files = glob.glob("/var/log/ceph/nvme*")
    assert len(files) == 1
    assert f"nvmeof-{gw.name}" in files[0]
    cli(["subsystem", "add", "--subsystem", subsystem_prefix + "5"])
    cli(["subsystem", "add", "--subsystem", subsystem_prefix + "6"])
    cli(["subsystem", "add", "--subsystem", subsystem_prefix + "7"])
    for i in range(2000):
        cli(["subsystem", "list"])
    files = glob.glob("/var/log/ceph/nvme*")
    assert len(files) == 1
    assert f"nvmeof-{gw.name}" in files[0]
    files = os.listdir(f"/var/log/ceph/nvmeof-{gw.name}")
    assert len(files) == 1
    assert files[0] == "nvmeof-log"
    statinfo = os.stat(f"/var/log/ceph/nvmeof-{gw.name}/nvmeof-log")
    assert statinfo.st_size > 1048576
    with open(f"/var/log/ceph/nvmeof-{gw.name}/nvmeof-log", mode="r") as f:
        check_for = f"Starting gateway {gw.name}"
        assert check_for in f.read()


def test_no_spdk_log(gateway):
    gw = gateway
    files = glob.glob("/var/log/ceph/nvme*")
    assert len(files) == 1
    assert f"nvmeof-{gw.name}" in files[0]
    spdk_files = glob.glob("/var/log/ceph/spdk*")
    assert len(spdk_files) == 0
