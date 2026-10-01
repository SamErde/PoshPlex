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
