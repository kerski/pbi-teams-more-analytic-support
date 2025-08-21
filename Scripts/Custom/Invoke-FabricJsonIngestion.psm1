# Microsoft Fabric JSON Ingestion PowerShell Module
# Cross-platform compatible (Windows/Linux)
# Requires PowerShell 5.1 or later

# Platform detection helper
function Get-PlatformInfo {
    [CmdletBinding()]
    param()
    
    $platform = @{
        IsWindows = $false
        IsLinux = $false
        IsMacOS = $false
        IsCore = $false
    }
    
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        # PowerShell 6+ has built-in platform detection
        $platform.IsCore = $true
        $platform.IsWindows = $IsWindows
        $platform.IsLinux = $IsLinux
        $platform.IsMacOS = $IsMacOS
    } else {
        # PowerShell 5.1 on Windows
        $platform.IsWindows = $true
    }
    
    return $platform
}

<#
.SYNOPSIS
    Creates a Kusto table in Microsoft Fabric with schema inferred from a JSON file.

.DESCRIPTION
    This function checks if a specified table exists in the Kusto database. If the table
    doesn't exist, it creates it by inferring the schema from the first record in the
    provided JSON file. The function handles Azure AD authentication and provides
    detailed logging for troubleshooting. Cross-platform compatible (Windows/Linux).

.PARAMETER ClusterUrl
    The URL of the Kusto cluster (e.g., "https://help.kusto.windows.net")

.PARAMETER Database
    The name of the Kusto database

.PARAMETER TableName
    The name of the table to create or verify

.PARAMETER JsonFilePath
    Path to the JSON file used for schema inference (cross-platform path format)

.PARAMETER TenantId
    Azure AD tenant ID for authentication

.PARAMETER ClientId
    Azure AD application (client) ID for authentication

.PARAMETER ClientSecret
    Azure AD application client secret for authentication

.EXAMPLE
    Invoke-FabricTableCreation -ClusterUrl "https://help.kusto.windows.net" -Database "TestDB" -TableName "MyTable" -JsonFilePath "/data/sample.json" -TenantId "tenant-id" -ClientId "client-id" -ClientSecret "secret"
    
.EXAMPLE
    Invoke-FabricTableCreation -ClusterUrl "https://help.kusto.windows.net" -Database "TestDB" -TableName "MyTable" -JsonFilePath "C:\data\sample.json" -TenantId "tenant-id" -ClientId "client-id" -ClientSecret "secret"
