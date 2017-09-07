$PowerCLIPath = '\\server\share\VMware\PowerCLI\6.5.2.6268016'
$VCSConnectionHistory = "$env:TEMP\lastvcsserver.txt"
$RunningLocation = Get-Location

##*===============================================
##* VARIABLE DECLARATION
##*===============================================
## Variables: Script Name and Script Paths
[string]$scriptPath = $MyInvocation.MyCommand.Definition
[string]$scriptName = [IO.Path]::GetFileNameWithoutExtension($scriptPath)
[string]$scriptFileName = Split-Path -Path $scriptPath -Leaf
[string]$scriptRoot = Split-Path -Path $scriptPath -Parent
[string]$invokingScript = (Get-Variable -Name 'MyInvocation').Value.ScriptName

#  Get the invoking script directory
If ($invokingScript) {
	#  If this script was invoked by another script
	[string]$scriptParentPath = Split-Path -Path $invokingScript -Parent
}
Else {
	#  If this script was not invoked by another script, fall back to the directory one level above this script
	[string]$scriptParentPath = (Get-Item -LiteralPath $scriptRoot).Parent.FullName
}

[boolean]$envRunningInISE = [environment]::commandline -like "*powershell_ise.exe*"
# FUNCTIONS
#=======================================================

function Confirm-PCLIVersion {
    $PSMajMin = ($envPSVersion[0] + "." + $envPSVersion[2])
    if ($PSMajMin -ge "3.0") {
        Write-OutputBox -OutputBoxMessage "Supported version of PowerShell was detected [$PSMajMin]" -Type "INFO: " -Object Tab1
        $WPFtxtPSVersion.Text = $PSMajMin
        $WPFtxtPSVersion.Foreground = '#FF0BEA00'
        return $true
    }
    else {
        Write-OutputBox -OutputBoxMessage "Unsupported version of PowerShell detected [$PSMajMin]. This tool requires PowerShell 3.0 and above" -Type "ERROR: " -Object Tab1
        $lblPSVersionCheck.Content = $PSMajMin
        return $false
    }
}

function Write-OutputBox {
	param(
	[parameter(Mandatory=$true)]
	[string]$OutputBoxMessage,
	[ValidateSet("WARNING","ERROR","INFO","START")]
	[string]$Type
	)
	Process {
		$WPF_txtLogging.AppendText("`n$($Type): $($OutputBoxMessage)")
        [System.Windows.Forms.Application]::DoEvents()
        $WPF_txtLogging.ScrollToEnd()
        
	}
} 

Function Get-VCSServer {
    #[string]$Global:VCSStored = $WPF_txtVCSConnect.Text
    $VCSTextBox = Get-Variable WPF_txtVCSConnect -ValueOnly
    (Set-Variable VCSStored -Scope Global -Value $VCSTextBox.text -PassThru).Value
}

Function Get-DatastoreList{
    #Build the GUI
    [xml]$xaml = @"
<Window 
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    x:Name="Window" Title="Initial Window" WindowStartupLocation = "CenterScreen" 
    Width = "313" Height = "400" ShowInTaskbar = "True" Background = "lightgray">
    <ScrollViewer VerticalScrollBarVisibility="Auto">
        <StackPanel >
            <TextBox IsReadOnly="True" TextWrapping="Wrap">
                Select Datastore (double click)
            </TextBox>
            <Button x:Name="btnGetDatastore" Content="Get Datastores"/>
            <ListBox x:Name="lbDatastoreList"/>
        </StackPanel>
    </ScrollViewer >
</Window>
"@
 
    $reader=(New-Object System.Xml.XmlNodeReader $xaml)
    $Window=[Windows.Markup.XamlReader]::Load( $reader )
 
    #Connect to Controls
    $button = $Window.FindName('btnGetDatastore')
    $listbox = $Window.FindName('lbDatastoreList')
 
    #Events
    $button.Add_Click({
        $datastores = Get-Datastore
        $listbox.ItemsSource = $datastores
    })
     
    $listbox.Add_MouseDoubleClick({
        If ($listbox.SelectedItems.count -eq 1) {
            $WPF_tbDatastore.Text = $listbox.SelectedItem
            Write-OutputBox -OutputBoxMessage "Selected the $($listbox.SelectedItem) datastore" -Type INFO
            $Window.Close()
            $App.Activate()| Out-Null
        } 
        Else{
            [System.Windows.Forms.MessageBox]::Show("Please highlight only one item and try again") 
        }
    })

    $Window.ShowDialog() | Out-Null
}



