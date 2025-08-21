# PQLint API PowerShell Module
# Provides functions to interface with the PQLint API for linting Power Query M code and TMDL code
# Cross-platform compatible (Windows/Linux)

# API Configuration
$script:ApiBaseUrl = "https://api.pqlint.com/v1"

# Cross-platform URL encoding function
function Get-UrlEncodedString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputString
    )
    
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        # PowerShell 6+ cross-platform
        return [System.Uri]::EscapeDataString($InputString)
    } else {
        # Windows PowerShell 5.1
        try {
            Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
            return [System.Web.HttpUtility]::UrlEncode($InputString)
        } catch {
            # Fallback manual encoding for basic cases
            return $InputString.Replace(' ', '%20').Replace('&', '%26').Replace('=', '%3D')
        }
    }
}

# Helper function to make HTTP requests with proper error handling
function Invoke-PQLintApiRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        
        [Parameter(Mandatory = $false)]
        [string]$Method = 'GET',
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Headers = @{},
        
        [Parameter(Mandatory = $false)]
        [object]$Body,
        
        [Parameter(Mandatory = $false)]
        [string]$ContentType = 'application/json'
    )
    
    try {
        $requestParams = @{
            Uri = $Uri
            Method = $Method
            Headers = $Headers
            ContentType = $ContentType
        }
        
        if ($Body) {
            if ($Body -is [hashtable] -or $Body -is [PSCustomObject]) {
                $requestParams.Body = ($Body | ConvertTo-Json -Depth 10)
            } else {
                $requestParams.Body = $Body
            }
        }
        
        $response = Invoke-RestMethod @requestParams
        return $response
    }
    catch {
        $errorDetails = $_.Exception.Message
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode
            $statusDescription = $_.Exception.Response.StatusDescription
            
            try {
                # Cross-platform compatible error response reading
                if ($PSVersionTable.PSVersion.Major -ge 6) {
                    # PowerShell Core
                    $errorStream = $_.Exception.Response.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader($errorStream)
                    $errorBody = $reader.ReadToEnd()
                    $reader.Close()
                } else {
                    # Windows PowerShell 5.1
                    $errorStream = $_.Exception.Response.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader($errorStream)
                    $errorBody = $reader.ReadToEnd()
                    $reader.Close()
                }
                
                if ($errorBody) {
                    $errorObject = $errorBody | ConvertFrom-Json
                    $errorDetails = "HTTP $([int]$statusCode) $statusDescription - $($errorObject.body)"
                }
            }
            catch {
                $errorDetails = "HTTP $([int]$statusCode) $statusDescription - $errorDetails"
            }
        }
        
        throw "PQLint API Error: $errorDetails"
    }
}

<#
.SYNOPSIS
    Retrieves all linting rules from the PQLint API.

.DESCRIPTION
    This function calls the /lint/rules endpoint to get a list of all available linting rules
    with their IDs, names, categories, descriptions, severity levels, and other metadata.

.EXAMPLE
    Get-LintingRules
    
    Retrieves all available linting rules.

.OUTPUTS
    Array of PSCustomObject representing linting rules with properties:
    - id: The ID of the rule
    - name: The name of the rule
    - category: The category of the rule
    - description: The description of the rule
    - references: Array of reference objects with link and description
    - severity: The severity level of the rule
    - minLicenseLevel: The minimum license level required for the rule
