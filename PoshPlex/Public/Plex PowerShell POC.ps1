# Plex Media Server (PMS) simple API helpers
# Date: 2025-10-04
# Purpose: Connect to a Plex Media Server instance and list libraries (sections).
# Reference: https://developer.plex.tv/pms/ (official docs)

<#
.SYNOPSIS
    Retrieves the list of Plex libraries (sections) from a Plex Media Server.

.DESCRIPTION
    Provides lightweight helper functions to call the Plex Media Server API
    for enumerating library sections. Designed for local network use.

    Authentication: Most PMS endpoints require an X-Plex-Token. This script will:
        1. Use the -Token parameter when supplied
        2. Else use the value in $env:PLEX_TOKEN if present
        3. Otherwise attempt an unauthenticated request (may fail with 401/401)

    The script adds standard X-Plex-* headers recommended by Plex so that the
    server can correctly attribute the client.

.EXAMPLE
    PS> . .\PlexMediaServerAPI.ps1
    PS> Get-PlexLibraries -Server 192.168.1.10 -Port 5501 -Token (Get-Content .\plex_token.txt -Raw)

.EXAMPLE
    PS> $env:PLEX_TOKEN = 'your-token-here'
    PS> Get-PlexLibraries -Server 192.168.1.10 -Port 5501 | Format-Table

.OUTPUTS
    PSCustomObject for each library section with properties:
        Id, Title, Type, Agent, Scanner, Language, Uuid, CreatedAt, UpdatedAt, Locations

.NOTES
    Time values are converted from Unix epoch seconds when available.
    Network errors and HTTP failures are surfaced with readable messages.
#>

param(
    [string]$Server = '192.168.1.10',
    [int]$Port = 5501,
    [string]$Token
)

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

<#
.SYNOPSIS
Sends a request to the Plex Media Server API.

.DESCRIPTION
Sends an HTTP GET request to the specified Plex API path. By default, the
response is parsed as XML; use -Raw to return the complete web response.

.PARAMETER Server
Plex server hostname, IP address, or absolute server URL.
.PARAMETER Port
Plex server API port. This is ignored when Server is an absolute URL.
.PARAMETER Path
Plex API path to request, such as /identity.
.PARAMETER Token
Optional authentication token. PLEX_TOKEN is used when this parameter is omitted.
.PARAMETER Query
Optional query-string parameters to add to the request.
.PARAMETER Raw
Returns the complete web response instead of parsing its content as XML.

.EXAMPLE
Invoke-PlexApi -Server '192.168.1.10' -Path '/identity'

Requests the server identity and returns the parsed XML response.
#>
function Invoke-PlexApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Server,
        [Parameter()][int]$Port = 32400,
        [Parameter(Mandatory)][string]$Path,
        [Parameter()][string]$Token,
        [Parameter()][hashtable]$Query,
        [switch]$Raw
    )

    if (-not $Token) { $Token = $env:PLEX_TOKEN }

    $scheme = 'http'
    if ($Server -match '^https?://') { # Allow passing full URL
        $base = $Server.TrimEnd('/')
    } else {
        $base = "${scheme}://${Server}:$Port"
    }

    $uriBuilder = [System.UriBuilder]::new($base)
    $relative = $Path.TrimStart('/')
    if ($uriBuilder.Path.EndsWith('/')) {
        $uriBuilder.Path = $uriBuilder.Path + $relative
    } else {
        $uriBuilder.Path = $uriBuilder.Path + '/' + $relative
    }

    $queryParams = @{}
    if ($Query) { $Query.GetEnumerator() | ForEach-Object { $queryParams[$_.Key] = $_.Value } }
    if ($Token) { $queryParams['X-Plex-Token'] = $Token }
    if ($queryParams.Count -gt 0) {
        $uriBuilder.Query = ($queryParams.GetEnumerator() | ForEach-Object { "{0}={1}" -f [System.Web.HttpUtility]::UrlEncode($_.Key), [System.Web.HttpUtility]::UrlEncode([string]$_.Value) }) -join '&'
    }

    $uri = $uriBuilder.Uri.AbsoluteUri

    Write-Verbose "GET $uri"

    try {
        $response = Invoke-WebRequest -Uri $uri -Headers (New-PlexRequestHeader -Token $Token) -Method GET -ErrorAction Stop
    } catch {
        $errMsg = $_.Exception.Message
        $status = $null
        $snippet = $null
        if ($_.Exception.Response) {
            try { $status = $_.Exception.Response.StatusCode.value__ } catch { }
            try {
                $reader = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream())
                $content = $reader.ReadToEnd()
                if ($content) { $snippet = ($content.Substring(0, [Math]::Min(200, $content.Length))).Trim() }
            } catch { }
        }
        $detail = @()
        if ($status) { $detail += "Status=$status" }
        if ($snippet) { $detail += "BodySnippet='${snippet}'" }
        $detailText = if ($detail.Count) { ' (' + ($detail -join '; ') + ')' } else { '' }
        throw "Plex API request failed: $errMsg$detailText"
    }

    if ($Raw) { return $response }

    # Attempt to parse XML (default PMS response for this endpoint)
    try {
        [xml]$xml = $response.Content
        return $xml
    } catch {
        throw 'Failed to parse Plex response as XML.'
    }
}

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