Function Get-FolderList{
    param(       
        [parameter(Mandatory=$true)]
        $DatastoreName
    )
    #Build the GUI
    [xml]$xaml = @"
<Window 
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    x:Name="Window" Title="Initial Window" WindowStartupLocation = "CenterScreen" 
    Width = "313" Height = "400" ShowInTaskbar = "True" Background = "lightgray">
    <ScrollViewer VerticalScrollBarVisibility="Auto">
        <StackPanel >
            <TextBox IsReadOnly="True" TextWrapping="Wrap">
                Select Folder (double click)
            </TextBox>
            <Button x:Name="btnGetFolders" Content="Get Folders"/>
            <ListBox x:Name="lbFolderList"/>
        </StackPanel>
    </ScrollViewer >
</Window>
"@
 
    $reader=(New-Object System.Xml.XmlNodeReader $xaml)
    $Window=[Windows.Markup.XamlReader]::Load( $reader )
 
    #Connect to Controls
    $GetFolderButton = $Window.FindName('btnGetFolders')
    $FolderListbox = $Window.FindName('lbFolderList')
 
    #Events
    $GetFolderButton.Add_Click({
        $datastore = Get-Datastore $DatastoreName
        $DSDrive = Get-PSDrive | ?{ $_.Name -eq 'ds' }
        If($DSDrive){Remove-PSDrive ds}
        $destination = New-PSDrive -Location $datastore -Name ds -PSProvider VimDatastore -Root "\" -Scope Global -ErrorAction SilentlyContinue
        $DSFolders = Get-childItem -Path ds:\ | ?{ $_.PSIsContainer }
        
        $FolderListbox.ItemsSource = $DSFolders.Name
        
    })
     
    $FolderListbox.Add_MouseDoubleClick({
        $WPF_tbFolder.Text = $FolderListbox.SelectedItem
        Write-OutputBox -OutputBoxMessage "Selected the $($FolderListbox.SelectedItem) sub folder" -Type INFO
        $Window.Close()
        $App.Activate()| Out-Null
    })

    $Window.ShowDialog() | Out-Null
}

Function Get-FileName($initialDirectory)
{
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.initialDirectory = $initialDirectory
    $OpenFileDialog.DefaultExt = '.ISO'
    $OpenFileDialog.Filter = 'All Files|*.*'
    $OpenFileDialog.FilterIndex = 0
    $OpenFileDialog.InitialDirectory = $InitialDirectory
    $OpenFileDialog.Multiselect = $false
    $OpenFileDialog.RestoreDirectory = $true
    $OpenFileDialog.Title = "Select a file"
    $OpenFileDialog.ValidateNames = $true
    $OpenFileDialog.ShowHelp = $true
    $OpenFileDialog.ShowDialog() | Out-Null

    $WPF_txtUpload.text = $OpenFileDialog.filename
    $App.Activate()| Out-Null
}

Function Upload-DSFile{
    param(       
        [parameter(Mandatory=$true)]
        $SourceFile,
        [parameter(Mandatory=$true)]
        $DSDestFolder
    )
    $DSDrive = (Get-PSDrive | ?{ $_.Name -eq 'ds' }).Root
     Write-OutputBox -OutputBoxMessage "Uploading $SourceFile to datastore: $DSDrive" -Type START
    Copy-DatastoreItem -Item $SourceFile -Destination ds:\$DSDestFolder\
     Write-OutputBox -OutputBoxMessage "Finished Uploading file" -Type INFO
}
# LOAD ASSEMBLIES
#=======================================================
[System.Reflection.Assembly]::LoadWithPartialName('WindowsFormsIntegration')  | out-null

