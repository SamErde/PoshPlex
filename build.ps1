[CmdletBinding(DefaultParameterSetName = 'Task')]
param(
    # Build task(s) to execute
    [parameter(ParameterSetName = 'Task', Position = 0)]
    [ArgumentCompleter({
        param($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams)
        $PSakeFile = './PSakeFile.ps1'

        switch ($Parameter) {
            'Task' {
                if ([string]::IsNullOrEmpty($WordToComplete)) {
                    Get-PSakeScriptTasks -BuildFile $PSakeFile | Select-Object -ExpandProperty Name
                }
                else {
                    Get-PSakeScriptTasks -BuildFile $PSakeFile |
                        Where-Object { $_.Name -match $WordToComplete } |
                        Select-Object -ExpandProperty Name
                }
            }

            Default {
            }
        }
    })]
    [string[]]$Task = 'Default',

    # Bootstrap dependencies
    [switch]$Bootstrap,

    # List available build tasks
    [parameter(ParameterSetName = 'Help')]
    [switch]$Help,

    # Optional properties to pass to PSake
    [hashtable]$Properties,

    # Optional parameters to pass to PSake
    [hashtable]$Parameters
)

$ErrorActionPreference = 'Stop'

# Bootstrap Dependencies
if ($Bootstrap.IsPresent) {
    Get-PackageProvider -Name NuGet -ForceBootstrap | Out-Null
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

    if (Test-Path -Path './Requirements.psd1') {
        if (-not (Get-Module -Name PSDepend -ListAvailable)) {
            Install-Module -Name PSDepend -Repository PSGallery -Scope CurrentUser -Force
        }

        Import-Module -Name PSDepend -Verbose:$false
        Invoke-PSDepend -Path './Requirements.psd1' -Install -Import -Force -WarningAction SilentlyContinue
    }
    else {
        Write-Warning 'No [Requirements.psd1] found. Skipping build dependency installation.'
    }
}

# Execute PSake Task(s)
$PSakeFile = './PSakeFile.ps1'

if ($PSCmdlet.ParameterSetName -eq 'Help') {
    Get-PSakeScriptTasks -BuildFile $PSakeFile |
        Format-Table -Property Name, Description, Alias, DependsOn
}
else {
    Set-BuildEnvironment -Force
    Invoke-PSake -BuildFile $PSakeFile -TaskList $Task -NoLogo -Properties $Properties -Parameters $Parameters

    exit ([int](-not $PSake.build_success))
}
