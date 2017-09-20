#######################################################################################################################
# This file will be removed when PowerCLI is uninstalled. To make your own scripts run when PowerCLI starts, create a
# file named "Initialize-PowerCLIEnvironment_Custom.ps1" in the same directory as this file, and place your scripts in
# it. The "Initialize-PowerCLIEnvironment_Custom.ps1" is not automatically deleted when PowerCLI is uninstalled.
#######################################################################################################################
param([bool]$promptForCEIP = $false)


Function Parse-Psd1{
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$false)]
        [Microsoft.PowerShell.DesiredStateConfiguration.ArgumentToConfigurationDataTransformationAttribute()]
        [hashtable] $data
    ) 
    return $data
}

## Variables: Script Name and Script Paths
[string]$scriptPath = $MyInvocation.MyCommand.Definition
[string]$scriptRoot = Split-Path -Path $scriptPath -Parent
$UserPCLIModule = $env:PSModulePath -split ';' | Where {$_ -like "$home*"}

# List of modules to be loaded
$LocalModule = Get-ChildItem $UserPCLIModule -Recurse -Filter VMware.PowerCLI -Directory
$MainModulePSD1 = (Get-ChildItem $LocalModule.FullName -Recurse -Filter *.psd1).FullName
$ParsedPSD1 = Parse-Psd1 $MainModulePSD1
$PowerCLIVersion = $ParsedPSD1.ModuleVersion
$moduleList = $ParsedPSD1.RequiredModules

$productName = "PowerCLI"
$productShortName = "PowerCLI"

$loadingActivity = "Loading $productName"
$script:completedActivities = 0
$script:percentComplete = 0
$script:currentActivity = ""
$script:totalActivities = `
   $moduleList.Count + 1

function ReportStartOfActivity($activity) {
   $script:currentActivity = $activity
   Write-Progress -Activity $loadingActivity -CurrentOperation $script:currentActivity -PercentComplete $script:percentComplete
}
function ReportFinishedActivity() {
   $script:completedActivities++
   $script:percentComplete = (100.0 / $totalActivities) * $script:completedActivities
   $script:percentComplete = [Math]::Min(99, $percentComplete)
   
   Write-Progress -Activity $loadingActivity -CurrentOperation $script:currentActivity -PercentComplete $script:percentComplete
}

# Load modules
function Load-DependencyModules(){
    ReportStartOfActivity "Searching for $productShortName module components..."

   

   $loaded = Get-Module -Name $moduleList.ModuleName -ErrorAction Ignore | % {$_.Name}
   $registered = Get-Module -Name $moduleList.ModuleName -ListAvailable -ErrorAction Ignore | % {$_.Name}
   $notLoaded = $null
   $notLoaded = $registered | ? {$loaded -notcontains $_}
   
   ReportFinishedActivity
   
   foreach ($module in $registered) {
      if ($loaded -notcontains $module) {
		 ReportStartOfActivity "Loading module $module"
         
		 Import-Module $module
		 
		 ReportFinishedActivity
      }
   }
}

Load-DependencyModules
#Import-Module $MainModulePSD1

# Update PowerCLI version after snap-in load
$powerCliFriendlyVersion = [VMware.VimAutomation.Sdk.Util10.ProductInfo]::PowerCLIFriendlyVersion
$host.ui.RawUI.WindowTitle = $powerCliFriendlyVersion

$productName = "PowerCLI"

# Launch text
write-host "          Welcome to VMware $productName!"
write-host ""
write-host "Log in to a vCenter Server or ESX host:              " -NoNewLine
write-host "Connect-VIServer" -foregroundcolor yellow
write-host "To find out what commands are available, type:       " -NoNewLine
write-host "Get-VICommand" -foregroundcolor yellow
write-host "To show searchable help for all PowerCLI commands:   " -NoNewLine
write-host "Get-PowerCLIHelp" -foregroundcolor yellow  
write-host "Once you've connected, display all virtual machines: " -NoNewLine
write-host "Get-VM" -foregroundcolor yellow
write-host "If you need more help, visit the PowerCLI community: " -NoNewLine
write-host "Get-PowerCLICommunity" -foregroundcolor yellow
write-host ""
write-host "       Copyright (C) VMware, Inc. All rights reserved."
write-host ""
write-host ""

# CEIP
Try	{
	$configuration = Get-PowerCLIConfiguration -Scope Session

	if ($promptForCEIP -and
		$configuration.ParticipateInCEIP -eq $null -and `
		[VMware.VimAutomation.Sdk.Util10Ps.CommonUtil]::InInteractiveMode($Host.UI)) {

		# Prompt
		$caption = "Participate in VMware Customer Experience Improvement Program (CEIP)"
		$message = `
			"VMware's Customer Experience Improvement Program (`"CEIP`") provides VMware with information " +
			"that enables VMware to improve its products and services, to fix problems, and to advise you " +
			"on how best to deploy and use our products.  As part of the CEIP, VMware collects technical information " +
			"about your organization’s use of VMware products and services on a regular basis in association " +
			"with your organization’s VMware license key(s).  This information does not personally identify " +
			"any individual." +
			"`n`nFor more details: press Ctrl+C to exit this prompt and type `"help about_ceip`" to see the related help article." +
			"`n`nYou can join or leave the program at any time by executing: Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP `$true or `$false. "

		$acceptLabel = "&Join"
		$choices = (
			(New-Object -TypeName "System.Management.Automation.Host.ChoiceDescription" -ArgumentList $acceptLabel,"Participate in the CEIP"),
			(New-Object -TypeName "System.Management.Automation.Host.ChoiceDescription" -ArgumentList "&Leave","Don't participate")
		)
		$userChoiceIndex = $Host.UI.PromptForChoice($caption, $message, $choices, 0)
		
		$participate = $choices[$userChoiceIndex].Label -eq $acceptLabel

		if ($participate) {
         [VMware.VimAutomation.Sdk.Interop.V1.CoreServiceFactory]::CoreService.CeipService.JoinCeipProgram();
      } else {
         Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -Confirm:$false | Out-Null
      }
	}
} Catch {
	# Fail silently
}
# end CEIP

Write-Progress -Activity $loadingActivity -Completed


cd \
