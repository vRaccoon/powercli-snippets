<#
  .SYNOPSIS
  This Scripts checks for all Paths from each ESXiHost to each Datastore
  AUTHOR: Stephan Kuehne
  SCRIPT VERSION: 20181119.01
  .DESCRIPTION
  This script will run through each Host in the specified vCenter and check each Path on each esxihost to each Datastore (/LUN) and will then give a summary of Total/Active/Death Paths from each host to each Datastore
  If -savepath is specified, it will export the results as csv
  .EXAMPLE
  Get-Pathss -vcenter "vC1_FQDN,vC2_FQDN"
  Get-Paths -vcenter "vC1_FQDN,vC2_FQDN" -savepath "D:\Temp\"
  .PARAMETER vcenter
  vcenter FQDN to query
  .PARAMETER savepath
  Full path, were to save the file
  #>

param(
    [Parameter(Mandatory = $true, HelpMessage="Please enter vCenter Servers FQDN (comma seperated and in quotes) --> `"FQDN1,FQDN2`"")]
    [ValidateNotNullorEmpty()]
    [string] $vCenter,
    [Parameter(Mandatory = $false, HelpMessage="Please enter output destination")]
    [ValidateNotNullorEmpty()]
    [string] $savepath
)


Begin {
    #################################
	######### vCenter Login #########
	#################################
	
    #Split vCenter Input into Array
    $vClist = $vCenter.split(",");

    # Get Login Credentials
    $admincred = Get-Credential

    # Check $global:defaultviservers for actie VI Sessions
    # If it is null, connect to specified VI Server
    # If it is not null, disconnect active VI Server first and connect to specified VI Servers afterwards
    if (!$global:defaultviservers) {
        foreach($vC in $vClist){ 
            Connect-VIServer -Credential $admincred -Server $vC 
        }
    } else {
        foreach($vC in $global:defaultviservers){ 
            Write-Host "Disconnecting from vCenter $vC ..."
            Disconnect-VIServer -Server $vC -Confirm:$false
        }
        foreach($vC in $vClist){ 
            Connect-VIServer -Credential $admincred -Server $vC 
        }
    }
    
    ### Initialize Base variables
    $DSView = @() # Datastore View
    $DSReport = @() # Datastore Summary
    $Report = @() # FInal Report

}

Process {
    # Get a list of all available Datastores
    $DSs = Get-Datastore

    ## Get-View from Datastore to extrakt Canonical
    foreach ($DS in $DSs) {
    
   	    $DSview = $DS | Get-View
	    $DSObject = [PSCustomObject] @{
		    DSName= $DS.Name
		    Canonical = $DSview.Info.vmfs.Extent[0].DiskName
        }
        $DSReport += $DSObject
    }


    # Get all ESXI Hosts in selected vCenters
    $ESXiHosts = Get-VMHost

    $i = 1
    foreach ($ESXiHost in $ESXiHosts) {
	    Write-Progress -Activity "Counting paths on host:" -status "$ESXiHost ($i/$($ESXiHosts.count))" -percentComplete ($i / $ESXiHosts.count*100) -Id 0
        $i++

        # Get esxcli
        $esxcli = Get-EsxCli -VMHost $ESXiHost -V2
	    $devices = $esxcli.storage.core.path.list.invoke() | select Device -Unique
    
        # Go through all devices on that host and get the path-counts
        $j = 1
	    foreach ($device in $devices) {
		    Write-Progress -Activity "Counting paths on device:" -status "$device ($j/$($devices.count))" -percentComplete ($j / $devices.count*100) -Id 1
            $j++

            # Create CLI arguments, save device
            $args = $esxcli.storage.core.path.list.CreateArgs()
		    $args.device = $device.Device
        
            # invoke list of device again, but only for one device
		    $LUNs = $esxcli.storage.core.path.list.Invoke($args)
        
            # Combine Information
		    $LUNReport = [PSCustomObject] @{
			    HostName = $ESXiHost.Name
			    Device = $device.Device
			    "Active Paths" = ($LUNs | Where-Object State -EQ active).count
			    "Err paths" = ($LUNs | Where-Object State -NE active).count
			    "DS Name" = ($DSReport | Where-Object Canonical -EQ $device.Device).DSName -join '; '
			    LUNIDs = $LUNs.LUN | Select-Object -Unique
		    }
		    $Report += $LUNReport
	    }
    }
}

End {
    # Display Results
    $Report | Sort-Object Hostname, LUNIDs | ft

   #If $savepath was set (hence is not null); write $Report in file, else write $Report on Screen
    if($savepath) {
        $Report | Export-Csv "$savepath" -NoTypeInformation
        if ($?) {Write-Host "Output has been saved to $savepath" -BackgroundColor Green}
        }
    
    # Disconnect from all previously connected vCenters
    foreach($vC in $vClist){ 
        Disconnect-VIServer $vC -Force -Confirm:$false 
    }
}
    