# Test script to call the Azure Function

# Replace with your Azure Function URL and function key
$functionUrl = "https://your-function-app.azurewebsites.net/api/AnsibleVMTrigger?code=your-function-key"

# Read the sample Ansible playbook file
$playbookPath = Join-Path -Path $PSScriptRoot -ChildPath "sample-ansible-playbook.yml"
$ansibleScript = Get-Content -Path $playbookPath -Raw

# Prepare the request body
$requestBody = @{
    ansible_script = $ansibleScript
    resource_group_name = "test-ub"                   # Your resource group
    vm_name = "workernode01-win"                      # Your VM name
    domain_username = "dctest01\test"                 # Domain username
    domain_password = "Demo@123456"                   # Domain password
    subscription_id = "fad00f76-8d05-4998-8cb0-48d8939cda39"  # Your subscription ID
    location = "East US"                              # VM location
} | ConvertTo-Json

# Call the function
$response = Invoke-RestMethod -Uri $functionUrl -Method Post -Body $requestBody -ContentType "application/json"

# Display the response
$response | ConvertTo-Json -Depth 10

# You can also test with a direct embedded script:
<#
$requestBody = @{
    ansible_script = @"
---
- name: Simple Ansible Test
  hosts: localhost
  connection: local
  gather_facts: no
  
  tasks:
    - name: Get current user
      win_shell: whoami
      register: current_user
    
    - name: Display current user
      debug:
        msg: "Current user is {{ current_user.stdout }}"
"@
    resource_group_name = "test-ub"
    vm_name = "workernode01-win"
    domain_username = "dctest01\test"
    domain_password = "Demo@123456"
    subscription_id = "fad00f76-8d05-4998-8cb0-48d8939cda39"
    location = "East US"
} | ConvertTo-Json

$response = Invoke-RestMethod -Uri $functionUrl -Method Post -Body $requestBody -ContentType "application/json"
$response | ConvertTo-Json -Depth 10
#>