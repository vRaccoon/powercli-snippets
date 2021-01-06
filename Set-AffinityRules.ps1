<#
.SYNOPSIS
    This Script will either enable or disable all (Anti-)Affinity Rules in the specified Cluster
    AUTHOR: Stephan Kuehne
	SCRIPT VERSION: 20181119.01
.DESCRIPTION
    This Script expect a vCenter FQDN, a Clustername and a DesiredState. It will then get all (Anti-)Affinity Rules in the specified Cluster and compare their Enabled-State to the DesiredState. If they are different, it will set the DesiredState
.EXAMPLE
    Set-AffinityRules.ps1 -vcenter "vC1_FQDN" -Cluster "ClusterA" -DesiredState $false
.EXAMPLE
    Set-AffinityRules.ps1 -vcenter "vC2_FQDN" -Cluster "ClusterB" -DesiredState $true
.PARAMETER vcenter
    vcenter FQDN to query
.PARAMETER Cluster
    vCenter Cluster to check
.PARAMETER DesiredState
    Either $true or $false - state all (Anti-)Affinity Rules will be set to
#>

param(
[Parameter(Mandatory = $true, HelpMessage="Please enter vCenter Server FQDN --> `"FQDN1`"")]
[ValidateNotNullorEmpty()]
[string] $vCenter,

[Parameter(Mandatory = $true, HelpMessage="Please enter Cluster Name --> `"Cluster1`"")]
[ValidateNotNullorEmpty()]
[string] $Clustername,

[Parameter(Mandatory = $true, HelpMessage="Please define state, either `$true or `$false")]
[bool]$DesiredState,

[Parameter(Mandatory = $false, HelpMessage="Please enter output destination")]
[ValidateNotNullorEmpty()]
[string] $savepath)

Begin {
  #################################
	######### vCenter Login #########
	#################################
	
    #Split vCenter Input into Array
    $vClist = $vCenter 

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
    #Get Cluster and check if a Cluster with that name exists; if not, exit script
    $cluster = Get-Cluster -Name $clustername -ErrorAction SilentlyContinue
    if (!$cluster) { 
        Return "No Cluster named $clustername exists" 
        }

    #Get all Rules in that Cluster
    $Rules = Get-DrsRule -Cluster $cluster

    # Go through each rule, an check if its already in the defined state ($DesiredState)
    foreach ($rule in $Rules){
    
        #Check if Rule is already in the defined state - if so, do nothing except creating output
        if($rule.Enabled -eq $DesiredState){

           #Create new Object with Information about modified Rule
           #Adding new Propertie "StateChange" which shows that the Rule was not modified
           $NewRule = [PSCustomObject] @{
                Name = $rule.Name
                Enabled = $rule.Enabled
                Type = $rule.Type
                VMs = (@(foreach ($VM in $rule.VMIds) { (Get-View -Id $VM).Name })-join ',') #Get the VM actual names from the VMIds
                StateChange = "Not Touched"
                }
            $Report += $NewRule
            }
    
        #If rule is not in the desired state, change it
        #Adding new Propertie "StateChange" which shows that the RUle was modified (Previous ($OldSetting and current state $)
        else {
            #Save original state
            $oldState = $rule.Enabled

            # Change original State to desired state, also save the "new" rule into $rule
            $rule = Set-DrsRule -Rule $rule -Enabled $DesiredState
        
            #Create new Object with Information about modified Rule
            #Adding new Propertie "StateChange" which shows that the RUle was not modified
            $NewRule = [PSCustomObject] @{
                Name = $rule.Name
                Enabled = $rule.Enabled
                Type = $rule.Type
                VMs = (@(foreach ($VM in $rule.VMIds) { (Get-View -Id $VM).Name })-join ',') #Get the VM actual names from the VMIds
                StateChange = "$oldState --> $($rule.Enabled)"
                }
            $Report += $NewRule
            }
    }
}

End {
    #If $savepath was set (hence is not null); write $Report in file, else write $Report on Screen
    if($savepath) {
        $Report | Export-Csv "$savepath" -NoTypeInformation
        if ($?) {Write-Host "Output has been saved to $savepath" -BackgroundColor Green}
        }
    else {
        $Report | ft
        }
}