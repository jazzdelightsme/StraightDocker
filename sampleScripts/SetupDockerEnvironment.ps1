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
       [switch] $RebootIfNeeded,

       [Parameter( Mandatory = $false )]
       [switch] $DaemonDebug,

       [Parameter( Mandatory = $false )]
       [int] $DaemonLcowTimeout = 400,

       [Parameter( Mandatory = $false )]
       [switch] $DaemonLcowDisableGlobalmode
     )

try
{
    if( !$DownloadsDir )
    {
        $DownloadsDir = Join-Path ([System.IO.Path]::GetTempPath()) 'straightDocker'
        $null = mkdir $DownloadsDir -ErrorAction Ignore
    }

    if( !$DockerInstallDir )
    {
        $DockerInstallDir = Join-Path ([System.IO.Path]::GetPathRoot( $PSScriptRoot )) 'docker'
    }

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


    function LaunchDockerDaemon
    {
        if( (Get-CimInstance Win32_ComputerSystem).Model -eq 'Virtual Machine' )
        {
            Write-Host '   ' -NoNewline
            Write-Host 'NOTE:' -Fore Black -Back DarkRed -NoNewline
            Write-Host ' You are running in a VM. If nested virtualization has not been' -Fore Yellow
            Write-Host '   enabled for this VM, ' -Fore Yellow -NoNewline
            Write-Host 'the Docker VM will not be able to start.' -Fore Red -NoNewline
            Write-Host ' To enable' -Fore Yellow
            Write-Host '   nested virtualization, run the following command on the Hyper-V host:' -Fore Yellow
            Write-Host ''
            Write-Host '      Set-VMProcessor -VMName <VMName> -ExposeVirtualizationExtensions $true'
            Write-Host ''
        }

        $okName         = "dockerSetup_ok_"         + [Guid]::NewGuid().ToString()
        $needRebootName = "dockerSetup_needReboot_" + [Guid]::NewGuid().ToString()
        $errorName      = "dockerSetup_error"       + [Guid]::NewGuid().ToString()

        [System.Threading.EventWaitHandle[]] $handles = [System.Threading.EventWaitHandle[]]::new( 3 )

        [int] $idx = 0
        foreach( $name in @( $okName, $needRebootName, $errorName ) )
        {
            [bool] $createdNew = $false
            $handles[ $idx ] = [System.Threading.EventWaitHandle]::new( $false, # initialState,
                                                                        [System.Threading.EventResetMode]::ManualReset,
                                                                        $name,
                                                                        ([ref] $createdNew) )
            $idx++

            if( !$createdNew )
            {
                throw "I expected to create this event new! " + $name
            }
        }

        $newProcArgs = "-ExecutionPolicy Bypass -NoExit -Command & '$PSScriptRoot\SetupDockerEnvironment_AdminStuff.ps1' -DownloadsDir '$DownloadsDir' -DockerInstallDir '$DockerInstallDir' -OkEvent '$okName' -NeedRebootEvent '$needRebootName' -ErrorEvent '$errorName' -DaemonLcowTimeout $DaemonLcowTimeout"

        if( $DaemonDebug )
        {
            $newProcArgs += " -DaemonDebug"
        }

        if( $DaemonLcowDisableGlobalmode )
        {
            $newProcArgs += " -DaemonLcowDisableGlobalMode"
        }

        if( $PSBoundParameters.ContainsKey( 'AddToUserPATH' ) )
        {
            $newProcArgs += " -AddToUserPath:`$$AddToUserPATH"
        }

        # Support either powershell or pwsh:
        $hostProcess = (get-process -id $pid).Name

        $proc = Start-Process -PassThru -Verb RunAs $hostProcess $newProcArgs

        # We poll in order to allow ctrl+c to interrupt us.
        while( $true )
        {
            $idx = [System.Threading.WaitHandle]::WaitAny( $handles, 1000 )
            if( $idx -eq 0 )
            {
                # Everything's OK!
                Write-Host -Fore DarkGreen '(docker ready)'
                break
            }
            elseif( $idx -eq 1 )
            {
                # We need a reboot.
                Write-Host -Fore Yellow 'You must restart your computer to enable container-related features. Please reboot and then re-run this script.'
                Write-Host ''

                if( $RebootIfNeeded )
                {
                    Write-Host '(automatically rebooting)' -Fore DarkCyan
                    Start-Sleep -Seconds 2 # So you can see the message if you are watching.

                    Restart-Computer -Force
                }
                else
                {
                    # Janky signal to tell caller not to continue trying to use
                    # docker.
                    Write-Output 'rebootNeeded'
                }

                break
            }
            elseif( $idx -eq 2 )
            {
                # There was some sort of error.
                Write-Error 'Something went wrong; Docker is not ready. Check the other window for more detail.'
                break
            }
            elseif( $idx = [System.Threading.WaitHandle]::WaitTimeout )
            {
                # (nothing; just polling)
            }
            else
            {
                throw "Unexpected return value from WaitAny: " + $idx
            }

            if( $proc.HasExited )
            {
                Write-Error "There was a problem with the elevated docker launcher process. It's exit code was: $($proc.ExitCode)."
                break
            }
        } # end while( waiting for an event )

        $proc.Dispose()
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


    $Checks = @(
        @{
            # Setting process-local PATH
            Test = { Test-EnvPathContains $DockerInstallDir }
            Fix = { $env:PATH = $DockerInstallDir + ";" + $env:PATH }
        }
        ,@{
            Test = {
                if( Get-Command 'docker.exe' -ErrorAction Ignore -All | where { -not $_.Source.StartsWith( $DockerInstallDir ) } )
                {
                    Write-Warning "There are other docker.exe commands available in your `$Env:PATH--be careful."
                }
            }
        }
        ,@{
            # Launch docker daemon if needed.
            # TODO: check that it's the one we expect?
            Test = { return (Get-Process 'dockerd' -ErrorAction Ignore) }
            FixDescription = 'Launching docker daemon'
            Fix = { LaunchDockerDaemon }
        }
    )

    foreach( $check in $Checks )
    {
        Invoke-DevEnvironmentCheck @check
    }
}
finally { }

