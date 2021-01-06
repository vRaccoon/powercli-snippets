<#
.SYNOPSIS
	This Script exports all currently configured Affinity Rules from all the Clusters of the given vCenters
	AUTHOR: Stephan Kuehne
	SCRIPT VERSION: 20181119.01
.DESCRIPTION
	This script will connect to each given vCenter, check each cluster for (Anti-)Affinity Rules, displays them and export them into a csv files if -savepath is specified.
.EXAMPLE
	Get-AffinityRulesc -vcenter "vC1_FQDN,vC2_FQDN" -savepath "D:\Temp\output.csv"
.EXAMPLE
	Get-AffinityRules -vcenter "vC1_FQDN,vC2_FQDN"
.PARAMETER vcenter
	vcenter FQDN to query
.PARAMETER savepath
	Full path, were to save the file
#>

param(
[Parameter(Mandatory = $true, HelpMessage="Please enter vCenter Servers FQDN (comma seperated and in quotes) --> `"vC1_FQDN,vC2_FQDN`"")]
[ValidateNotNullorEmpty()]
[string] $vCenter,
[Parameter(Mandatory = $false, HelpMessage="Please enter output destination")]
[ValidateNotNullorEmpty()]
[string] $savepath)

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
    $Report = @() # Final Output
    
	$clusters = get-cluster
}
Process {   
    $i=1 # Write-Progress variable
	## Run Through Clusters to collect all Affinity Rules
    foreach ($cluster in $clusters) {
        Write-Progress -Activity "Cluster:" -status "$cluster ($i/$($clusters.count))" -percentComplete ($i / $clusters.count*100) -Id 0
        $i++
        #Get all rules in that Cluster
        $rules = Get-DrsRule -Cluster $cluster

        #Go through each rule
        $j=1
        foreach ($rule in $rules) {
        Write-Progress -Activity "Rule:" -status "$rule ($j/$($rules.count))" -percentComplete ($j / $rules.count*100) -Id 1
        $j++
            $RulesReport = [PSCustomObject] @{
                Cluster = $cluster.Name
                Name = $rule.Name
                Enabled = $rule.Enabled
                Type = $rule.Type
                VMIDs = (@(foreach ($VM in $rule.VMIds) { (Get-View -Id $VM).Name })-join ',') #Get the VM actual names from the VMIds
            }
        $Report += $RulesReport
        }
    }
}
End {
    $Report | ft
    #If $savepath was set (hence is not null); write $Report in file, else write $Report on Screen
    if($savepath) {
        $Report | Export-Csv "$savepath" -NoTypeInformation
        if ($?) {Write-Host "Output has been saved to $savepath" -BackgroundColor Green}
        }

    # Disconnect from vCenters
    foreach($vC in $vClist){ 
        Disconnect-VIServer -Server $vC -Force -Confirm:$false
        if ($?) { Write-Host "Disconnected from vCenter $vc" }
    }
}

