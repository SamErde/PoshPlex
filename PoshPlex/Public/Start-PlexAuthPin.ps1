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
