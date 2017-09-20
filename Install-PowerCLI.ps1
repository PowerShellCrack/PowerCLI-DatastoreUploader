#######################################################################################################################
# PowerCLI installer - Current user
#######################################################################################################################
$LatestModuleVersion = '6.5.2.6268016'

Function Parse-Psd1{
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$false)]
        [Microsoft.PowerShell.DesiredStateConfiguration.ArgumentToConfigurationDataTransformationAttribute()]
        [hashtable] $data
    ) 
    return $data
}

function Copy-WithProgress {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $Source,
        [Parameter(Mandatory = $true)]
        [string] $Destination,
        [int] $Gap = 0,
        [int] $ReportGap = 200,
        [ValidateSet("Directories","Files")]
        [string] $ExcludeType,
        [string] $Exclude,
        [string] $ProgressDisplayName
    )
    # Define regular expression that will gather number of bytes copied
    $RegexBytes = '(?<=\s+)\d+(?=\s+)';

    #region Robocopy params
    # MIR = Mirror mode
    # NP  = Don't show progress percentage in log
    # NC  = Don't log file classes (existing, new file, etc.)
    # BYTES = Show file sizes in bytes
    # NJH = Do not display robocopy job header (JH)
    # NJS = Do not display robocopy job summary (JS)
    # TEE = Display log in stdout AND in target log file
    # XF file [file]... :: eXclude Files matching given names/paths/wildcards.
    # XD dirs [dirs]... :: eXclude Directories matching given names/paths.
    $CommonRobocopyParams = '/MIR /NP /NDL /NC /BYTES /NJH /NJS';
    
    switch ($ExcludeType){
        Files { $CommonRobocopyParams += ' /XF {0}' -f $Exclude };
	    Directories { $CommonRobocopyParams += ' /XD {0}' -f $Exclude };
    }
    
    #endregion Robocopy params
    
    #generate log format
    $TimeGenerated = "$(Get-Date -Format HH:mm:ss).$((Get-Date).Millisecond)+000"
    $Line = '<![LOG[{0}]LOG]!><time="{1}" date="{2}" component="{3}" context="" type="{4}" thread="" file="">'

    #region Robocopy Staging
    Write-Verbose -Message 'Analyzing robocopy job ...';
    $StagingLogPath = '{0}\offlinemodules-staging-{1}.log' -f $env:temp, (Get-Date -Format 'yyyy-MM-dd hh-mm-ss');

    $StagingArgumentList = '"{0}" "{1}" /LOG:"{2}" /L {3}' -f $Source, $Destination, $StagingLogPath, $CommonRobocopyParams;
    Write-Verbose -Message ('Staging arguments: {0}' -f $StagingArgumentList);
    Start-Process -Wait -FilePath robocopy.exe -ArgumentList $StagingArgumentList -WindowStyle Hidden;
    # Get the total number of files that will be copied
    $StagingContent = Get-Content -Path $StagingLogPath;
    $TotalFileCount = $StagingContent.Count - 1;

    # Get the total number of bytes to be copied
    [RegEx]::Matches(($StagingContent -join "`n"), $RegexBytes) | % { $BytesTotal = 0; } { $BytesTotal += $_.Value; };
    Write-Verbose -Message ('Total bytes to be copied: {0}' -f $BytesTotal);
    #endregion Robocopy Staging

    #region Start Robocopy
    # Begin the robocopy process
    $RobocopyLogPath = '{0}\offlinemodules-{1}.log' -f $env:temp, (Get-Date -Format 'yyyy-MM-dd hh-mm-ss');
    $ArgumentList = '"{0}" "{1}" /LOG:"{2}" /ipg:{3} {4}' -f $Source, $Destination, $RobocopyLogPath, $Gap, $CommonRobocopyParams;
    Write-Verbose -Message ('Beginning the robocopy process with arguments: {0}' -f $ArgumentList);
    $Robocopy = Start-Process -FilePath robocopy.exe -ArgumentList $ArgumentList -Verbose -PassThru -WindowStyle Hidden;
    Start-Sleep -Milliseconds 100;
    #endregion Start Robocopy

    #region Progress bar loop
    while (!$Robocopy.HasExited) {
        Start-Sleep -Milliseconds $ReportGap;
        $BytesCopied = 0;
        $LogContent = Get-Content -Path $RobocopyLogPath;
        $BytesCopied = [Regex]::Matches($LogContent, $RegexBytes) | ForEach-Object -Process { $BytesCopied += $_.Value; } -End { $BytesCopied; };
        $CopiedFileCount = $LogContent.Count - 1;
        Write-Verbose -Message ('Bytes copied: {0}' -f $BytesCopied);
        Write-Verbose -Message ('Files copied: {0}' -f $LogContent.Count);
        $Percentage = 0;
        if ($BytesCopied -gt 0) {
           $Percentage = (($BytesCopied/$BytesTotal)*100)
        }
        If ($ProgressDisplayName){$ActivityDisplayName = $ProgressDisplayName}Else{$ActivityDisplayName = 'Robocopy'}
        Write-Progress -Activity $ActivityDisplayName -Status ("Copied {0} of {1} files; Copied {2} of {3} bytes" -f $CopiedFileCount, $TotalFileCount, $BytesCopied, $BytesTotal) -PercentComplete $Percentage
    }
    #endregion Progress loop

    #region Function output
    [PSCustomObject]@{
        BytesCopied = $BytesCopied;
        FilesCopied = $CopiedFileCount;
    };
    #endregion Function output
}



