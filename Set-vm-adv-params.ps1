<#
.SYNOPSIS
	This Script Powers Down a VM, modifies some preconfigured Advanced VM parameters and Starts the VM again
	AUTHOR: Stephan Kuehne
	SCRIPT VERSION: 20201230.01
.DESCRIPTION
	This script will connect to a given vCenter, power down specific VMs, apply advanced parameter and start the vm again
.EXAMPLE
	Set-vm-adv-params -vcenter "vC1_FQDN" -vmlist "vm1,vm2,vm3"
.PARAMETER vcenter
	vcenter FQDN to query
.PARAMETER vmNames
	names of VM to be modified, comma separated and in Quotes
#>

param(
[Parameter(Mandatory = $true, HelpMessage="Please enter vCenter Server FQDN")]
[ValidateNotNullorEmpty()]
[string] $vCenter,
[Parameter(Mandatory = $false, HelpMessage="Please Enter VM Names, comma separated")]
[ValidateNotNullorEmpty()]
[string] $vmlist)

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

    #Split vmNames Input into Array
    $vmNames = $vmlist.split(",");

    ### Setup Advanced Paramters
    $advParams = New-Object VMware.Vim.VirtualMachineConfigSpec

    $advParam1 = New-Object VMware.Vim.OptionValue
    $advParam1.Key = 'isolation.tools.copy.disable'
    $advParam1.Value = 'true'
    $advParams.ExtraConfig += $advParam1

    $advParam2 = New-Object VMware.Vim.OptionValue
    $advParam2.Key = 'isolation.tools.paste.disable'
    $advParam2.Value = 'true'
    $advParams.ExtraConfig += $advParam2

    $advParam3 = New-Object VMware.Vim.OptionValue
    $advParam3.Key = 'RemoteDisplay.maxConnections'
    $advParam3.Value = '1'
    $advParams.ExtraConfig += $advParam3

}
	
Process { 
    # Run through VMs
    foreach ($vmName in $vmNames) {

        ###########################################
        ############## Power Down VM ##############
        ###########################################
        
        $vm = Get-VM -name $vmName -ErrorAction Stop
        if($vm.PowerState -eq 'PoweredOff') {
            Write-Host "-(1)-> VM $vmName already PoweredOff" -ForegroundColor Black -BackgroundColor Green
        } 
        else {
            Write-Host "-(1)-> Power Off VM: $vmName ..." -NoNewline
            Shutdown-VMGuest -VM $vm -confirm:$false > $null
            # Wait until VM is truely powerd off
            while ((Get-VM $vm).PowerState -ne 'PoweredOff') {
                Write-Host "." -NoNewline
                sleep 5
            }
            Write-Host "done" -ForegroundColor Black -BackgroundColor Green 
        }

        ###########################################
        ############## Set Adv Param ##############
        ###########################################

        $vm = Get-VM -name $vmName
        Write-Host "-(2)-> Update VM $vm.name"
        $vm.ExtensionData.ReconfigVM($advParams)


        ###########################################
        ############### Power On VM ###############
        ###########################################

        $vm = Get-VM -name $vmName -ErrorAction Stop  
        if($vm.PowerState -eq 'PoweredOn') {
            Write-Host "-(3)-> VM $vmName is already PoweredOn" -ForegroundColor Black -BackgroundColor Green
        }
        else {
            Write-Host "-(3)-> Powering On VM $vmName - Wating for VMware Tools " -NoNewline
            Start-VM -VM $vm > $null
            while((Get-VM -Name $vmName).ExtensionData.Guest.ToolsStatus -ne 'toolsOk') {
                Write-Host "." -NoNewline
                sleep 5
            }
            Write-Host "done" -ForegroundColor Black -BackgroundColor Green
        }

    }
    Write-Host "<! --- Next --- !>"
    Write-Host ""
}

End {
    #Nothing here yet
}