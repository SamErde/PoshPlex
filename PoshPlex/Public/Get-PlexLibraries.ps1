<#
.SYNOPSIS
Retrieves the list of Plex libraries from a Plex Media Server.

.DESCRIPTION
Enumerates the library sections exposed by a Plex Media Server and returns
their metadata as PowerShell objects.

.PARAMETER Server
Plex server hostname or IP address.
.PARAMETER Port
Plex server API port. The default is 32400.
.PARAMETER Token
Optional Plex authentication token. PLEX_TOKEN is used when omitted.

.EXAMPLE
Get-PlexLibraries -Server '192.168.1.10' -Port 32400 -Token $env:PLEX_TOKEN

Returns the libraries available on the specified Plex server.
#>
function Get-PlexLibraries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Server,
        [Parameter()][int]$Port = 32400,
        [Parameter()][string]$Token
    )

    $xml = Invoke-PlexApi -Server $Server -Port $Port -Path '/library/sections' -Token $Token

    if (-not $xml.MediaContainer.Directory) {
        Write-Warning 'No libraries returned (possible permission or token issue).'
        return @()
    }

    $libraries = foreach ($section in $xml.MediaContainer.Directory) {
        $created = $null
        $updated = $null
        if ($section.createdAt) { try { $created = [DateTimeOffset]::FromUnixTimeSeconds([int64]$section.createdAt).DateTime } catch { } }
        if ($section.updatedAt) { try { $updated = [DateTimeOffset]::FromUnixTimeSeconds([int64]$section.updatedAt).DateTime } catch { } }

        [PSCustomObject]@{
            Id        = [int]$section.key
            Title     = $section.title
            Type      = $section.type
            Agent     = $section.agent
            Scanner   = $section.scanner
            Language  = $section.language
            Uuid      = $section.uuid
            CreatedAt = $created
            UpdatedAt = $updated
            Locations = @($section.Location | ForEach-Object { $_.path })
        }
    }

    return $libraries | Sort-Object Title
}
