# redborder-net-tools

Polling daemon that enables running network diagnostic tools (ping, traceroute, dig, tcpdump, SNMP) on redborder proxy nodes from the manager web UI.

The connection between proxy and manager is unidirectional (proxy → manager only), so the daemon polls the manager API for pending tasks, executes them locally, and posts results back.

## Configuration

The daemon is configured via `/etc/sysconfig/redborder-net-tools` (written by `cookbook-rb-net-tools`):

```
MANAGER_URL="https://webui.redborder.cluster"
SENSOR_UUID="<proxy-sensor-uuid>"
```

## License

AFFERO GENERAL PUBLIC LICENSE, Version 3
