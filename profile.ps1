# Azure Functions profile.ps1
#
# This profile.ps1 will get executed every "cold start" of your Function App.
# "cold start" occurs when:
#
# * A Function App starts up for the very first time
# * A Function App starts up after being de-allocated due to inactivity
#
# You can define helper functions, run commands, or specify environment variables
# NOTE: any variables defined that are not environment variables will get reset after the first execution

# Authenticate with Azure PowerShell using MSI
# Uncomment the next line to enable MSI login
# Connect-AzAccount -Identity

# Import necessary modules
Import-Module Az.Compute
Import-Module Az.Accounts

# You can also define functions or aliases that can be referenced in any of your PowerShell functions
function Write-LogMessage {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Write to Azure Function log
    switch ($Level) {
        'Info'    { Write-Host $logMessage }
        'Warning' { Write-Warning $logMessage }
        'Error'   { Write-Error $logMessage }
    }
}