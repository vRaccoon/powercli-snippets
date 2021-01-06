<#
  .SYNOPSIS
    This Scripts checks for version of specific vibs on the ESXi Host
    AUTHOR: Stephan Kuehne
	SCRIPT VERSION: 20181119.01
  .DESCRIPTION
    This Script will check every ESXi-Host in the specified vCenter(s) for version of specified ViBs. Depending on the Parameter it will either
    check a set of "default" ViBs (-defaultViBs), which contains esx-base, esx-nsxv, cisco-vem, net-enic, nenic, ixgben, net-ixgbe, scsi-fnic, powerpath.cim.esx, powerpath.lib.esx, powerpath.plugin.esx
    or add some more ViBs to the default set (-addViBs "lpfc,i40en")
    or only check for a specific set (-listViBs "lpfc,esx-nsxv,net-enic").
    Additionally, it will be checked whether a reboot-image exists.
    The output will be displayed and can optionally also be saved to a csv file (-savepath).
  .EXAMPLE
    Get-VibVersions -vcenter "vC1_FQDN,vC2_FQDN"
    Get-VibVersions -vcenter "vC1_FQDN,vC2_FQDN" -savepath "D:\Temp\output.csv"
    Get-VibVersions -vcenter "vC1_FQDN,vC2_FQDN" -savepath "D:\Temp\output.csv" -addViBs "lpfc,i40en"
    Get-VibVersions -vcenter "vC1_FQDN,vC2_FQDN" -savepath "D:\Temp\output.csv" -listViBs "lpfc,i40en,net-enic"
  .PARAMETER vcenter
    vcenter FQDN to query (comma seperated, in quotes)
  .PARAMETER savepath
    Full path, were to save the file (including File Name)
  .Parameter defaultViBs
    will use the default list of ViBs (esx-base, esx-nsxv, cisco-vem, net-enic, nenic, ixgben, net-ixgbe, scsi-fnic, powerpath.cim.esx, powerpath.lib.esx, powerpath.plugin.esx)
    implicit parameter if neither -addViBs nor -listViBs is specified
  .Parameter addViBs
    more vibs to be checked in addition to the default list (comma seperated, in quotes)
  .Parameter listViBs
    only specified ViBs will be checked (comma seperated, in quotes)
  #>

param(
    [Parameter(Mandatory = $true, HelpMessage="Please enter vCenter Servers FQDN (comma seperated and in quotes) --> `"FQDN1,FQDN2`"")]
    [ValidateNotNullorEmpty()]
    [string] $vCenter,
    [Parameter(Mandatory = $false, HelpMessage="Default list of ViBs will be checked (`"esx-base, esx-nsxv, cisco-vem, net-enic, nenic, ixgben, net-ixgbe, scsi-fnic, powerpath.cim.esx, powerpath.lib.esx, powerpath.plugin.esx`"", ParameterSetName='defaultViBs')]
    [ValidateNotNullorEmpty()]
    [switch] $defaultViBs,
    [Parameter(Mandatory = $true, HelpMessage="Please enter ViBs to checked (comma seperated and in quotes) --> `"i40en,lpfc`"", ParameterSetName='addViBs')]
    [ValidateNotNullorEmpty()]
    [string] $addViBs,
    [Parameter(Mandatory = $true, HelpMessage="Please enter ViBs to be added to the default Set (comma seperated and in quotes) --> `"i40en,lpfc`"", ParameterSetName='listViBs')]
    [ValidateNotNullorEmpty()]
    [string] $listViBs,
    [Parameter(Mandatory = $false, HelpMessage="Please enter output destination (including File Name)")]
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
    $Report = @() # Final Object
    
}

Process {
    # Define ViBList depending on what was choosen on the Parameter during function call
    # For $defaultViBs, leave the array as it is
    # For $addViBs, just add the specified ViBs to the default set of ViBs (defined in Beginn{})

    if($addViBs) { $vibs += $addViBs.Split(",") 
    } ElseIF ($listViBs)  { $vibs += $listViBs.Split(",") 
    } else { $vibs = @("esx-base","esx-nsxv","cisco-vem","net-enic","nenic","ixgben","net-ixgbe","scsi-fnic","powerpath.cim.esx","powerpath.lib.esx","powerpath.plugin.esx") # Default List of ViBs to be checked 
    }
         
    Write-Host "Following ViBs will be checked:`n $vibs"
    $esxihosts = Get-VMHost # List of all ESXi Hosts to be 
    
    # Run through each host, get esxcli and query for all required Vibs
    $i=1
    foreach ($esxihost in $esxihosts) {
        Write-Progress -Activity "Host:" -status "$esxihost ($i/$($esxihosts.count))" -percentComplete ($i / $esxihosts.count*100) -Id 0
        $i++


        # Get ESXiCLI (USing V1 to have it compatible with PowerCLI 6.0)
        $esxcli = Get-EsxCli -VMHost $esxihost

        # Get all ViBs installed on Host
        $hostvibs = $esxcli.software.vib.list()
        
        # Check for Reboot-Image by querying its ViBs and set $rebootimage depeing on existance (no reboot-image --> no ViBs for it) 
        if ($esxcli.software.vib.list.($true)) {
            $rebootimage = $true
        } 
        else {
            $rebootimage = $false
        }

        # Create an object for the ViB-Versions on the current Host
        # Then run through the previously generated list of all ViBs and filter only for versions of the specified ViBs
        # Add them to Custom Object, afterwards add the this Object to final Object $Report
        $hostvibversions = New-Object -TypeName psobject
        $hostvibversions | Add-Member -MemberType NoteProperty –Name "Hostname" –Value $esxihost.Name
        $hostvibversions | Add-Member -MemberType NoteProperty –Name "RebootImage" –Value $rebootimage
        $j=1
        foreach ($vib in $vibs) {
            Write-Progress -Activity "ViB:" -status "$vib ($j/$($vibs.count))" -percentComplete ($j / $vibs.count*100) -Id 1
            $j++
            $hostvibversions | Add-Member -MemberType NoteProperty –Name $vib –Value $($hostvibs | Where-Object Name -eq $vib | select version -ExpandProperty Version)
        }
        $Report += $hostvibversions

    }
}


End {
  # Display Results
    $Report | fl

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