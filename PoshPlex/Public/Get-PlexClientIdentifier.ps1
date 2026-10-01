<#
.SYNOPSIS
Gets or creates the persistent Plex client identifier.

.DESCRIPTION
Reuses the identifier stored in the current user's profile, or creates and
stores a new identifier when no saved value is available.

.EXAMPLE
Get-PlexClientIdentifier

Returns the client identifier used in Plex API requests.
#>
function Get-PlexClientIdentifier {
    $idFile = Join-Path $env:APPDATA 'PlexClientId.txt'
    if (Test-Path $idFile) {
        try { return (Get-Content -Path $idFile -Raw).Trim() } catch { }
    }
    $newId = [guid]::NewGuid().ToString('N')
    try { Set-Content -Path $idFile -Value $newId -Encoding ASCII -Force } catch { }
    return $newId
}