#>
function Invoke-FabricTableCreation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ClusterUrl,

        [Parameter(Mandatory)]
        [string]$Database,

        [Parameter(Mandatory)]
        [string]$TableName,

        [Parameter(Mandatory)]
        [ValidateScript({ 
            $resolvedPath = if ([System.IO.Path]::IsPathRooted($_)) { $_ } else { Join-Path -Path (Get-Location) -ChildPath $_ }
            if (Test-Path $resolvedPath -PathType Leaf) { 
                return $true 
            } else { 
                throw "File not found: $resolvedPath" 
            }
        })]
        [string]$JsonFilePath,

        [Parameter(Mandatory)]
        [string]$TenantId,

        [Parameter(Mandatory)]
        [string]$ClientId,

        [Parameter(Mandatory)]
        [string]$ClientSecret
    )

    try {
        # Resolve path to absolute path for cross-platform compatibility
        $resolvedJsonPath = if ([System.IO.Path]::IsPathRooted($JsonFilePath)) { 
            $JsonFilePath 
        } else { 
            Join-Path -Path (Get-Location) -ChildPath $JsonFilePath 
        }
        
        Write-Verbose "##[debug]Starting Fabric JSON ingestion via Kusto REST API..."
        Write-Verbose "##[debug]Cluster: $ClusterUrl"
        Write-Verbose "##[debug]Database: $Database"
        Write-Verbose "##[debug]Table: $TableName"
        Write-Verbose "##[debug]JSON File: $resolvedJsonPath"
        Write-Verbose "##[debug]Platform: $($PSVersionTable.Platform)"

        # --- Get Azure AD access token ---
        Write-Verbose "##[debug]Obtaining Azure AD access token..."
        $tokenBody = @{
            grant_type    = "client_credentials"
            client_id     = $ClientId
            client_secret = $ClientSecret
            scope         = "https://kusto.kusto.windows.net/.default"
        }

        $tokenResponse = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
            -Method POST `
            -Body $tokenBody `
            -ContentType "application/x-www-form-urlencoded"

        $accessToken = $tokenResponse.access_token
        $headers = @{
            "Authorization" = "Bearer $accessToken"
            "Content-Type"  = "application/json"
            "Accept"        = "application/json"
        }

        # --- Check if table exists ---
        Write-Verbose "##[debug]Checking if table '$TableName' exists..."
        $checkQuery = ".show tables | where TableName == '$TableName'"
        $queryBody = @{
            db  = $Database
            csl = $checkQuery
        } | ConvertTo-Json

        # Create ingest URL by adding "ingest-" prefix to the cluster hostname
        $ingestClusterUrl = $ClusterUrl -replace "https://", "https://ingest-"
        $queryUrl = "$ClusterUrl/v1/rest/query"
        $mgmtUrl = "$ClusterUrl/v1/rest/mgmt"
        $checkResponse = Invoke-RestMethod -Uri $queryUrl -Method POST -Headers $headers -Body $queryBody -Verbose

        $tableExists = $checkResponse.Tables[0].Rows.Count -gt 0
        Write-Verbose "##[debug]Table exists: $tableExists"

        if (-not $tableExists) {
            Write-Verbose "##[debug]Table '$TableName' does not exist. Creating it with inferred schema..."
            Write-Verbose "##[debug]Loading JSON from file for schema inference: $resolvedJsonPath"
            $jsonSample = Get-Content $resolvedJsonPath -Raw | ConvertFrom-Json
            $firstRecord = if ($jsonSample -is [array]) { $jsonSample[0] } else { $jsonSample }

            $columns = @()

            foreach ($prop in $firstRecord.PSObject.Properties) {
                $name = $prop.Name
                $value = $prop.Value

                if ($null -eq $value) {
                    $type = "string"
                }
                elseif ($value -is [array] -or $value -is [PSCustomObject]) {
                    # Arrays and nested objects should be stored as dynamic
                    $type = "dynamic"
                    Write-Verbose "##[debug]Property '$name' is array/object - will be stored as dynamic"
                }
                elseif ($value -is [int] -or $value -is [long]) {
                    $type = "long"
                }
                elseif ($value -is [double] -or $value -is [float]) {
                    $type = "real"
                }
                elseif ($value -is [DateTime]) {
                    $type = "datetime"
                }
                elseif ($value -is [bool]) {
                    $type = "bool"
                }
                else {
                    $type = "string"
                }

                Write-Verbose "##[debug]Inferred column: $name as $type"
                $columns += "${name}:${type}"
            }

            $schema = ($columns -join ", ")
            Write-Verbose "##[debug]Final inferred schema: $schema"

            $createQuery = ".create table $TableName ($schema)"
            $createBody = @{
                db  = $Database
                csl = $createQuery
            } | ConvertTo-Json

            Write-Verbose "##[debug]Executing table creation via REST API..."
            $createResponse = Invoke-RestMethod -Uri $mgmtUrl -Method POST -Headers $headers -Body $createBody
            Write-Verbose "##[debug]Table creation response: $($createResponse | ConvertTo-Json -Depth 3)"
            Write-Verbose "##[debug]✅ Table '$TableName' created with schema."
        }

        return $true
        
    }
    catch {
        Write-Verbose "##[error]❌ Failed to ingest JSON data: $($_.Exception.Message)"
        
        # Enhanced error handling for 400 errors with cross-platform support
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 400) {
            Write-Verbose "##[debug]HTTP 400 Bad Request detected in outer catch - providing detailed error information:"
            Write-Verbose "##[debug]Status Code: $($_.Exception.Response.StatusCode)"
            Write-Verbose "##[debug]Status Description: $($_.Exception.Response.StatusDescription)"
        }
        
        if ($_.ErrorDetails) {
            Write-Verbose "##[debug]API Error Response: $($_.ErrorDetails.Message)"
        }
        elseif ($_.Exception.Response) {
            try {
                # Cross-platform compatible response reading
                if ($PSVersionTable.PSVersion.Major -ge 6) {
                    # PowerShell Core
                    $responseContent = $_.Exception.Response.Content.ReadAsStringAsync().Result
                } else {
                    # Windows PowerShell 5.1
                    $responseStream = $_.Exception.Response.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader($responseStream)
                    $responseContent = $reader.ReadToEnd()
                    $reader.Close()
                }
                Write-Verbose "##[debug]API Error Response: $responseContent"
            }
            catch {
                Write-Verbose "##[debug]Could not read error response content: $($_.Exception.Message)"
            }
        }
        Write-Verbose "##[debug]Full error details: $($_.Exception | Out-String)"
        return $false
    }
}

<#
.SYNOPSIS
    Ingests JSON records into a Kusto table via Microsoft Fabric REST API.

.DESCRIPTION
    This function reads JSON data from a file and ingests each record individually
    into the specified Kusto table using the Fabric REST API. It handles Azure AD
    authentication, processes records one by one, and returns the count of successfully
    ingested records. The function throws an exception if ingestion fails.
    Cross-platform compatible (Windows/Linux).

.PARAMETER ClusterUrl
    The URL of the Kusto cluster (e.g., "https://help.kusto.windows.net")

.PARAMETER Database
    The name of the Kusto database

.PARAMETER TableName
    The name of the target table for ingestion

.PARAMETER JsonFilePath
    Path to the JSON file containing records to ingest (cross-platform path format)

