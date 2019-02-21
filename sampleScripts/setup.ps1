<#
.SYNOPSIS
    Sample environment setup script which downloads and starts "straight docker" (https://github.com/jazzdelightsme/StraightDocker).

    You must run this on a version of Windows 10 new enough that it has curl.exe included.

    It will enable Hyper-V and container-related features of Windows.

    These scripts are not intended to be "production ready"; they are a sample that you can incorporate or build upon.

.PARAMETER DockerDebug
    *If* starting dazzle starts the docker daemon (dockerd), turns on debug spew from the daemon.

.PARAMETER DockerLcowTimeout
    *If* starting dazzle starts the docker daemon (dockerd), sets the LCOW timeout (could be needed to deal with large image layers).

.PARAMETER DockerLcowDisableGlobalmode
    *If* starting dazzle starts the docker daemon (dockerd), turns off LCOW global mode (for troubleshooting).

.PARAMETER AddDockerToUserPATH
    Useful for unattended first-time setup (to avoid a prompt).

.PARAMETER RebootIfNeeded
    Useful for unattended first-time setup (to avoid a prompt).
#>
[CmdletBinding( PositionalBinding = $false )]
param(
       [Parameter( Mandatory = $false )]
       [switch] $DockerDebug,

       [Parameter( Mandatory = $false )]
       [int] $DockerLcowTimeout,

       [Parameter( Mandatory = $false )]
       [switch] $DockerLcowDisableGlobalmode,

       #
       # Args useful for unattended first-time setup (to avoid prompts)
       #

       [Parameter( Mandatory = $false )]
       [switch] $AddDockerToUserPATH,

       [Parameter( Mandatory = $false )]
       [switch] $RebootIfNeeded
     )

try
{
    Set-StrictMode -Version Latest

    $curlCmd = Get-Command curl.exe -ErrorAction Ignore

    if( !$curlCmd -or ($curlCmd.Source -ne 'C:\WINDOWS\system32\curl.exe') )
    {
        throw "You need to be running a version of Windows 10 that is new enough to have curl.exe as part of it."
    }

    # Rather than have to wait through a download, get prompted, wait through another
    # download, get prompted, wait for optional features to be enabled, get prompted,
    # etc.; we'll just do some detection and prompt up front.

    function Test-RequiredVirtualizationEnabled
    {
        # The "real" way to test this would be to use Get-WindowsOptionalFeature, but
        # that requires elevation.
        #
        # We are going to need to spawn an elevated process later (to run dockerd), so
        # we could launch one now to be our "do stuff elevated" proxy, but that seems
        # a little complicated.
        #
        # So we're going for a super cheap, low-quality hack: probing for the
        # existence of certain files.
        #
        # It's not the end of the world if this gets the wrong answer: when the
        # features are actually probed or enabled (in the elevated portion of the
        # script), the user will be told if they need to reboot; we just won't do it
        # automatically based on this up-front prompt.

        $filesToCheck = @( 'C:\Windows\system32\vmcompute.exe'
                           'C:\Windows\system32\VmCrashDump.dll '
                           'C:\Windows\system32\vmwp.exe'
                           'C:\Windows\system32\drivers\vmswitch.sys'
                           'C:\Windows\system32\drivers\vmsvcext.sys'
                           'C:\Windows\system32\vmms.exe'
                           'C:\Windows\system32\hvc.exe'
                           'C:\Windows\system32\HyperVSysprepProvider.dll'
                           'C:\Windows\system32\VmDataStore.dll'
                           'C:\Windows\system32\CCG.exe'
                         )

        foreach( $fileToCheck in $filesToCheck )
        {
            if( !(Test-Path $fileToCheck) )
            {
                return $false
            }
        }

        return $true
    } # end Test-RequiredVirtualizationEnabled


    if( !($PSBoundParameters.ContainsKey( 'AddDockerToUserPATH' )) -and !(Get-Command 'docker' -ErrorAction Ignore) )
    {
        try
        {
            $choiceIdx = $Host.UI.PromptForChoice(
                    "Persist Docker to PATH?", # caption
                    "This script will download Docker binaries (xcopy install). Would you like to add docker to your user PATH environment variable?",
                    @( [System.Management.Automation.Host.ChoiceDescription]::new( 'Y' )
                       [System.Management.Automation.Host.ChoiceDescription]::new( 'n' ) ),
                    0 ) # default ("Y")
        }
        catch [System.Management.Automation.PSInvalidOperationException]
        {
            # We must be running non-interactive. Default to adding it to the PATH.
            $choiceIdx = 0
        }

        $AddDockerToUserPATH = 0 -eq $choiceIdx
    }

    if( !($PSBoundParameters.ContainsKey( 'RebootIfNeeded' )) -and !(Test-RequiredVirtualizationEnabled) )
    {
        try
        {
            $choiceIdx = $Host.UI.PromptForChoice(
                    "Automatically reboot?", # caption
                    "This script will enable virtualization features (Hyper-V, Containers), which will require a reboot. Would you like to automatically reboot at the end of this script?",
                    @( [System.Management.Automation.Host.ChoiceDescription]::new( 'y' )
                       [System.Management.Automation.Host.ChoiceDescription]::new( 'N' ) ),
                    1 ) # default ("N")
        }
        catch [System.Management.Automation.PSInvalidOperationException]
        {
            # We must be running non-interactive. Default to automatically rebooting.
            $choiceIdx = 0
        }

        $RebootIfNeeded = 0 -eq $choiceIdx
    }


    # Let's get Docker going. This will download and "install" it if necessary.
    try
    {
        $script = "$PSScriptRoot\SetupDockerEnvironment.ps1"

        $scriptArgs = @{
            'ErrorAction' = 'Stop'
            'RebootIfNeeded' = $RebootIfNeeded
            'AddToUserPATH' = $AddDockerToUserPATH
            'DaemonDebug' = $DockerDebug
            'DaemonLcowDisableGlobalmode' = $DockerLcowDisableGlobalmode
        }

        if( $DockerLcowTimeout -ne 0 ) # leave the default up to the SetupDockerEnvironment script
        {
            $scriptArgs[ 'DaemonLcowTimeout' ] = $DockerLcowTimeout
        }

        $result = & $script @scriptArgs

        if( $result -eq 'rebootNeeded' )
        {
            return $false # The caller should exit; we're done
        }

        Write-Host ''
        Write-Host 'Docker should be running now. Try running "docker run -it ubuntu bash".'
        Write-Host ''

        return $true # LGTM
    }
    catch
    {
        Write-Error $_
        return $false # The caller should exit; we're done
    }
}
finally { } # ensure terminating errors are actually terminating

