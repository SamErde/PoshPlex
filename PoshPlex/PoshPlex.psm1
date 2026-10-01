# Dot source public/private functions
$classes = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Classes/*.ps1') -Recurse -ErrorAction Stop)
$public  = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Public/*.ps1')  -Recurse -ErrorAction Stop)
$private = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Private/*.ps1') -Recurse -ErrorAction Stop)
foreach ($import in @($classes + $public + $private)) {
    try {
        . $import.FullName
    } catch {
        throw "Unable to dot source [$($import.FullName)]"
    }
}

if ($public.Count -gt 0) {
    $functionsToExport = foreach ($script in $public) {
        $tokens = $null
        $parseErrors = $null
        $scriptAst = [System.Management.Automation.Language.Parser]::ParseFile(
            $script.FullName,
            [ref]$tokens,
            [ref]$parseErrors
        )
        if ($parseErrors) {
            throw "Unable to parse public script [$($script.FullName)]"
        }

        $scriptAst.EndBlock.Statements |
            Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] } |
            ForEach-Object -Process { $_.Name }
    }
} else {
    $moduleName = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
    $manifestPath = Join-Path -Path $PSScriptRoot -ChildPath "$moduleName.psd1"
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw "Public scripts are unavailable and module manifest was not found at [$manifestPath]."
    }

    $moduleManifest = Import-PowerShellDataFile -Path $manifestPath
    $functionsToExport = @($moduleManifest.FunctionsToExport)
    if (-not $functionsToExport -or $functionsToExport -contains '*') {
        throw "Public scripts are unavailable and [$manifestPath] does not declare exported functions."
    }
}

if ($functionsToExport) {
    Export-ModuleMember -Function $functionsToExport
}
