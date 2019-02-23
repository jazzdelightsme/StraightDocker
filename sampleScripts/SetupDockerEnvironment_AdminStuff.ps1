<#
.SYNOPSIS
    Sets up a dev environment to run "straight docker" (as opposed to "Docker for Windows" (D4W) from Docker Inc).
#>
[CmdletBinding()]
param( [Parameter( Mandatory = $false )]
       [string] $DownloadsDir,

       [Parameter( Mandatory = $false )]
       [string] $DockerInstallDir,

       [Parameter( Mandatory = $false )]
       [switch] $AddToUserPATH,

       [Parameter( Mandatory = $false )]
       [string] $OkEvent,

       [Parameter( Mandatory = $false )]
       [string] $NeedRebootEvent,

       [Parameter( Mandatory = $false )]
       [string] $ErrorEvent,

       [Parameter( Mandatory = $false )]
       [switch] $DaemonDebug,

       [Parameter( Mandatory = $false )]
       [int] $DaemonLcowTimeout = 400,

       [Parameter( Mandatory = $false )]
       [switch] $DaemonLcowDisableGlobalmode
     )

try
{
    # TODO: check IsAdmin

    $errorOccurred = $true

    if( !$DownloadsDir )
    {
        $DownloadsDir = Join-Path ([System.IO.Path]::GetTempPath()) 'straightDocker'
        $null = mkdir $DownloadsDir -ErrorAction Ignore
    }

    if( !$DockerInstallDir )
    {
        $DockerInstallDir = Join-Path ([System.IO.Path]::GetPathRoot( $PSScriptRoot )) 'docker'
    }

    function SignalEvent( $name )
    {
        if( !$name )
        {
            return
        }

        [bool] $createdNew = $false
        $evt = [System.Threading.EventWaitHandle]::new( $false, # initialState,
                                                        [System.Threading.EventResetMode]::ManualReset,
                                                        $name,
                                                        ([ref] $createdNew) )

        if( $createdNew )
        {
            Write-Host -Fore DarkYellow "(launcher already exited?)"
        }
        else
        {
            $null = $evt.Set()
        }
        $evt.Dispose()
    }


    $ExpectedDataRoot = Join-Path $DockerInstallDir 'dataRoot'
    $LCoW_KernelDir = 'C:\Program Files\Linux Containers'


    function Test-EnvPathContains
    {
        [CmdletBinding()]
        param( [string] $Element )

        try
        {
            return ($env:PATH).Split( ';' ) -contains $Element
        }
        finally { }
    }

    function Install-DownloadableZip
    {
        [CmdletBinding()]
        param( [string] $DisplayName,
               [string] $SourceUri,
               [string] $SourceArchiveFileName,
               [string] $DestPath )

        begin
        {
            try
            {
                $destZipPath = Join-Path $DownloadsDir $SourceArchiveFileName

                # $env:TEST_REUSE_DOWNLOADS: useful for testing, without
                # re-downloading everything every time.

                if( (Test-Path $destZipPath) -and ($env:TEST_REUSE_DOWNLOADS) )
                {
                    Write-Host "(reusing existing archive: $destZipPath)" -Fore DarkMagenta
                }
                else
                {
                    Write-Host "Downloading $DisplayName archive to: $destZipPath" -Fore Cyan

                    #Invoke-WebRequest -Uri $url -OutFile $destZipPath
                    # Curl has a better progress bar:
                    Write-Host "   source URI: $SourceUri" -Fore DarkMagenta
                    curl.exe --progress-bar --location -o $destZipPath $SourceUri

                    if( !$? -or !(Test-Path $destZipPath) )
                    {
                        throw "Failed to download ${DisplayName}."
                    }
                }

                Write-Host "Expanding to: $DestPath" -Fore Cyan
                Expand-Archive $destZipPath $DestPath -ErrorAction Stop

                if( !$env:TEST_REUSE_DOWNLOADS )
                {
                    Remove-Item $destZipPath
                }
            }
            finally { }
        }
    } # end Install-DownloadableZip


    function DownloadAndExtractDockerBinaries
    {
        [CmdletBinding()]
        param()

        begin
        {
            try
            {
                #$url = 'https://master.dockerproject.org/windows/x86_64/docker.zip'

                # Rather than always getting last night's build of docker, let's use a
                # fixed, known-good release:
                $url = 'https://github.com/jazzdelightsme/StraightDocker/releases/download/v0.2.0%2B20190214/docker.zip'

                # N.B. The docker.zip archive contains a single root dir also called
                # 'docker', so we unzip to one directory level up.
                $destPath = Split-Path $DockerInstallDir

                Install-DownloadableZip -DisplayName "Docker" `
                                        -SourceUri $url `
                                        (Split-Path $url -Leaf) `
                                        -DestPath $destPath

                if( !(Test-Path $ExpectedDataRoot) )
                {
                    $null = mkdir $ExpectedDataRoot
                }
            }
            finally { }
        }
    }


    function DownloadAndExtractLCoWKernelBinaries
    {
        [CmdletBinding()]
        param()

        begin
        {
            try
            {
                $url = 'https://github.com/linuxkit/lcow/releases/download/v4.14.35-v0.3.9/release.zip'

                $zipPath = Join-Path $DownloadsDir 'LcowKernelBinaries.zip'
                Write-Host "Downloading LCOW binaries to: $zipPath" -Fore Cyan

                curl.exe -L --progress -o $zipPath $url

                if( !$? -or !(Test-Path $zipPath) )
                {
                    throw "Failed to download LCOW kernel binaries."
                }

                $expectedHash = '9d929afe79b4abd96ffa00841ed0b2178402f773bc85d4f177cdeb339afe44df'
                $hash = (Get-FileHash -Algorith sha256 $zipPath).Hash

                if( $hash -ne $expectedHash )
                {
                    throw "Whoa; file hash does not match?! ($hash versus $expectedHash)"
                }

                Write-Host "Expanding to: $LCoW_KernelDir" -Fore Cyan
                Expand-Archive $zipPath $LCoW_KernelDir -ErrorAction Stop
            }
            finally { }
        }
    }

    $virtFeatures = @( 'HypervisorPlatform', 'Microsoft-Hyper-V', 'Containers' )

    function Test-RequiredVirtualizationEnabled
    {
        [CmdletBinding()]
        param()

        begin
        {
            try
            {
                # If in pwsh, need to load old Windows PowerShell DISM module:
                Import-Module "$($env:WINDIR)\system32\WindowsPowerShell\v1.0\Modules\Dism\Microsoft.Dism.PowerShell.dll" -ErrorAction Stop

                foreach( $featureName in $virtFeatures )
                {
                    $feature = Get-WindowsOptionalFeature -FeatureName $featureName -Online
                    if( !$feature -or ($feature.State -ne 'Enabled') )
                    {
                        return $false
                    }
                }

                return $true
            }
            finally { }
        }
    }


    function Enable-RequiredVirtualizationFeatures
    {
        [CmdletBinding()]
        param()

        begin
        {
            try
            {
                # If in pwsh, need to load old Windows PowerShell DISM module:
                Import-Module "$($env:WINDIR)\system32\WindowsPowerShell\v1.0\Modules\Dism\Microsoft.Dism.PowerShell.dll" -ErrorAction Stop

                [bool] $restartNeeded = $false

                foreach( $featureName in $virtFeatures )
                {
                    Write-Host "   enabling feature: $featureName" -Fore DarkCyan

                    $result = Enable-WindowsOptionalFeature -FeatureName $featureName `
                                                            -Online `
                                                            -NoRestart `
                                                            -ErrorAction Stop `
                                                            -All

                    $restartNeeded = $restartNeeded -or $result.RestartNeeded
                }

                if( $restartNeeded )
                {
                    Write-Host -Fore Yellow 'You must restart your computer to enable container-related features.'
                    return 'STOP'
                }
            }
            finally { }
        }
    }


    # Generic worker function to test things and fix them if the test fails.
    function Invoke-DevEnvironmentCheck
    {
        [CmdletBinding()]
        param( [Parameter( Mandatory = $false, Position = 0 )]
               [string] $TestDescription,

               [Parameter( Mandatory = $false, Position = 1 )]
               [ScriptBlock] $Test,

               [Parameter( Mandatory = $false, Position = 2 )]
               [string] $FixDescription,

               [Parameter( Mandatory = $false, Position = 3 )]
               [ScriptBlock] $Fix
             )
        try
        {
            [bool] $testResult = $false
            if( $Test )
            {
                if( $TestDescription )
                {
                    Write-Host "Check: $TestDescription" -Fore Cyan
                }
                $testResult = & $Test
            }

            if( !$testResult )
            {
                if( $Fix )
                {
                    if( $Test -and $TestDescription ) # Only say "fix required" if there as a test.
                    {
                        Write-Host "Fix required. " -Fore Magenta -NoNewline
                    }
                    if( $FixDescription )
                    {
                        $fixColor = 'DarkCyan'
                        if( $Test -and $TestDescription )
                        {
                            $fixColor = 'Cyan'
                            Write-Host "Applying fix: " -Fore Cyan -NoNewline
                        }
                        Write-Host "$FixDescription" -Fore $fixColor
                    }
                    & $Fix
                }
            }
            else
            {
                if( $TestDescription ) # only say "OK" if there is context
                {
                    Write-Host "OK" -Fore Green
                }
            }
        }
        finally { }
    } # end Invoke-DevEnvironmentCheck


    # based on tools/install-powershell.ps1 from the PowerShell repo
    function AddToPath
    {
        [CmdletBinding()]
        param( [Parameter( Mandatory = $true )]
               [string] $Path,

               [Parameter( Mandatory = $false )]
               [ValidateSet([System.EnvironmentVariableTarget]::User, [System.EnvironmentVariableTarget]::Machine)]
               [System.EnvironmentVariableTarget] $Target = ([System.EnvironmentVariableTarget]::User)
             )

        $rwSubtree = [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree

        if ($Target -eq [System.EnvironmentVariableTarget]::User)
        {
            [Microsoft.Win32.RegistryKey] $baseKey = [Microsoft.Win32.Registry]::CurrentUser
            [string] $Environment = 'Environment'
        }
        else
        {
            [Microsoft.Win32.RegistryKey] $baseKey = [Microsoft.Win32.Registry]::LocalMachine
            [string] $Environment = 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
        }

        [Microsoft.Win32.RegistryKey] $key = $baseKey.OpenSubKey( $Environment, $rwSubtree )

        # $key is null here if it the user was unable to get ReadWriteSubTree access.
        if( $null -eq $key )
        {
            throw [System.Security.SecurityException]::new( "Unable to access the target registry" )
        }

        # Get current UNEXPANDED value
        [string] $curVal = $key.GetValue( 'PATH',
                                          '', # defaultValue
                                          [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames )

        # Keep current value kind if possible/appropriate
        try
        {
            [Microsoft.Win32.RegistryValueKind] $pathValKind = $key.GetValueKind( 'PATH' )
        }
        catch
        {
            [Microsoft.Win32.RegistryValueKind] $pathValKind = [Microsoft.Win32.RegistryValueKind]::ExpandString
        }

        $newVal = [string]::Concat( $curVal.TrimEnd( [System.IO.Path]::PathSeparator ),
                                    [System.IO.Path]::PathSeparator,
                                    $Path )

        # Upgrade pathValKind to [Microsoft.Win32.RegistryValueKind]::ExpandString if appropriate
        if( $newVal.Contains( '%' ) )
        {
            $pathValKind = [Microsoft.Win32.RegistryValueKind]::ExpandString
        }

        $key.SetValue( 'PATH', $newVal, $pathValKind )

        # I'm too lazy to write the proper code to broadcast a WM_SETTINGCHANGE; instead
        # I'll [ab]use setx to do it for me by setting a random variable (and then
        # immediately deleting it).
        $randomEnvVarName = [guid]::NewGuid().ToString()
        setx $randomEnvVarName $randomEnvVarName
        [Environment]::SetEnvironmentVariable( $randomEnvVarName, $null, 'User' )
    } # end AddToPath()


    $Checks = @(
        @{
            TestDescription = "Does docker exist at ${DockerInstallDir}?"
            Test = { Test-Path $DockerInstallDir }
            FixDescription = "Downloading docker"
            Fix = { DownloadAndExtractDockerBinaries }
        }
        ,@{
            TestDescription = "Do LCOW kernel binaries exist at ${LCoW_KernelDir}?"
            Test = {
                $kernel = Join-Path $LCoW_KernelDir 'kernel'
                $initrd = Join-Path $LCoW_KernelDir 'initrd.img'
                return (Test-Path $kernel) -and (Test-Path $initrd)
            }
            FixDescription = "Downloading LCoW Kernel files"
            Fix = { DownloadAndExtractLCoWKernelBinaries }
        }
        ,@{
            Test = { Test-EnvPathContains $DockerInstallDir }
            Fix = {
                $env:PATH = $DockerInstallDir + ";" + $env:PATH
            }
        }
        ,@{
            Test = { $AddToUserPATH }
            Fix = {

                # Note that we retrieve the untouched user PATH from the system, NOT the
                # PATH of the current process.
                $untouchedPath = [System.Environment]::GetEnvironmentVariables( [System.EnvironmentVariableTarget]::User ).Path

                # It could already be in the PATH, even if we just downloaded it.
                if( !($untouchedPath.Split( ';' ) -contains $DockerInstallDir) )
                {
                    # Note that we use the AddToPath helper function, which takes care not
                    # to mess up embedded environment variable references (i.e. it is /
                    # should be a REG_EXPAND_SZ, and we don't want to change that).
                    AddToPath $DockerInstallDir
                }
            } # end Fix
        }
        ,@{
            Test = { Test-RequiredVirtualizationEnabled }
            FixDescription = "Enabling virtualization features"
            Fix = { Enable-RequiredVirtualizationFeatures }
        }
    )


    foreach( $check in $Checks )
    {
        $results = @( Invoke-DevEnvironmentCheck @check )

        if( $results -and ($results.Count -eq 1) -and ($results[ 0 ] -eq 'STOP') )
        {
            Write-Host "(terminating early)" -Fore DarkCyan
            SignalEvent $NeedRebootEvent
            $errorOccurred = $false
            $exitCode = 3010 # ERROR_SUCCESS_REBOOT_REQUIRED
            $host.SetShouldExit( $exitCode ) # get the host to actually exit instead of
                                             # just returning to prompt.
            Start-Sleep -Seconds 6  # Let the user see this screen for a bit before we
                                    # magically disappear.
            exit $exitCode
        }
    }


    # Okay, let's start the daemon.

    # TODO: set the window title, maybe set up an easy way to relaunch the daemon?

    # We want to signal the OkEvent when the daemon comes up. To do that, we'll start a
    # background job that tries to connect to the pipe that docker listens on.
    #
    # PowerShell Core (pwsh) comes with Start-ThreadJob... but Windows Powershell does not.

    if( !(Get-Command Start-ThreadJob -ErrorAction Ignore) )
    {
        Write-Host ''
        Write-Host 'Installing ThreadJob module...'
        Write-Host ''

        Install-Module -Name ThreadJob -ErrorAction Stop
    }

    $pipeWatcherJob = Start-ThreadJob -ErrorAction Stop `
                                      -ArgumentList @( (Get-Command SignalEvent).Definition,
                                                       $OkEvent,
                                                       $ErrorEvent ) `
                                      -ScriptBlock `
    {
        param( $signalEventCmd, $OkEvent, $ErrorEvent )

        [bool] $noError = $false
        $pipeClient = $null
        try
        {
            # TODO: what if /this/ fails?
            New-Item Function:\SignalEvent -Value $signalEventCmd -ErrorAction Stop

            $pipeClient = [System.IO.Pipes.NamedPipeClientStream]::new( '.',
                                                                        'docker_engine',
                                                                        'InOut' )
            try
            {
                $pipeClient.Connect( 15000 ) # 15 second timeout to connect

                SignalEvent $OkEvent
                $noError = $true
            }
            catch [System.TimeoutException]
            {
                # Rats; we couldn't connect. Hopefully there's some output from the main
                # runspace indicating what the problem is.
            }
        }
        finally
        {
            if( !$noError )
            {
                SignalEvent $ErrorEvent
            }
            if( $pipeClient )
            {
                $pipeClient.Dispose()
            }
        }
    } # end thread job scriptblock


    $errorOccurred = $false

    $dockerdPath = Join-Path $DockerInstallDir 'dockerd.exe'
    $userName = [Environment]::UserDomainName + "\" + [Environment]::UserName

    # --experimental    : latest, greatest features
    # -D                : turn on debug spew
    # --data-root       : where image layers etc. are stored
    # lcow.globalmode=1 : less-secure but faster LCOW mode
    # lcow.timeout=400  : longer than the default, useful for dealing with LARGE images
    # --group           : so that you don't need to be elevated to run the client

    $debugSpew = ''
    if( $DaemonDebug )
    {
        $debugSpew = '-D'
    }

    if( $DaemonLcowDisableGlobalmode )
    {
        $lcowGlobalMode = '0'
    }
    else
    {
        $lcowGlobalMode = '1'
    }

    Write-Host "      Data root: $ExpectedDataRoot" -Fore Magenta
    Write-Host " Debug messages: $(if( $debugSpew ) { 'Yes' } else { 'No' })" -Fore Magenta
    Write-Host "LCOW GlobalMode: $lcowGlobalMode" -Fore Magenta
    Write-Host "   LCOW Timeout: $DaemonLcowTimeout" -Fore Magenta
    Write-Host "          Group: $userName" -Fore Magenta

    & $dockerdPath --experimental `
                   $debugSpew `
                   --data-root $ExpectedDataRoot `
                   --storage-opt lcow.globalmode=$lcowGlobalMode `
                   --storage-opt lcow.timeout=$DaemonLcowTimeout `
                   --group $userName
}
finally
{
    if( $errorOccurred )
    {
        SignalEvent $ErrorEvent
    }
}