[System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')  | out-null
[System.Reflection.Assembly]::LoadWithPartialName('System.ComponentModel') | out-null
[System.Reflection.Assembly]::LoadWithPartialName('System.Data')           | out-null
[System.Reflection.Assembly]::LoadWithPartialName('System.Drawing')        | out-null

[void] [System.Reflection.Assembly]::LoadWithPartialName('PresentationCore')
[void] [System.Reflection.Assembly]::LoadWithPartialName('PresentationFramework')
[void] [System.Reflection.Assembly]::LoadWithPartialName('WindowsBase')

#=======================================================
# LOAD APP XAML (Built with Visual Studio 2015)
#=======================================================
$xaml = {}
#Build the GUI
$xaml = @"
<Window x:Class="VWwareISOUpload.MainWindow"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
        xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
        xmlns:local="clr-namespace:VWwareISOUpload"
        mc:Ignorable="d"
        Title="Datastore File Uploader" Height="350" Width="630"
        ResizeMode="NoResize"
        WindowStartupLocation="CenterScreen"
	    ShowInTaskbar="False">
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="87*"/>
            <RowDefinition Height="20*"/>
        </Grid.RowDefinitions>
        <Label x:Name="lblPSCLIVersion" Content="PowerCLI Installed:" FontSize="10" Margin="422,21.2,-9.4,7.8" Foreground="#FF4C4C4C" Grid.Row="1"/>
        <TextBox x:Name="txtPSCLIVersion" Text="No" FontSize="10" Foreground="Red" FontWeight="Bold" TextWrapping="NoWrap" IsReadOnly="True" IsEnabled="False" Margin="514,26.2,18,7.8" Grid.Row="1"/>
        <TextBlock x:Name="txtUsername" TextAlignment="Right" HorizontalAlignment="Left" Margin="433,6,0,0" TextWrapping="Wrap" Text="test\test" VerticalAlignment="Top" Width="145"/>
        <Button x:Name="btnUsername" Content="..." HorizontalAlignment="Left" Margin="583,3,0,0" VerticalAlignment="Top" Width="26"/>
        <Label x:Name="lblVCSConnect" Content="1. Connect to vCenter Server (FQDN/IP):" HorizontalAlignment="Left" Margin="12,16,0,0" VerticalAlignment="Top" Height="28" Width="234"/>
        <TextBox x:Name="txtVCSConnect" HorizontalAlignment="Left" Height="26" Margin="21,44,0,0" TextWrapping="Wrap" VerticalAlignment="Top" Width="239" FontSize="14"/>
        <Button x:Name="btnVCSConnect" Content="Connect" HorizontalAlignment="Left" Margin="265,44,0,0" VerticalAlignment="Top" Width="117" Height="26"/>
        <TextBox x:Name="txtLogging" HorizontalAlignment="Left" Height="230" Margin="416,52,0,0" TextWrapping="Wrap" VerticalAlignment="Top" Width="190" Grid.RowSpan="2" VerticalScrollBarVisibility="Auto"/>
        <Label x:Name="lblDatabStore" Content="2. Select datastore or type it in:" HorizontalAlignment="Left" Margin="12,71,0,0" VerticalAlignment="Top" Width="192"/>
        <Label x:Name="lblFolder" Content="3. Select a folder or type it in:" HorizontalAlignment="Left" Margin="10,123,0,0" VerticalAlignment="Top" Width="192"/>
        <Label x:Name="lblUpload" Content="4. Browse to File" HorizontalAlignment="Left" Margin="10,178,0,0" VerticalAlignment="Top" Width="150"/>
        <TextBox x:Name="txtUpload" HorizontalAlignment="Left" Height="23" Margin="21,204,0,0" TextWrapping="Wrap" VerticalAlignment="Top" Width="334" FontSize="16"/>
        <Button x:Name="btnBrowse" Content="..." HorizontalAlignment="Left" Margin="360,204,0,33.8" Width="51"/>
        <Button x:Name="btnUpload" Content="UPLOAD" HorizontalAlignment="Left" Margin="253,247,0,0" VerticalAlignment="Top" Width="158" Height="61" Grid.RowSpan="2"/>
        <Label x:Name="lblLabel" Content="Logging:" HorizontalAlignment="Left" Margin="416,26,0,0" VerticalAlignment="Top" Width="147"/>
        <TextBox x:Name="tbDatastore" HorizontalAlignment="Left" Height="26" Margin="21,97,0,0" TextWrapping="Wrap" Text="ISO" VerticalAlignment="Top" Width="183" FontSize="14"/>
        <TextBox x:Name="tbFolder" HorizontalAlignment="Left" Height="26" Margin="21,150,0,0" TextWrapping="Wrap" Text="" VerticalAlignment="Top" Width="183" FontSize="14"/>
        <Button x:Name="btnDatastore" Content="..." HorizontalAlignment="Left" Margin="209,97,0,137.8" Width="51"/>
        <Button x:Name="btnFolder" Content="..." HorizontalAlignment="Left" Margin="209,150,0,84.8" Width="51"/>
        <ProgressBar Name="TransferComplete" HorizontalAlignment="Left" Height="10" Margin="21,232,0,0" VerticalAlignment="Top" Width="334"/>
    </Grid>
</Window>

"@ 
[xml]$xaml = $xaml -replace 'mc:Ignorable="d"','' -replace "x:N",'N' -replace '^<Win.*', '<Window' -replace 'x:Class=*', ''
$reader=(New-Object System.Xml.XmlNodeReader $xaml)
try{$App=[Windows.Markup.XamlReader]::Load( $reader )}
catch{
    $ErrorMessage = $_.Exception.Message
    Write-Host "Unable to load Windows.Markup.XamlReader for $AppXAMLPath. Some possible causes for this problem include: 
    - .NET Framework is missing
    - PowerShell must be launched with PowerShell -sta
    - invalid XAML code was encountered
    - The error message was [$ErrorMessage]" -ForegroundColor White -BackgroundColor Red
    #Exit
}
# Store Form Objects In PowerShell
#===========================================================================
$xaml.SelectNodes("//*[@Name]") | %{Set-Variable -Name "WPF_$($_.Name)" -Value $App.FindName($_.Name)}

# Add events to Form Objects
#===========================================================================
Get-Variable WPF*


# Run prerequisite checks: OS version, powershell version, elevated admin
$PowerCLI = Get-Module VMware.VimAutomation.Cis.Core
If ($PowerCLI){
    Write-OutputBox -OutputBoxMessage "VMware Powershell CLI version $($PowerCLI.Version) is installed" -Type INFO
    $WPF_txtPSCLIVersion.Text = $PowerCLI.Version
} 
Else {
    Write-OutputBox -OutputBoxMessage "VMware Powershell CLI not found; will try to install module" -Type INFO
    Write-Host "VMware Powershell CLI not found; will try to install module" -ForegroundColor Yellow
    Try {
        If(Test-Path $PowerCLIPath){
            $PowerCLIVersion = Split-Path $PowerCLIPath -Leaf
            $UserPCLIModule = "$home\Documents\WindowsPowerShell\Modules\VMware.PowerCLI"
            If (!(Test-Path "$UserPCLIModule\VMware.PowerCLI\$PowerCLIVersion\VMware.PowerCLI.psd1")){
                New-Item -Path $UserPCLIModule -ItemType Directory -ErrorAction SilentlyContinue
                Copy-Item -Path "$PowerCLIPath\*" -Destination $UserPCLIModule –Recurse -ErrorAction SilentlyContinue
            }
            Import-Module "$UserPCLIModule\VMware.PowerCLI\$PowerCLIVersion\VMware.PowerCLI.psd1" -Force
        }
        Else{ 
            Install-Module -Name VMware.PowerCLI -AllowClobber -Scope CurrentUser
        }
        $PowerCLI = Get-Module VMware.VimAutomation.Cis.Core 
        $WPF_txtPSCLIVersion.Text = $PowerCLI.Version
    }
    Catch {
        Write-OutputBox -OutputBoxMessage "Unable to install VMware Powershell CLI, Please try to install it manually" -Type ERROR
        Start-Sleep 30
        $App.Close()
    }
}
#Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false

$WPF_txtUsername.text = "$env:USERDNSDOMAIN\$env:USERNAME"
$WPF_txtVCSConnect.text = Get-Content $VCSConnectionHistory -ErrorAction SilentlyContinue

$WPF_btnUsername.add_Click({
    $Credentials = $host.ui.PromptForCredential("Need credentials", "Please enter your user name and password.", "", "NetBiosUserName") 
    If ($Credentials){$WPF_txtUsername.text = $Credentials.UserName}
})

$WPF_btnVCSConnect.add_Click({ 
    $VCSServer = $WPF_txtVCSConnect.text
    $WPF_txtVCSConnect.text | Out-File $VCSConnectionHistory
    If ($WPF_btnVCSConnect.Content -eq "Connect"){ 
        $WPF_btnVCSConnect.IsEnabled = $false
        Try{
            Write-OutputBox -OutputBoxMessage "Connecting to: $VCSServer" -Type START
            If ($Credentials){
                $Connection = Connect-VIServer -Server $VCSServer -Credential $Credentials
                If (!$Connection){$WPF_btnVCSConnect.IsEnabled = $true;}Else{
                Write-OutputBox -OutputBoxMessage "Connected to: $VCSServer, using creds: $($Credentials.UserName)" -Type INFO}
                $App.Activate()| Out-Null
            }
            Else{ 
                $Connection = Connect-VIServer -Server $VCSServer -User "$env:USERDNSDOMAIN\$env:USERNAME"
                If (!$Connection){$WPF_btnVCSConnect.IsEnabled = $true}Else{
                Write-OutputBox -OutputBoxMessage "Connected to: $VCSServer, using creds: $env:USERDNSDOMAIN\$env:USERNAME" -Type INFO}
                $App.Activate()| Out-Null
            }  
        } 
        Catch {
            $ErrorMessage = $_.Exception.Message
            Write-OutputBox -OutputBoxMessage "Unable to connect to: $VCSServer; $ErrorMessage" -Type ERROR
        }
        If ($Connection.Name -eq $VCSServer){
            $WPF_btnVCSConnect.Content = "Disconnect"
            $WPF_btnVCSConnect.IsEnabled = $true

        }
    }
    Else{
        Try{
            Write-OutputBox -OutputBoxMessage "Disconnecting: $VCSServer" -Type START
            Disconnect-VIServer -Server $VCSServer -Force
            Clear-Variable $Connection -Force
            $WPF_btnVCSConnect.Content = "Connect"
        } 
        Catch {
            $ErrorMessage = $_.Exception.Message
            Write-OutputBox -OutputBoxMessage "Unable to disconnect from: $VCSServer; $ErrorMessage" -Type ERROR
        }
    }
})



$WPF_btnDatastore.add_Click({ 
    Get-DatastoreList
})

$WPF_btnFolder.add_Click({ 
    Get-FolderList -Datastore $WPF_tbDatastore.Text
})

$WPF_btnBrowse.add_Click({ 
    Get-FileName "$ENV:USERPROFILE\Desktop"
})

$WPF_btnUpload.add_Click({
    Upload-DSFile -SourceFile $WPF_txtUpload.text -DSDestFolder $WPF_tbFolder.Text
})

# Shows the form
#===========================================================================
# Allow input to window for TextBoxes, etc

[Void][System.Windows.Forms.Integration.ElementHost]::EnableModelessKeyboardInterop($App)
#App Window (top right) Exit button
$App.Add_Closing({
    #For windows.handler property
    #$_.Cancel = $False
    [System.Windows.Forms.Application]::Exit($null)
    If(!$envRunningInISE){Stop-Process $pid}    
})


If(!$envRunningInISE){
    #Hide-PSConsole # hide the console at start when running exe
    # Make PowerShell Disappear 
    $windowcode = '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);' 
    $asyncwindow = Add-Type -MemberDefinition $windowcode -name Win32ShowWindowAsync -namespace Win32Functions -PassThru 
    $null = $asyncwindow::ShowWindowAsync((Get-Process -PID $pid).MainWindowHandle, 0)
}

#$App.WindowStartupLocation = "CenterScreen"
#$App.Topmost = $True
$App.Show()
#$App.Activate()| Out-Null
#$App.ShowDialog() | Out-Null

# Force garbage collection just to start slightly lower RAM usage.
[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()

Try{
    $AppWindowState = [System.Windows.Forms.FormWindowState]::Normal
    $App.WindowState = $AppWindowState
} 
Catch {
    $ErrorMessage = $_.Exception.Message
    Write-Host "Unable to set WindowsState. May be unsupported in OS version"
}
# Create an application context for it to all run within.
# This helps with responsiveness, especially when clicking Exit.
$appContext = New-Object System.Windows.Forms.ApplicationContext
[System.Windows.Forms.Application]::Run($appContext)