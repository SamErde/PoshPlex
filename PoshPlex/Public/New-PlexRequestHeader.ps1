<#
.SYNOPSIS
Creates standard request headers for the Plex Media Server API.

.DESCRIPTION
Builds the X-Plex headers used by this module and includes an authentication
token header when a token is supplied.

.PARAMETER Token
Optional Plex authentication token to include in the headers.

.EXAMPLE
New-PlexRequestHeader -Token $env:PLEX_TOKEN

Creates a request header hashtable with the current Plex token.
#>
function New-PlexRequestHeader {
    param(
        [string]$Token
    )

    $headers = @{
        'Accept'                   = 'application/xml'
        'X-Plex-Product'           = 'ErdeFam-Script'
        'X-Plex-Version'           = '1.0'
        'X-Plex-Device'            = 'PowerShell'
        'X-Plex-Platform'          = [System.Environment]::OSVersion.Platform.ToString()
        'X-Plex-Platform-Version'  = [System.Environment]::OSVersion.Version.ToString()
        'X-Plex-Device-Name'       = $env:COMPUTERNAME
        'X-Plex-Client-Identifier' = (Get-PlexClientIdentifier)
    }

    if ($Token) {
        $headers['X-Plex-Token'] = $Token
    }

    return $headers
}
