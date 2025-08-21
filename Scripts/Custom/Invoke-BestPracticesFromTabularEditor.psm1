<#
    Author: John Kerski

    .SYNOPSIS
    Installs and runs Best Practice Analyzer using Tabular Editor for a Power BI semantic model.

    .DESCRIPTION
    This script connects to a Power BI workspace, executes the Best Practice Analyzer (BPA) using Tabular Editor, 
    and saves the output to the specified file path. It supports both service principal and user-based authentication 
    and works across different Power BI environments such as Public, Germany, China, and USGov.

    .PARAMETER InputFile
    The file path to the model.bim, model.tmdl file, or folder containing the semantic model files for local analysis.

    .PARAMETER WorkspaceName
    The name of the Power BI workspace where the semantic model resides.

    .PARAMETER SemanticModelName
    The name of the semantic model for which Best Practice Analyzer will be run.

    .PARAMETER Credential
    PSCredential object containing the username and password or service principal credentials for authentication.

    .PARAMETER Environment
    The Power BI cloud environment (e.g., Public, Germany, China, USGov). Defaults to Public.

    .PARAMETER BPAFilePath
    The full file path to the Best Practice Analyzer (BPA) JSON file.

    .PARAMETER TabularEditorPath
    The full file path to the Tabular Editor executable.

    .PARAMETER OutputFilePath
    The full file path where the BPA output will be saved.

    .PARAMETER TenantId
    The Azure Active Directory tenant ID. This is required if using a service principal for authentication.

    .NOTES
    Ensure Tabular Editor is installed and accessible at the specified path. The script handles folder creation for 
    the output file if the specified directory does not exist.

    .EXAMPLE
    Invoke-BestPracticesFromTabularEditor -WorkspaceName "FinanceWorkspace" -SemanticModelName "SalesData" `
        -Credential (Get-Credential) -Environment "Public" -BPAFilePath "C:\BPA\Analyzer.json" `
        -TabularEditorPath "C:\TabularEditor\TabularEditor.exe" -OutputFilePath "C:\BPA\Results\Output.json"

    Runs the Best Practice Analyzer on the SalesData semantic model in the FinanceWorkspace using user credentials.

    .EXAMPLE
    Invoke-BestPracticesFromTabularEditor -InputFile "C:\Models\SalesModel.bim" `
        -BPAFilePath "C:\BPA\Analyzer.json" -TabularEditorPath "C:\TabularEditor\TabularEditor.exe" `
        -OutputFilePath "C:\BPA\Results\Output.json"

    Runs the Best Practice Analyzer on a local model.bim file.

    .EXAMPLE
    Invoke-BestPracticesFromTabularEditor -InputFile "C:\Models\SalesModel\" `
        -BPAFilePath "C:\BPA\Analyzer.json" -TabularEditorPath "C:\TabularEditor\TabularEditor.exe" `
        -OutputFilePath "C:\BPA\Results\Output.json"

    Runs the Best Practice Analyzer on a local semantic model folder containing TMDL files.
#>
Function Invoke-BestPracticesFromTabularEditor { 
    [CmdletBinding(DefaultParameterSetName='Default')]
    Param(         
        # The file path to the model.bim, model.tmdl file, or folder containing the semantic model files
        [Parameter(Mandatory = $true, ParameterSetName="Local")]
        [String]$InputFile,

        # The file path where the output will be saved
        [Parameter(Mandatory = $true, ParameterSetName="Local")]
        [Parameter(Mandatory = $true, ParameterSetName="Default")]
        [String]$OutputFilePath,        

        # The file path to the Tabular Editor executable
        [Parameter(Mandatory = $true, ParameterSetName="Local")]
        [Parameter(Mandatory = $true, ParameterSetName="Default")]
        [String]$TabularEditorPath, 

        # The file path to the Best Practice Analyzer (BPA) file
        [Parameter(Mandatory = $true, ParameterSetName="Local")]
        [Parameter(Mandatory = $true, ParameterSetName="Default")]
        [String]$BPAFilePath,        

        # The name of the Power BI workspace
        [Parameter(Mandatory = $true, ParameterSetName="Default")]
        [String]$WorkspaceName, 
        
        # The name of the semantic model
        [Parameter(Mandatory = $true, ParameterSetName="Default")]
        [String]$SemanticModelName,
        
        # The credentials to use for authentication
        [Parameter(Mandatory = $true, ParameterSetName="Default")]
        [PSCredential]$Credential,
        
        # The environment (e.g., Public, Germany, China, USGov, etc.)
        [Parameter(Mandatory = $true, ParameterSetName="Default")]
        [String]$Environment,
        
        # The tenant ID (required if using a service principal)
        [Parameter(Mandatory = $false, ParameterSetName="Default")]
        [String]$TenantId     
    ) 
    Process { 
        $result = 0
        # Check if service principal or username/password
        $guidRegex = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
        $isServicePrincipal = $false
        $bpaArg = ""
        $secureStringPtr = ""
        $plainTextPwd = ""
        # Enter parameter set name to validate input
        switch($PSCmdlet.ParameterSetName){
            'Default' {
                    if($Credential.UserName -match $guidRegex){# Service principal used
                        $isServicePrincipal = $true
                    }

                    # Check Tenant ID when Service Principal is used
                    if((-not $TenantId) -and $isServicePrincipal -eq $true){
                        throw "TenantId Parameter is required when ServicePrincipal is provided"
                    }  

                    # Map to correct API Prefix
                    $pbiEndpoint = "powerbi://api.powerbi.com/v1.0/myorg"
                    switch($Environment){
                        "Public" {$pbiEndpoint = "powerbi://api.powerbi.com/v1.0/myorg"}
                        "Germany" {$pbiEndpoint = "powerbi://api.powerbi.de/v1.0/myorg"}
                        "China" {$pbiEndpoint = "powerbi://api.powerbi.cn/v1.0/myorg"}
                        "USGov" {$pbiEndpoint = "powerbi://api.powerbigov.us/v1.0/myorg"}
                        "USGovHigh" {$pbiEndpoint = "powerbi://api.high.powerbigov.us/v1.0/myorg"}
                        "USGovDoD" {$pbiEndpoint = "powerbi://api.mil.powerbi.us/v1.0/myorg"}
                        Default {$pbiEndpoint = "powerbi://api.powerbi.com/v1.0/myorg"}
                    }   
                    
                    # Convert secure string to plain text to use in connection strings
                    $secureStringPtr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Credential.Password)
                    $plainTextPwd = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($secureStringPtr)                    
            }
            'Local' {
                if (-not (Test-Path -LiteralPath $InputFile -PathType Leaf)) {
                    Throw "$($InputFile) not found for analysis"
                }
            }
        }# end parametersetname check     

        Try {
            # Install Tabular Editor if Needed
            if (-not (Test-Path $TabularEditorPath -PathType Leaf)) {
                Throw "Please include TabularEditor in your project"
            }     
            
            # Setup Arguments
            if($PSCmdlet.ParameterSetName -eq "Local"){
                # Get absolute path to reference
                $absFilePath = Resolve-Path -LiteralPath $InputFile
                $bpaArg = "`"$($absFilePath)`" -A """"$($BPAFilePath)"""" -T """"$($OutputFilePath)"""""
            }
            elseif($isServicePrincipal){
                $bpaArg = "`"Provider=MSOLAP;Data Source=$($pbiEndpoint)/$($WorkspaceName);User ID=app:$($Credential.UserName)@$($TenantId);Password=$($plainTextPwd);Integrated Security=ClaimsToken;`" `"$($SemanticModelName)`" -A """"$($BPAFilePath)"""" -T """"$($OutputFilePath)"""""
            }
            else{
                $bpaArg = "`"Provider=MSOLAP;Data Source=$($pbiEndpoint)/$($WorkspaceName);User ID=$($Credential.UserName);Password=$($plainTextPwd);Integrated Security=ClaimsToken;`" `"$($SemanticModelName)`" -A """"$($BPAFilePath)"""" -T """"$($OutputFilePath)"""""
            }# end check of service principal

            # Check and create folders if necessary
            $outputDirectory = [System.IO.Path]::GetDirectoryName($OutputFilePath)
            if (-not (Test-Path $outputDirectory)) {
                New-Item -Path $outputDirectory -ItemType Directory | Out-Null
            }
            Write-Verbose "Running Best Practices Analyzer with arguments: $bpaArg"
            Start-Process -FilePath $TabularEditorPath -Wait -NoNewWindow -PassThru -ArgumentList "$($bpaArg)"
        }Catch{
            Write-Host "##vso[task.logissue type=error]Unable to check best practices. Exception: $_"
            $result = -1
        }#End Try

        return $result
    }#End Process
}#End Function

Export-ModuleMember -Function Invoke-BestPracticesFromTabularEditor