#requires -version 4
<#
.SYNOPSIS
  Check jumbo frames works on all ESXi hosts to network gateways

.DESCRIPTION
  <Brief description of script>


.INPUTS node
  Mandatory. The vCenter Server or ESXi Host the script will connect to, in the format of IP address or FQDN.


.OUTPUTS Log File
  The script log file stored in /var/log

.NOTES
  Version:        1.0
  Author:         George Gabra
  Creation Date:  1620820346
  Purpose/Change: Initial script development

.EXAMPLE
  <Example explanation goes here>

  <Example goes here. Repeat this attribute for more than one example>
#>

#---------------------------------------------------------[Script Parameters]------------------------------------------------------

Param (
  #Script parameters go here

	[string]$vCenters,
	[switch]$TestHostsMTU,
	[switch]$FromInventory,
	[switch]$FromCLI,
	[switch]$TestIP,
	[switch]$Help


)

#---------------------------------------------------------[Initialisations]--------------------------------------------------------

# Set Error Action to Silently Continue
$ErrorActionPreference = 'SilentlyContinue'

# Import Modules & Snap-ins
#Import-Module VMware.VimAutomation.Core -WarningAction SilentlyContinue
Import-Module VMware.VimAutomation.Core

#Import Logging Module
Import-Module send-syslogmessage.psm1

#Set-PowerCLIConfiguration -Scope AllUsers -DefaultVIServerMode Multiple -InvalidCertificateAction Ignore -ParticipateInCEIP:$False -DisplayDeprecationWarnings:$False -Confirm:$False
Set-PowerCLIConfiguration -Scope ([VMware.VimAutomation.ViCore.Types.V1.ConfigurationScope]::User -bor [VMware.VimAutomation.ViCore.Types.V1.ConfigurationScope]::AllUsers -bor [VMware.VimAutomation.ViCore.Types.V1.ConfigurationScope]::Session) -DefaultVIServerMode Multiple -InvalidCertificateAction Ignore -ParticipateInCEIP:$False -DisplayDeprecationWarnings:$False -Confirm:$False
Import-Module PSLogging


#----------------------------------------------------------[Declarations]----------------------------------------------------------

#Script Version
$sScriptVersion = '1.0'

#Log File Info
$sLogPath = "/tmp/scripts/"
$ScriptName = $MyInvocation.MyCommand.Name
$sLogName = "$($ScriptName).log"
$sLogFile = Join-Path -Path $sLogPath -ChildPath $sLogName

#vCenter Credentials
$username = "administrator@vsphere.local"
$password = "PASSWORD"

#-----------------------------------------------------------[Functions]------------------------------------------------------------

# Function to connect to Ralph3 inventory and return the authentication token and Ralph Server URL

Function Get-RalphToken
{
  $User = "USER"
  $Password = "PASSWORD"
  $Server = "inv.example.com"
  $url = "https://$Server/api-token-auth/"
  $data = @{
    username = $User
    password = $Password
  }
  $resp = Invoke-RestMethod -Method 'Post' -Uri $url -Body $data
  return $resp.token,$Server
}

#Function to return the list of vCenter servers from Ralph3 inventory

Function  Get-RalphVirtualServers()
{
  $vCentersRalphList = New-Object System.Collections.Generic.List[System.Object]
  $Filters = New-Object System.Collections.Generic.List[System.Object]
  $Filters = @( 'tag=emea-provider' , 'tag=amer-provider' , 'tag=apj-provider' )
  foreach ($Filter in $Filters)
  {
  $TokenServer, $ServerName = Get-RalphToken
  $Server = $ServerName
  $token = $TokenServer
  $token = "Token " + $token.Trim()
  $url = "https://$Server/api/virtual-servers/"
  if ($null -ne $Filter)
  {
    $url += "?$Filter"
  }
  $headers = @{
    "Authorization" = $token
  }
  $resp = Invoke-RestMethod -Method 'Get' -Uri $url -Headers $headers
  $vCentersRalphList += $resp.results.hostname
}
return $vCentersRalphList
}

# Function to Post alert to VMware vRLI