#>
function Get-LintingRules {
    [CmdletBinding()]
    param()
    
    Write-Verbose "Retrieving linting rules from PQLint API"
    
    $uri = "$script:ApiBaseUrl/lint/rules"
    
    try {
        $rules = Invoke-PQLintApiRequest -Uri $uri -Method 'GET'
        
        Write-Verbose "Successfully retrieved $($rules.Count) linting rules"
        return $rules
    }
    catch {
        Write-Error "Failed to retrieve linting rules: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Lints Power Query M code or TMDL code using the PQLint API.

.DESCRIPTION
    This function sends code to the PQLint API for analysis and returns linting results.
    Supports both Power Query M code and TMDL code with configurable options.

.PARAMETER Code
    The multiline Power Query M code or TMDL code to lint. This parameter is mandatory.

.PARAMETER SubscriptionKey
    The subscription key for API authorization. This parameter is mandatory.

.PARAMETER Rules
    Optional array of rule IDs to apply. If not specified, all applicable rules will be used.

.PARAMETER Severity
    Optional minimum severity level to include in results. 
    For example: "3" for potential issues, "2" for best practices.

.PARAMETER Format
    Optional format type. Either "pq" for Power Query M code or "tmdl" for TMDL code.
    If not specified, defaults to "pq".

.PARAMETER VerboseOutput
    Optional boolean to enable verbose output from the PQLint API where all the rules are returned even if they are not violated.
    If not specified, defaults to false.

.EXAMPLE
    Invoke-CodeLinting -Code $myCode -SubscriptionKey "your-key-here"
    
    Lints the provided code using default settings.

.EXAMPLE
    Invoke-CodeLinting -Code $myCode -SubscriptionKey "your-key-here" -Format "tmdl" -Severity "2"
    
    Lints TMDL code with minimum severity level of 2 (best practices).

.EXAMPLE
    Invoke-CodeLinting -Code $myCode -SubscriptionKey "your-key-here" -VerboseOutput $true
    
    Lints code with verbose API output enabled.

.EXAMPLE
    $rules = @("rule1", "rule2")
    Invoke-CodeLinting -Code $myCode -SubscriptionKey "your-key-here" -Rules $rules
    
    Lints code using only the specified rules.

.OUTPUTS
    Array of PSCustomObject representing rule results with properties:
    - ID: Rule identifier
    - Name: Rule name
    - Category: Rule category
    - Description: Rule description
    - Severity: Rule severity level
    - ErrorInformation: Object containing error location and file path details
#>
function Invoke-CodeLinting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Code,
        
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionKey,
        
        [Parameter(Mandatory = $false)]
        [string[]]$Rules,
        
        [Parameter(Mandatory = $false)]
        [string]$Severity,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("pq", "tmdl")]
        [string]$Format = "pq",
        
        [Parameter(Mandatory = $false)]
        [bool]$VerboseOutput = $false
    )
    
    Write-Verbose "Linting code using PQLint API with format: $Format"
    
    if ([string]::IsNullOrWhiteSpace($Code)) {
        throw "Code parameter cannot be null or empty"
    }
    
    if ([string]::IsNullOrWhiteSpace($SubscriptionKey)) {
        throw "SubscriptionKey parameter cannot be null or empty"
    }
    
    # Build the request body
    $requestBody = @{
        code = $Code
    }
    
    # Add optional parameters
    if ($Rules -and $Rules.Count -gt 0) {
        $requestBody.rules = $Rules
    }
    
    $options = @{}
    if (![string]::IsNullOrWhiteSpace($Severity)) {
        $options.severity = $Severity
    }
    if (![string]::IsNullOrWhiteSpace($Format)) {
        $options.format = $Format
    }
    if ($VerboseOutput) {
        $options.verbose = $VerboseOutput
    }
    
    if ($options.Count -gt 0) {
        $requestBody.options = $options
    }
    
    # Build the URI with subscription key
    $uri = "$script:ApiBaseUrl/pq/lint?subscription-key=$(Get-UrlEncodedString -InputString $SubscriptionKey)"
    try {
        $results = Invoke-PQLintApiRequest -Uri $uri -Method 'POST' -Body $requestBody -Verbose
        
        Write-Verbose "Successfully completed linting. Found $($results.Count) issues."
        return $results
    }
    catch {
        Write-Error "Failed to lint code: $($_.Exception.Message)"
        throw
    }
}

# Export module functions
Export-ModuleMember -Function Get-LintingRules, Invoke-CodeLinting
