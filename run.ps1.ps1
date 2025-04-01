using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log
Write-Host "PowerShell HTTP trigger function processed a request."

# Initialize response object
$statusCode = [HttpStatusCode]::OK
$body = ""

try {
    # Get request body
    $reqBody = $Request.Body | ConvertFrom-Json

    # Extract parameters from the request
    $ansibleScript = $reqBody.ansible_script
    $resourceGroupName = $reqBody.resource_group_name ?? "test-ub"
    $vmName = $reqBody.vm_name ?? "workernode01-win"
    $domainUsername = $reqBody.domain_username ?? "domain\user"
    $domainPassword = $reqBody.domain_password ?? "xxxxxxxx"
    $subscriptionId = $reqBody.subscription_id ?? "xxxxxxxxxxxxxxxxx"
    $location = $reqBody.location ?? "East US"

    if (-not $ansibleScript) {
        $statusCode = [HttpStatusCode]::BadRequest
        $body = @{
            error = "No Ansible script provided"
        } | ConvertTo-Json
        
        # Associate values to output bindings by calling 'Push-OutputBinding'.
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $statusCode
            Body = $body
            ContentType = "application/json"
        })
        return
    }

    # Define the SubscriptionId directly
    $AzureContext = Connect-AzAccount -Identity
    $AzureContext = Set-AzContext -SubscriptionId $subscriptionId -DefaultProfile $AzureContext

    # Check and output the current Azure context
    $azContext = Get-AzContext
    Write-Host "Identity CONTEXT AFTER:"
    Write-Host ($azContext | Format-Table | Out-String)

    # Generate a random string for the command name
    $randomString = [System.Guid]::NewGuid().ToString("N").Substring(0, 6)
    $commandName = "RunAnsibleScript_$randomString"

    # Create the PowerShell script that will run Ansible on the VM
    $scriptContent = @"
# PowerShell script to run Ansible on Windows
# This script runs as the domain user $domainUsername

# Write to a log file for troubleshooting
`$logFile = "C:\AnsibleRun_$randomString.log"
"Starting Ansible execution at `$(Get-Date)" | Out-File -FilePath `$logFile

# Check if Ansible is installed
try {
    `$ansibleExists = Test-Path -Path "C:\Program Files\ansible" -ErrorAction SilentlyContinue
    "Ansible installation check: `$ansibleExists" | Out-File -FilePath `$logFile -Append
    
    if (-not `$ansibleExists) {
        "Installing prerequisite software..." | Out-File -FilePath `$logFile -Append
        
        # Install Chocolatey if not already installed
        if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
            "Installing Chocolatey..." | Out-File -FilePath `$logFile -Append
            Set-ExecutionPolicy Bypass -Scope Process -Force
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
            Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
        }
        
        # Install Ansible using Chocolatey
        "Installing Ansible..." | Out-File -FilePath `$logFile -Append
        choco install ansible -y
        
        # Refresh environment variables
        `$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    }
} catch {
    "Error checking/installing Ansible: `$_" | Out-File -FilePath `$logFile -Append
}

# Create a temporary directory for Ansible files
`$tempDir = "C:\AnsibleTemp_$randomString"
New-Item -ItemType Directory -Path `$tempDir -Force | Out-Null

# Create the Ansible playbook file
`$playbookPath = "`$tempDir\playbook.yml"

"Creating Ansible playbook at `$playbookPath" | Out-File -FilePath `$logFile -Append

@'
$ansibleScript
'@ | Out-File -FilePath `$playbookPath -Encoding utf8

# Create a simple inventory file
`$inventoryPath = "`$tempDir\inventory.ini"
@'
[local]
localhost ansible_connection=local
'@ | Out-File -FilePath `$inventoryPath -Encoding utf8

# Create an ansible.cfg file
`$ansibleCfgPath = "`$tempDir\ansible.cfg"
@'
[defaults]
host_key_checking = False
retry_files_enabled = False
log_path = `$tempDir\ansible.log
'@ | Out-File -FilePath `$ansibleCfgPath -Encoding utf8

# Set environment variables for Ansible
`$env:ANSIBLE_CONFIG = `$ansibleCfgPath

# Run the Ansible playbook as the current user (which is the domain user)
"Running Ansible playbook..." | Out-File -FilePath `$logFile -Append

try {
    # The crucial part - this runs as the domain user because the entire script is running as that user
    `$output = ansible-playbook -i `$inventoryPath `$playbookPath -v
    `$output | Out-File -FilePath `$logFile -Append
    "Ansible playbook execution completed successfully" | Out-File -FilePath `$logFile -Append
} catch {
    "Error running Ansible playbook: `$_" | Out-File -FilePath `$logFile -Append
}

# Return the log file content as output
if (Test-Path -Path `$logFile) {
    Get-Content -Path `$logFile
} else {
    "Log file not found"
}

# Clean up
Remove-Item -Path `$tempDir -Recurse -Force -ErrorAction SilentlyContinue
"Cleanup completed at `$(Get-Date)" | Out-File -FilePath `$logFile -Append
"@

    # Log the script execution info
    Write-Host "Executing Ansible script on VM: $vmName as user: $domainUsername"

    # Check if there are any existing run commands that need to be removed
    Write-Host "Checking for existing run commands on VM: $vmName"
    $existingRunCommands = Get-AzVMRunCommand -ResourceGroupName $resourceGroupName -VMName $vmName

    # If any run commands exist, remove them except for the latest one
    if ($existingRunCommands.Count -gt 0) {
        Write-Host "Removing previous run commands..."
        $commandsToRemove = $existingRunCommands | Sort-Object -Property CreatedTime -Descending | Select-Object -Skip 1

        foreach ($cmd in $commandsToRemove) {
            Remove-AzVMRunCommand -ResourceGroupName $resourceGroupName -VMName $vmName -RunCommandName $cmd.Name
            Write-Host "Removed Run Command: $($cmd.Name)"
        }
    }

    # Execute the script on the VM using Set-AzVMRunCommand
    Write-Host "Starting run command: $commandName"

    # Execute the run command
    $result = Set-AzVMRunCommand -ResourceGroupName $resourceGroupName `
                      -VMName $vmName `
                      -RunCommandName $commandName `
                      -Location $location `
                      -ScriptString $scriptContent `
                      -RunAsUser $domainUsername `
                      -RunAsPassword $domainPassword `
                      -Verbose `
                      -Debug `
                      -Confirm:$false
                      
    # Extract the results
    $output = $result.Value[0].Message

    # Return the response
    $responseBody = @{
        command_name = $commandName
        vm_name = $vmName
        output = $output
        success = $true
    } | ConvertTo-Json
    
    $body = $responseBody
}
catch {
    $statusCode = [HttpStatusCode]::InternalServerError
    $errorMessage = $_.Exception.Message
    Write-Host "Error: $errorMessage"
    $body = @{
        error = $errorMessage
    } | ConvertTo-Json
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = $statusCode
    Body = $body
    ContentType = "application/json"
})