Function Send-vRLI($severity, $message, $sendMail)
{
    Send-SyslogMessage -Server vrli.example.com -Hostname "host.example.com" -Severity "$severity" -Message "$message" -Facility user -Application "Jumbo_Frames_Checker"
    if ($sendMail -eq $true) {
        Send-MailMessage -From "sender@example.com" -To "receiver@example.com" -SmtpServer "smtp.example.com" -Subject "Critical: Jumbo Frames Check Failed" -Body "$message" -Priority High
    }
}


# Function to Write to log file

Function Write-Log
{
Param ([string]$LogString)
$Stamp = (Get-Date).toString("dd/MM/yyyy HH:mm:ss")
$sLogMessage = "$($Stamp): $($LogString)"
Add-content $sLogFile -value $sLogMessage
}

# Open a connection to the vCenter server using the credentials defined in Declarations section

Function Connect-VMwareServer {
  Param ([Parameter(Mandatory=$true)][string]$VMServer)

  begin {
    $message = "Connecting to VMware environment $($VMServer)..."
    Write-Host `n
    Write-Host $message
    Write-Log $message
  }

  process {
    try {
	Connect-VIServer -Server $VMServer -User $username -Password $password
    }

    catch {
      Write-Host $_.Exception
      Write-Log $_.Exception
      Break
    }
  }

  end {
    If ($?) {
      $message = "Successfully connected to $($VMServer)"
      Write-Host $message
      Write-Log $message
    }
  }
}


# Check that MTU with 9000 bytes works on all ESXi hosts to all network gateways

Function Check-MTU {
  Param ([Parameter(Mandatory=$true)][string]$vCenterServer)

  Begin {
    $message = "Start checking all ESXi hosts managed by vCenter server $($vCenterServer)..."
    Write-Host $message `r`n
    Write-Log $message
  }

  Process {
      # Retrieve list of only ESXi hosts which are connected or in maintenance mode under the vCenter (Any host which is not responding, disconnected,... etc. won't be checked by the script)
      $esxihostslist = New-Object System.Collections.Generic.List[System.Object]
      $esxihostslist += Get-VMHost -Server $vCenterServer -State Connected,Maintenance
  for ( $i=0 ; $i -lt $esxihostslist.Count ; $i++ )
	{
		$esxihostname = $esxihostslist[$i] | Select -ExpandProperty  Name
		$esxihoststate = $esxihostslist[$i] | Select -ExpandProperty State

		$message = "ESXi Host: $($esxihostname) state is $($esxihoststate)"
		Write-Host $message
		Write-Log $message
    $EsxCLIRoutes = Get-EsxCli -VMHost (Get-VMHost $esxihostname) -V2
    # Get list of all IPv4 network routes on the host
		# Get the VMkernel interface name and the gateway from the list
    $NetworkInfo = $ESXCLIRoutes.network.ip.route.ipv4.list.Invoke() | select Interface,Gateway
		foreach ($VMKAdaptor in $NetworkInfo)
		{
			# Check if the network gateway value is not set to quad zero
			if ( $VMKAdaptor.Gateway -ne "0.0.0.0" )
			{
			$message = "Checking VMkernel Adaptor $($VMKAdaptor.Interface) network gateway is $($VMKAdaptor.Gateway)"
			Write-Host $message
			Write-Log $message
			$EsxCLIPing = Get-EsxCli -VMHost (Get-VMHost $esxihostname) -V2
			# Create parameters for ping command
		  $params = $EsxCLIPing.network.diag.ping.CreateArgs()
			$params.host = $VMKAdaptor.Gateway
			$params.interface = $VMKAdaptor.Interface
			$params.count = 10
			# Set ping command packet size to 8972 bytes as per VMware's KB# 1003728
			$params.size = '8972'
			$res = $EsxCLIPing.network.diag.ping.Invoke($params)
			# Check the result of the ping and verify packet loss value
			if ( $res.summary.PacketLost -gt 80 )
			{
			   # If packet loss value is more than 1 (Which is 10% of the 10 packets), print and error with the details
			   Write-Host "Error: " -ForegroundColor red  -NoNewline
			   Write-Host "Ping with Jumbo frames on $($esxihostname) which is managed by vCenter server $($vCenterServer) from $($VMKAdaptor.Interface) to network gateway $($VMKAdaptor.Gateway) failed with $($res.summary.PacketLost)% packet loss"

			   # Add error to script log file
			   $message = "Error: Ping with Jumbo frames on $($esxihostname) which is managed by vCenter server $($vCenterServer) from $($VMKAdaptor.Interface) to network gateway $($VMKAdaptor.Gateway) failed with $($res.summary.PacketLost)% packet loss"
			   Write-Log $message

			   # Post a user created event on the ESXi host so it can be pushed to vROPs/vRLI
         $eventManager = Get-View eventManager
         $vmhost = Get-VMHost -Name $esxihostname
         $eventManager.LogUserEvent($vmhost.ExtensionData.MoRef,$message)

			   # Post message to vRLI
			   Send-vRLI "Critical" $message $true

			}
			else
			{
			   # If there is no packet loss, print a sucess message
			   Write-Host "Success: " -ForegroundColor Green  -NoNewline
			   Write-Host "Ping with Jumbo frames on $($esxihostname) which is managed by vCenter server $($vCenterServer) from $($VMKAdaptor.Interface) to network gateway $($VMKAdaptor.Gateway) has $($res.summary.PacketLost)% packet loss"

			   # Add event to script log file
         $message = "Success: Ping with Jumbo frames on $($esxihostname) which is managed by vCenter server $($vCenterServer) from $($VMKAdaptor.Interface) to network gateway $($VMKAdaptor.Gateway) has $($res.summary.PacketLost)% packet loss"
			   Write-Log $message

			   # Post a user created event to the ESXi host
  			 $eventManager = Get-View eventManager
			   $vmhost = Get-VMHost -Name $esxihostname
			   $eventManager.LogUserEvent($vmhost.ExtensionData.MoRef,$message)

			   # Post message to vRLI
			   Send-vRLI "Information" $message $false

			}

			}
		}


		# Get list of NFS storage servers
		$EsxCLINFS = Get-EsxCli -VMHost (Get-VMHost $esxihostname) -V2
		$NFSInfo = $EsxCLINFS.storage.nfs.list.Invoke()

		# Remove duplicate records from NFS storage servers list
		$NFSInfo = $NFSInfo | Sort-Object -Property Host -Unique
		# Loop on each NFS storage server and run ping with Jumbo frames
		foreach ($NFSServer in $NFSInfo.Host)
    {
			$message = "NFS Storage Server: $($NFSServer)"
			Write-Host $message
			Write-Log $message
      $EsxCLIPing = Get-EsxCli -VMHost (Get-VMHost $esxihostname) -V2
      # Create parameters for ping command
      $params = $EsxCLIPing.network.diag.ping.CreateArgs()
      $params.host = $NFSServer
			$params.count = 10
      #$params.interface  = $VMKAdaptor.Interface #Commented to run ping from VMkernel adaptor based on routing table defined in the ESXi host
      # Set ping command packet size to 8972 bytes as per VMware's KB# 1003728
      $params.size = '8972'
      $res = $EsxCLIPing.network.diag.ping.Invoke($params)
      # Check the result of the ping and verify packet loss value
      if ( $res.summary.PacketLost -gt 80 )
      {
       # If packet loss value is not zero, print and error with the details
       Write-Host "Error: " -ForegroundColor red  -NoNewline
       Write-Host "Ping with Jumbo frames from $($esxihostname) which is managed by vCenter server $($vCenterServer) to NFS storage server $($NFSServer) failed with $($res.summary.PacketLost)% packet loss"

			 # Add error to script log file
			 $message = "Error: Ping with Jumbo frames from $($esxihostname) which is managed by vCenter server $($vCenterServer) to NFS storage server $($NFSServer) failed with $($res.summary.PacketLost)% packet loss"
			 Write-Log $message

       # Post a user created event on the ESXi host so it can be pushed to vROPs/vRLI
       $eventManager = Get-View eventManager
       $vmhost = Get-VMHost -Name $esxihostname
       $eventManager.LogUserEvent($vmhost.ExtensionData.MoRef,$message)

       # Post message to vRLI
       Send-vRLI "Critical" $message $true

       }

       else
       {
        # If there is no packet loss, print a sucess message
        Write-Host "Success: " -ForegroundColor Green  -NoNewline
        Write-Host "Ping with Jumbo frames from $($esxihostname) which is managed by vCenter server $($vCenterServer) to NFS storage server $($NFSServer) has $($res.summary.PacketLost)% packet loss"

			   #Add event to script log file
			   $message = "Success: Ping with Jumbo frames from $($esxihostname) which is managed by vCenter server $($vCenterServer) to NFS storage server $($NFSServer) has $($res.summary.PacketLost)% packet loss"
			   Write-Log $message

         # Post a user created event to the ESXi host
         $eventManager = Get-View eventManager
         $vmhost = Get-VMHost -Name $esxihostname
         $eventManager.LogUserEvent($vmhost.ExtensionData.MoRef,$message)

         # Post message to vRLI
         Send-vRLI "Information" $message $false

         }

         }

		Write-Host "===============================================================================================================================================================================================================================" `r`n
		}

		}
		}


# Function to check MTU Jumbo frames to specific IP address from all ESXi hosts managed by specific vCenter server
Function Check-MTU-IP
{

  Begin {
    Write-Host `n
    [string]$vCenterServer = $( Read-Host "Type vCenter Server FQDN/IP Address" )
    [string]$IPAddress = $( Read-Host "Type the IP Address you want to test Jumbo frames to" )
    $thisConn = Connect-VMwareServer -VMServer $vCenterServer
    $message = "Starting checking Jumbo frames from all ESXi hosts managed by vCenter server $($vCenterServer) to IP address $($IPAddress)...."
    Write-Host `n
    Write-Host $message
    Write-Log $message
  }

  Process {
      # Retrieve list of only connected ESXi hosts under the vCenter (Any host which is in maintenance mode, not responding, disconnected,... etc. won't be checked by the script)
      $esxihostslist = Get-VMHost -Server $vCenterServer -State Connected,Maintenance
      for ( $i=0 ; $i -lt $esxihostslist.Count ; $i++ )
      {
      $esxihostname = $esxihostslist.Name[$i]
      $esxihoststate = $esxihostslist.State[$i]

      $message = "ESXi Host: $($esxihostname) state is $($esxihoststate)"
		  Write-Host $message
	   	Write-Log $message
			$EsxCLIPing = Get-EsxCli -VMHost (Get-VMHost $esxihostname) -V2
      # Create parameters for ping command
      $params = $EsxCLIPing.network.diag.ping.CreateArgs()
      $params.host = $IPAddress
			$params.count = 10
      # Set ping command packet size to 8972 bytes as per VMware's KB# 1003728
      $params.size = '8972'
      $res = $EsxCLIPing.network.diag.ping.Invoke($params)
      # Check the result of the ping and verify packet loss value
      if ( $res.summary.PacketLost -gt 80 )
      {
		  # If packet loss value is more than 1 (Which is 10% of the 10 packets), print and error with the details
      Write-Host "Error: " -ForegroundColor red  -NoNewline
      Write-Host "Ping with Jumbo frames from $($esxihostname) which is managed by vCenter server $($vCenterServer) to IP Address $($IPAddress) failed with $($res.summary.PacketLost)% packet loss"

      # Add error to script log file
			$message = "Error: Ping with Jumbo frames from $($esxihostname) which is managed by vCenter server $($vCenterServer) to IP Address $($IPAddress) failed with $($res.summary.PacketLost)% packet loss"
      Write-Log $message

      # Post a user created event on the ESXi host so it can be pushed to vROPs/vRLI
      $eventManager = Get-View eventManager
      $vmhost = Get-VMHost -Name $esxihostname
      $eventManager.LogUserEvent($vmhost.ExtensionData.MoRef,$message)

      }

      else
      {
      # If there is no packet loss, print a sucess message
      Write-Host "Success: " -ForegroundColor Green  -NoNewline
      Write-Host "Ping with Jumbo frames from $($esxihostname) which is managed by vCenter server $($vCenterServer) to IP Address $($IPAddress) has $($res.summary.PacketLost)% packet loss"

      # Add event to script log file
			$message = "Success: Ping with Jumbo frames from $($esxihostname) which is managed by vCenter server $($vCenterServer) to IP Address $($IPAddress) has $($res.summary.PacketLost)% packet loss"
      Write-Log $message

      # Post a user created event on the ESXi host so it can be pushed to vROPs/vRLI
      $eventManager = Get-View eventManager
      $vmhost = Get-VMHost -Name $esxihostname
      $eventManager.LogUserEvent($vmhost.ExtensionData.MoRef,$message)

       }

       }
		Write-Host "===============================================================================================================================================================================================================================" `r`n
		}

	}


Function Script-Help
{

Write-Host "
.SYNOPSIS
Check Jumbo frames from ESXi hosts managed by vCenter to VMkernel gateways and NFS storage servers.
The script can be ran manually or scheduled. When it runs manually you can specify list of vCenters or specific IP address to be checked from all ESXi hosts.

.DESCRIPTION
Check Jumbo frames from ESXi hosts managed by vCenter to VMkernel gateways and NFS storage servers.
The script sends 10 packets and returns an error if packet loss is more than 10% (i.e more than 1 packet is lost).
The script can be ran manually or scheduled. When it runs manually you can specify list of vCenters or specific IP address to be checked from all ESXi hosts.

.PARAMETER --TestHostsMTU
Check Jumbo frames from ESXi hosts managed by vCenter to VMkernel gateways and NFS storage servers.
This parameter requires the vCenters source list with one of the following parameters --FromInventory or --FromCLI
.PARAMETER --FromInventory
Gets cloud provider vCenter servers list from inventory service
.PARAMETER --FromCLI
Gets vCenter servers list from command line. The vCenter list has to be separated wih single quote.
.PARAMETER --TestIP
Check jumbo frames to specific IP address from all ESXi hosts managed by a vCenter server.
vCenter server and IP address have to be provided.

.EXAMPLE
pwsexec check_mtu_9000.ps1 --TestHostsMTU --FromInventory
Description
---------------------------------------
Gets cloud provider vCenter servers list from inventory service. The script loops on the retrieved vCenters list and check jumbo frames from each ESXi host to VMkernel gateways and to NFS storage servers.

.EXAMPLE
pwsexec check_mtu_9000.ps1 --TestHostsMTU --FromCLI vc1.example.com,vc2.example.com
Description
---------------------------------------
Gets vCenter servers list from command line. The vCenter list has to be separated wih single quote. The script loops on the provided vCenters list and check jumbo frames from each ESXi host to VMkernel gateways and to NFS storage servers.

.EXAMPLE
pwsexec check_mtu_9000.ps1 --TestIP
Type vCenter Server FQDN/IP Address: vc1.example.com
Type the IP Address you want to test Jumbo frames to: 10.17.140.3
Description
---------------------------------------
Check jumbo frames to specific IP address from all ESXi hosts managed by a vCenter server.

.NOTES
Script Name     : check_mtu_9000.ps1
Version		    : 1.0
Created by      : George Gabra
Creation Date   : 19-01-2022 02:25 AM
More info       : TDB
"

}

#-----------------------------------------------------------[Execution]------------------------------------------------------------

#Script Execution goes here

#main()

# Check of flag os passed to get the list of vCenter server from CLI
if ($TestHostsMTU.IsPresent -And $FromCLI.IsPresent)
{
#Split the list of vCenter servers which are passed as parameter to the script
$vCentersList = $vCenters -split ','

# Loop on each vCenter server
foreach ($vCenterServer in $vCentersList)
{

# Open a connection to the vCenter server
$thisConn = Connect-VMwareServer -VMServer $vCenterServer

# Call Check-MTU function and pass the vCenter server name/IP to it
Check-MTU $vCenterServer

# Disconnect from the vCenter server
Disconnect-VIServer -Server * -Force -Confirm:$false
}
}

# Check if flag is  passed to get the list of vCenters from Ralph3 inventory
if ($TestHostsMTU.IsPresent -And $FromInventory.IsPresent)
{
$vCentersList = New-Object System.Collections.Generic.List[System.Object]
$vCentersList = Get-RalphVirtualServers

# Loop on each vCenter server
foreach ($vCenterServer in $vCentersList)
{

# Open a connection to the vCenter server
$thisConn = Connect-VMwareServer -VMServer $vCenterServer

# Call Check-MTU function and pass the vCenter server name/IP to it
Check-MTU $vCenterServer

# Disconnect from the vCenter server
Disconnect-VIServer -Server * -Force -Confirm:$false
}
}

if ($TestIP.IsPresent)
{
Check-MTU-IP
}

if ($Help.IsPresent)
{
Script-Help
}
