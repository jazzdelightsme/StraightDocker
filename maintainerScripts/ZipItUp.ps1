<#
.SYNOPSIS
    Helps the maintainer create a new release .zip. The version should look like x.y.z+YYYYMMDD.
#>
[CmdletBinding()]
param( [Parameter( Mandatory = $true )]
       [string] $Version
     )

try
{
    $versionNumPart, $datePart = $Version.Split( '+' )

    # If it's not a good version string, this will throw:
    $isItReallyAVersion = [version]::Parse( $versionNumPart )

    if( !$datePart -or ($datePart.Length -ne 8) )
    {
        throw "The -Version parameter should look like x.y.z+YYYYMMDD."
    }

    $destDir = "$PSScriptRoot\..\docker"

    if( !(Test-Path "$destDir\docker.exe") -or
        !(Test-Path "$destDir\dockerd.exe") )
    {
        throw "Missing docker[d].exe in: $destDir. You can get them from somewhere like https://master.dockerproject.org."
    }

    $choiceIdx = $Host.UI.PromptForChoice(
            "Have you updated the docker binaries?", # caption
            "This script will zip up the docker binaries (docker.exe, dockerd.exe) in $(Resolve-Path -Relative $destDir). Have you copied in the versions that you want to zip up?",
            @( [System.Management.Automation.Host.ChoiceDescription]::new( 'Y' )
               [System.Management.Automation.Host.ChoiceDescription]::new( 'n' ) ),
            0 ) # default ("Y")

    if( $choiceIdx -ne 0 )
    {
        Write-Host "Well... go do that, then." -Fore Yellow
        Write-Host "You can get them from somewhere like: https://master.dockerproject.org"
        return
    }

    if( !(Test-Path "$destDir\docker-credential-wincred.exe") )
    {
        throw "Missing docker-credential-wincred.exe in: $destDir. You should be able to get it from somewhere like https://github.com/docker/docker-credential-helpers/releases/download/v0.6.0/docker-credential-wincred-v0.6.0-amd64.zip."
    }

    $choiceIdx = $Host.UI.PromptForChoice(
            "Have you got the wincred helper binary?", # caption
            "This script will also zip up the windows credential helper (docker-credential-wincred.exe) in $(Resolve-Path -Relative $destDir). Have you copied in the version that you want to zip up?",
            @( [System.Management.Automation.Host.ChoiceDescription]::new( 'Y' )
               [System.Management.Automation.Host.ChoiceDescription]::new( 'n' ) ),
            0 ) # default ("Y")

    if( $choiceIdx -ne 0 )
    {
        Write-Host "Well... go do that, then." -Fore Yellow
        return
    }

    $descriptionFileName = 'docker_version_description.txt'

    $choiceIdx = $Host.UI.PromptForChoice(
            "Have you updated the $descriptionFileName file?", # caption
            "This script will also zip up the docker_version_description.txt file. Have you updated it to describe the docker binaries that are being zipped up?",
            @( [System.Management.Automation.Host.ChoiceDescription]::new( 'Y' )
               [System.Management.Automation.Host.ChoiceDescription]::new( 'n' ) ),
            0 ) # default ("Y")

    if( $choiceIdx -ne 0 )
    {
        Write-Host "Well... go do that, then." -Fore Yellow
        return
    }

    Copy-Item "$PSScriptRoot\..\$descriptionFileName" $destDir -Force -ErrorAction Stop


    $versionData = [ordered] @{
        Version = $Version # the version of this "straight docker" package

        DockerFileVersion = (Get-ChildItem "$destDir\dockerd.exe").VersionInfo.FileVersion
        # The wincred helper currently isn't stamped with any version info whatsoever.
        WincredVersion = '0.6.0'

        DockerExeSha256  = (Get-FileHash -Algorithm SHA256 -LiteralPath "$destDir\docker.exe").Hash
        DockerdExeSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath "$destDir\dockerd.exe").Hash
        WincredExeSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath "$destDir\docker-credential-wincred.exe").Hash
    }

    $jsonVersionFilePath = Join-Path $destDir 'straightDockerVersion.json'

    $versionData | ConvertTo-Json | Out-File -Encoding utf8 `
                                             -LiteralPath $jsonVersionFilePath `
                                             -ErrorAction Stop `
                                             -Force

    # Make sure we have the licenses:
    Copy-Item "$PSScriptRoot\..\licenses" "$destDir" -Recurse -Force -ErrorAction Stop

    $destZip = "$PSScriptRoot\..\docker.zip"

    Compress-Archive -Path "$PSScriptRoot\..\docker" `
                     -CompressionLevel Optimal `
                     -DestinationPath $destZip `
                     -ErrorAction Stop `
                     -Force # overwrite!

    Write-Host ''
    Write-Host 'Sucess!' -Fore Green
    Write-Host ''
    Write-Host 'The new .zip file is located at: ' -NoNewline
    Write-Host (Resolve-Path -Relative $destZip) -Fore Cyan
    Write-Host ''
    Write-Host 'Be sure to commit and push before actually creating the release.'
    Write-Host ''
}
finally { }