## Variables: Script Name and Script Paths
[string]$scriptPath = $MyInvocation.MyCommand.Definition
[string]$scriptRoot = Split-Path -Path $scriptPath -Parent
$UserPCLIModule = $env:PSModulePath -split ';' | Where {$_ -like "$home*"}

# Check to see if last version folder is there, if not find the next best one
If (!(Test-Path "$scriptRoot\$LatestModuleVersion")){
    Write-Host "WARNING: PowerCLI version: $LatestModuleVersion was not found, checking for differnt version...." -ForegroundColor Yellow
    $LatestModuleVersion = ((Split-Path (Get-ChildItem $scriptRoot -Recurse -Filter VMware.PowerCLI.psd1 | select -Last 1).Fullname -Parent) -split "\\")[-1]
    Write-Host "INFO: Found PowerCLI version: $LatestModuleVersion, loading that instead...." -ForegroundColor Yellow
}

#Install Nuget prereq
$NuGetAssemblySourcePath = Get-ChildItem $scriptRoot -Recurse -Filter nuget -Directory | Where-Object {$_.FullName -match "$LatestModuleVersion" }
$NuGetAssemblyVersion = (Get-ChildItem $NuGetAssemblySourcePath.FullName).Name
$NuGetAssemblyDestPath = "$env:ProgramFiles\PackageManagement\ProviderAssemblies\nuget"
If (!(Test-Path $NuGetAssemblyDestPath\$NuGetAssemblyVersion)){
    Write-Host "Copying nuget Assembly ($NuGetAssemblyVersion) to $NuGetAssemblyDestPath" -ForegroundColor Cyan
    New-Item $NuGetAssemblyDestPath -ItemType Directory -ErrorAction SilentlyContinue
    #Copy-Item -Path "$NuGetAssemblySourcePath\*" -Destination $NuGetAssemblyDestPath –Recurse -ErrorAction SilentlyContinue
    Copy-WithProgress -Source $NuGetAssemblySourcePath.FullName -Destination $NuGetAssemblyDestPath -ProgressDisplayName 'Copying Nuget Assembly Files...'
}

#Install PowerCLI Modules locally
$NetModule = Get-ChildItem $scriptRoot -Recurse -Filter VMware.PowerCLI -Directory | Where-Object {$_.FullName -match "$LatestModuleVersion" }
$PowerCLINetPath = Split-Path $($NetModule.FullName) -Parent

#copy PowerCLI Modules to User directory if they don't exist ($env:PSModulePath)
If (!(Test-Path "$UserPCLIModule\VMware.PowerCLI\$LatestModuleVersion\VMware.PowerCLI.psd1")){
    Write-Host "Copying Vmware PowerCLI Offline Module Files ($LatestModuleVersion) to $UserPCLIModule" -ForegroundColor Cyan
    #New-Item -Path $UserPCLIModule -ItemType Directory -ErrorAction SilentlyContinue
    #Copy-Item -Path "$PowerCLINetPath\*" -Destination $UserPCLIModule –Recurse -ErrorAction SilentlyContinue
   
    #Remove-Item -Path "$UserPCLIModule\nuget" -Recurse -Force -ErrorAction SilentlyContinue
    Copy-WithProgress -Source $PowerCLINetPath -Destination $UserPCLIModule -ExcludeType Directories -Exclude 'nuget' -ProgressDisplayName 'Copying Vmware PowerCLI Modules Files...'
    Copy-Item -Path "$scriptRoot\VMware PowerCLI (32-Bit).lnk" -Destination "$env:USERPROFILE\Desktop" -ErrorAction SilentlyContinue
    Copy-Item -Path "$scriptRoot\VMware PowerCLI.lnk" -Destination "$env:USERPROFILE\Desktop" -ErrorAction SilentlyContinue
}


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
If($LASTEXITCODE -gt 0){Break}
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
