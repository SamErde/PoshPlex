<#
.SYNOPSIS
Tests whether a Plex authentication token is accepted by a server.

.DESCRIPTION
Requests the Plex server identity endpoint and returns the response status
and available server details without throwing for an invalid token.

.PARAMETER Server
Plex server hostname or IP address.
.PARAMETER Port
Plex server API port. The default is 32400.
.PARAMETER Token
Plex authentication token to validate.

.EXAMPLE
Test-PlexToken -Server '192.168.1.10' -Token $env:PLEX_TOKEN

Checks the token and returns its validity and the server identity details.
#>
function Test-PlexToken {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][string]$Server,
        [int]$Port = 32400,
        [Parameter(Mandatory)][string]$Token
    )
    try {
        $raw = Invoke-PlexApi -Server $Server -Port $Port -Path '/identity' -Token $Token -Raw -ErrorAction Stop
        $ok = $raw.StatusCode -eq 200
        $machineId = $null
        $friendly = $null
        $version = $null
        try {
            [xml]$xml = $raw.Content
            $machineId = $xml.MediaContainer.machineIdentifier
            $friendly  = $xml.MediaContainer.friendlyName
            $version   = $xml.MediaContainer.version
        } catch { }
        [PSCustomObject]@{
            Valid             = $ok
            StatusCode        = $raw.StatusCode
            MachineIdentifier = $machineId
            FriendlyName      = $friendly
            Version           = $version
        }
    } catch {
        [PSCustomObject]@{
            Valid      = $false
            StatusCode = $null
            Error      = $_.Exception.Message
        }
    }
}