<#
.SYNOPSIS
    Acquire a Plex authentication token using account credentials.
.DESCRIPTION
    Performs a POST to https://plex.tv/users/sign_in.json with Basic authentication
    (username:password) and required X-Plex-* headers. Returns the auth token.
    Prefer using a SecureString for the password. You can also be prompted.
.PARAMETER Username
    Plex account username (email) or managed user login.
.PARAMETER Password
    SecureString or plain text password. If omitted, will prompt securely.
.PARAMETER SetEnv
    If specified, sets $env:PLEX_TOKEN with the retrieved token.
.PARAMETER SaveTo
    Optional file path to save ONLY the token (no newline decoration). Directory must exist.
.PARAMETER Quiet
    Suppress output of the token to the pipeline (useful with -SetEnv / -SaveTo).
.EXAMPLE
    New-PlexAuthTokenBasic -Username 'user@example.com' -SetEnv

Prompts for the account password and stores the token in PLEX_TOKEN.

.EXAMPLE
    New-PlexAuthTokenBasic -Username 'user@example.com' -SaveTo .\plex_token.txt

Prompts for the account password and saves the token to the specified file.
#>
function New-PlexAuthTokenBasic {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][string]$Username,
        [Parameter()][Object]$Password,
        [switch]$SetEnv,
        [string]$SaveTo,
        [switch]$Quiet
    )

    if (-not $Password) {
        $Password = Read-Host -AsSecureString -Prompt 'Plex Password'
    } elseif ($Password -is [string]) {
        # Convert plain string to SecureString for consistent handling
        $plainTemp = $Password
        $Password = ConvertTo-SecureString -String $plainTemp -AsPlainText -Force
        $plainTemp = $null
    }

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR([System.Security.SecureString]$Password)
    try { $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    $basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$Username`:$plain"))
    # Zero out plain variable after use (best effort)
    $plain = $null

    $headers = New-PlexRequestHeader -Token $null
    $headers['Authorization'] = "Basic $basic"
    $headers['Accept'] = 'application/json'

    $uri = 'https://plex.tv/users/sign_in.json'
    try {
        $response = Invoke-WebRequest -Method Post -Uri $uri -Headers $headers -ErrorAction Stop
    } catch {
        throw "Failed to sign in to Plex: $($_.Exception.Message)"
    }

    if (-not $response.Content) { throw 'Empty response from Plex sign-in.' }
    try { $json = $response.Content | ConvertFrom-Json } catch { throw 'Unable to parse JSON from Plex sign-in.' }
    $token = $json.user.authToken
    if (-not $token) { throw 'Auth token not found in Plex response.' }

    if ($SetEnv) { $env:PLEX_TOKEN = $token }
    if ($SaveTo) { Set-Content -Path $SaveTo -Value $token -NoNewline -Encoding ASCII }
    if (-not $Quiet) { return $token }
}

<#
.SYNOPSIS
    Initiate or complete a Plex PIN (device link) authentication flow.
.DESCRIPTION
    Requests a PIN code from Plex and optionally polls until the user links it via
    https://plex.tv/link. When the token is issued, returns it. Useful when you
    don't want to enter the account password directly.
.PARAMETER StartOnly
    Emit the PIN info and do not poll for completion.
.PARAMETER PollIntervalSec
    Seconds between polling attempts (default 5).
.PARAMETER TimeoutSec
    Maximum seconds to wait for token (default 300).
.PARAMETER SetEnv
    Sets $env:PLEX_TOKEN when token obtained.
.PARAMETER SaveTo
    Saves token to a file when token obtained.
.PARAMETER Quiet
    Suppress token output (still returns object without printing token if desired).
.EXAMPLE
    Start-PlexAuthPin  # Shows code and waits until linked, returns token.

Displays the PIN and waits for the Plex account to complete device linking.

.EXAMPLE
    Start-PlexAuthPin -StartOnly  # Just get the code and link manually later.

Displays the PIN information and returns without polling for completion.
#>
function Start-PlexAuthPin {
    [CmdletBinding()] param(
        [switch]$StartOnly,
        [int]$PollIntervalSec = 5,
        [int]$TimeoutSec = 300,
        [switch]$SetEnv,
        [string]$SaveTo,
        [switch]$Quiet
    )

    $headers = New-PlexRequestHeader -Token $null
    $headers['Accept'] = 'application/json'
    $pinUri = 'https://plex.tv/pins.json?strong=true'
    try {
        $pinResp = Invoke-WebRequest -Method Post -Uri $pinUri -Headers $headers -ErrorAction Stop
    } catch {
        throw "Failed to request PIN: $($_.Exception.Message)"
    }
    $rawJson = $pinResp.Content
    try { $pinJson = $rawJson | ConvertFrom-Json } catch { throw "Unable to parse PIN JSON response. Raw: $rawJson" }
    Write-Verbose ("PIN raw JSON: " + ($rawJson.Substring(0, [Math]::Min(400, $rawJson.Length))))

    # Normalize potential structures (array, nested, flat)
    if ($pinJson -is [System.Collections.IEnumerable] -and -not ($pinJson -is [string])) {
        # Take first element if array-like
        $pinJson = ($pinJson | Select-Object -First 1)
    }
    if ($pinJson.psobject.Properties.Name -contains 'pin') {
        $pin = $pinJson.pin
    } else {
        $pin = $pinJson
    }

    if (-not $pin) { throw 'PIN response missing expected object.' }
    $props = $pin.psobject.Properties.Name
    if (-not ($props -contains 'code')) { throw "PIN code field missing. Properties available: $($props -join ', ')" }

    # Determine expiration using multiple possible names
    $expires = $null
    $expiresInSeconds = 300
    if ($props -contains 'expiresIn') {
        $val = $pin.expiresIn
        if ($val -and [int]::TryParse([string]$val, [ref]([int]$null))) { try { $expiresInSeconds = [int]$val } catch { } }
        $expires = [DateTime]::UtcNow.AddSeconds($expiresInSeconds)
    } elseif ($props -contains 'expires_at') {
        try { $expires = [DateTime]::Parse($pin.expires_at).ToUniversalTime() } catch { $expires = [DateTime]::UtcNow.AddSeconds($expiresInSeconds) }
    } elseif ($props -contains 'expiresAt') {
        try { $expires = [DateTime]::Parse($pin.expiresAt).ToUniversalTime() } catch { $expires = [DateTime]::UtcNow.AddSeconds($expiresInSeconds) }
    } else {
        $expires = [DateTime]::UtcNow.AddSeconds($expiresInSeconds)
    }


    $result = [PSCustomObject]@{
        Id        = $pin.id
        Code      = $pin.code
        ExpiresAt = $expires.ToLocalTime()
        Token     = $null
        Linked    = $false
        Polls     = 0
        LinkUrl   = 'https://plex.tv/link'
    }

    # User prompt for PIN linking
    Write-Host "" -ForegroundColor Yellow
    Write-Host "==== Plex Device Link Required ====" -ForegroundColor Yellow
    Write-Host ("Go to: " + $result.LinkUrl) -ForegroundColor Yellow
    Write-Host ("Enter this code: " + $result.Code) -ForegroundColor Yellow
    Write-Host ("(Expires at: " + $result.ExpiresAt + ")") -ForegroundColor Yellow
    Write-Host "" -ForegroundColor Yellow

    if ($StartOnly) { return $result }

    $pollUri = "https://plex.tv/pins/$($pin.id).json"
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSec)
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Seconds $PollIntervalSec
        $result.Polls++
        try {
            $pollResp = Invoke-WebRequest -Method Get -Uri $pollUri -Headers $headers -ErrorAction Stop
            $pollJson = $pollResp.Content | ConvertFrom-Json
        } catch {
            Write-Verbose "Poll failed: $($_.Exception.Message)"; continue
        }
        # Normalize poll structure and extract token supporting both authToken and auth_token
        $pinPoll = $null
        if ($pollJson -and ($pollJson.psobject.Properties.Name -contains 'pin')) {
            $pinPoll = $pollJson.pin
        } else {
            $pinPoll = $pollJson
        }
        $token = $null
        if ($pinPoll) {
            $pinProps = $pinPoll.psobject.Properties.Name
            if ($pinProps -contains 'authToken') { $token = $pinPoll.authToken }
            elseif ($pinProps -contains 'auth_token') { $token = $pinPoll.auth_token }
        }
        if ($token) {
            $result.Token  = $token
            $result.Linked = $true
            if ($SetEnv) { $env:PLEX_TOKEN = $token }
            if ($SaveTo) { Set-Content -Path $SaveTo -Value $token -NoNewline -Encoding ASCII }
            if (-not $Quiet) { return $token }
            return $result
        }
        if ([DateTime]::UtcNow -gt $expires) { break }
    }
    Write-Warning 'PIN link not completed before timeout or expiration.'
    return $result
}

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

if ($ExecutionContext.SessionState.Module) {
    Export-ModuleMember -Function Get-PlexLibraries, Invoke-PlexApi, New-PlexRequestHeader, Get-PlexClientIdentifier, New-PlexAuthTokenBasic, Start-PlexAuthPin, Test-PlexToken
}

# Convenience execution: if not dot-sourced AND a Server value was provided (default provided), list libraries.
<#
NOTE: Automatic execution removed to avoid unintended calls when importing as a module.
To list libraries manually after importing or dot-sourcing:
    Get-PlexLibraries -Server $Server -Port $Port -Token $Token
Or acquire a token first via Start-PlexAuthPin / New-PlexAuthTokenBasic.
#>
