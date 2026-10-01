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
