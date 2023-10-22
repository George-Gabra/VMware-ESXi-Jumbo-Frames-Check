# VMware ESXi Hosts Jumbo Frames Checker

## Table of Contents

- [Overview](#overview)
- [Parameters](#parameters)
- [Examples](#examples)

## Overview

This script is designed to check Jumbo frames from ESXi hosts managed by vCenter to VMkernel gateways and NFS storage servers. It sends 10 packets and reports an error if packet loss exceeds 80% (more than 8 packets are lost). You can run the script manually or schedule it. When running manually, you can specify a list of vCenters or specific IP addresses to be checked on all ESXi hosts.


## Parameters

### `--TestHostsMTU`

Check Jumbo frames from ESXi hosts managed by vCenter to VMkernel gateways and NFS storage servers. This parameter requires the vCenters source list with one of the following parameters: `--FromInventory` or `--FromCLI`.

- `--FromInventory`: Gets cloud provider vCenter servers list from inventory service.
- `--FromCLI`: Gets vCenter servers list from the command line. The vCenter list has to be separated with single quotes.


### `--TestIP`

Check jumbo frames to a specific IP address from all ESXi hosts managed by a vCenter server. You need to provide the vCenter server and IP address.


## Examples

### Example 1:

```powershell
powershell.exe check_mtu_9000.ps1 --TestHostsMTU --FromInventory
```

**Description**: Gets cloud provider vCenter servers list from inventory service. The script loops through the retrieved vCenters list and checks Jumbo frames from each ESXi host to VMkernel gateways and NFS storage servers.

### Example 2:

```powershell
powershell.exe check_mtu_9000.ps1 --TestHostsMTU --FromCLI
```

**Description**: Gets vCenter servers list from the command line. The vCenter list has to be separated with single quotes. The script loops through the provided vCenters list and checks Jumbo frames from each ESXi host to VMkernel gateways and NFS storage servers.

### Example 3:

```powershell
powershell.exe check_mtu_9000.ps1 --TestHostsMTU --FromCLI vc1.example.com,vc2.example.com
```

### Example 4:

```powershell
powershell.exe check_mtu_9000.ps1 --TestIP
```

**Description**: Check Jumbo frames to a specific IP address from all ESXi hosts managed by a vCenter server. You will be prompted to enter the vCenter Server FQDN/IP Address and the IP Address you want to test Jumbo frames to.