.PARAMETER ClientId
    Azure AD application (client) ID for authentication

.PARAMETER ClientSecret
    Azure AD application client secret for authentication

.PARAMETER TenantId
    Azure AD tenant ID for authentication

.EXAMPLE
    $count = Invoke-KustoJsonIngest -ClusterUrl "https://help.kusto.windows.net" -Database "TestDB" -TableName "MyTable" -JsonFilePath "/data/records.json" -ClientId "client-id" -ClientSecret "secret" -TenantId "tenant-id"

.EXAMPLE
    $count = Invoke-KustoJsonIngest -ClusterUrl "https://help.kusto.windows.net" -Database "TestDB" -TableName "MyTable" -JsonFilePath "C:\data\records.json" -ClientId "client-id" -ClientSecret "secret" -TenantId "tenant-id"

.NOTES
    This function processes records individually, which may be slower for large datasets
    but provides better error handling and progress tracking. Compatible with both
    Windows PowerShell 5.1 and PowerShell 6+ on Windows/Linux.
#>
function Invoke-KustoJsonIngest {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string] $ClusterUrl,
        [Parameter(Mandatory)] [string] $Database,
        [Parameter(Mandatory)] [string] $TableName,
        [Parameter(Mandatory)] 
        [ValidateScript({ 
            $resolvedPath = if ([System.IO.Path]::IsPathRooted($_)) { $_ } else { Join-Path -Path (Get-Location) -ChildPath $_ }
            if (Test-Path $resolvedPath -PathType Leaf) { 
                return $true 
            } else { 
                throw "File not found: $resolvedPath" 
            }
        })] 
        [string] $JsonFilePath,
        [Parameter(Mandatory)] [string] $ClientId,
        [Parameter(Mandatory)] [string] $ClientSecret,
        [Parameter(Mandatory)] [string] $TenantId
    )

    # Resolve path to absolute path for cross-platform compatibility
    $resolvedJsonPath = if ([System.IO.Path]::IsPathRooted($JsonFilePath)) { 
        $JsonFilePath 
    } else { 
        Join-Path -Path (Get-Location) -ChildPath $JsonFilePath 
    }
    
    Write-Verbose "##[debug]Starting Kusto JSON ingestion via REST API..."
    Write-Verbose "##[debug]Resolved JSON file path: $resolvedJsonPath"
    Write-Verbose "##[debug]Platform: $($PSVersionTable.Platform)"
    # Acquire Azure AD token
    $tokenBody = @{ grant_type = 'client_credentials'; client_id = $ClientId; client_secret = $ClientSecret; scope = 'https://kusto.kusto.windows.net/.default' }
    $tokenResponse = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Method POST -Body $tokenBody -ContentType 'application/x-www-form-urlencoded'
    $accessToken = $tokenResponse.access_token
    $headers = @{ Authorization = "Bearer $accessToken"; 'Content-Type' = 'application/json'; Accept = 'application/json' }

    # Build ingest URL
    $ingestUrl = "$($ClusterUrl)/v1/rest/ingest/$($Database)/$($TableName)?streamFormat=multijson"
    Write-Verbose "##[debug]Ingest URL: $ingestUrl"
    # Read JSON payload
    $jsonContent = Get-Content -Path $resolvedJsonPath -Raw | ConvertFrom-Json
    # Build the payload
    $count = 0
    $payload = $null
    foreach ($line in $jsonContent) {
        $payload += ($line | ConvertTo-Json -Depth 4 -Compress) + "`n"
        $count++ # increment count for each successful ingestion
    }

    try {
        Write-Verbose "##[debug]Ingest REST body prepared: $payload"
        $response = Invoke-RestMethod -Uri $ingestUrl -Method POST -Headers $headers -Body $payload -Verbose
        # Log the full response via verbose
        Write-Verbose "##[debug]Ingest REST response: $($response | ConvertTo-Json -Depth 4)"

    }
    catch {
        Write-Error "##[error]❌ Ingestion REST failed: $($_.Exception.Message)"
        try {
            # Cross-platform compatible response reading
            if ($PSVersionTable.PSVersion.Major -ge 6) {
                # PowerShell Core
                $responseContent = $_.Exception.Response.Content.ReadAsStringAsync().Result
                Write-Verbose "##[debug]API Error Response: $responseContent"
            } else {
                # Windows PowerShell 5.1
                $responseStream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($responseStream)
                $responseContent = $reader.ReadToEnd()
                $reader.Close()
                Write-Verbose "##[debug]API Error Response: $responseContent"
            }
            
        }
        catch {
            Write-Verbose "##[debug]Could not read error response content: $($_.Exception.Message)"
        }
        # Failure logged via verbose
        throw "❌ Ingestion REST failed: $($_.Exception.Message)"
    }

    return $count
}

Export-ModuleMember -Function Invoke-FabricTableCreation, Invoke-KustoJsonIngest


