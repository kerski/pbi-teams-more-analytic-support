    <#
    .SYNOPSIS
    A helper function to retry HTTP requests upon failure.
   
    .PARAMETER Uri
    The request URL.

    .PARAMETER Method
    The HTTP method (GET, POST, etc.).

    .PARAMETER Headers
    The HTTP headers including authorization.

    .PARAMETER Body
    The request body (optional).

    .PARAMETER ContentType
    The content type of the request.

    .PARAMETER MaxRetries
    The maximum number of retry attempts.

    .PARAMETER RetryDelay
    The delay (in seconds) between retries.
    #>
    function Invoke-WithRetry {
        param (
            [Parameter(Mandatory = $true)]
            [string]$Uri,
            [Parameter(Mandatory = $true)]
            [string]$Method,
            [Parameter(Mandatory = $true)]
            [hashtable]$Headers,
            [string]$Body,
            [string]$ContentType = "application/json",
            [int]$MaxRetries = 1,
            [int]$RetryDelay = 15
        )
        $attempt = 0
        while ($attempt -lt $MaxRetries) {
            try {
                if ($Body) {
                    return Invoke-RestMethod -Uri $Uri -Method $Method -Headers $Headers -Body $Body -ContentType $ContentType
                } else {
                    return Invoke-RestMethod -Uri $Uri -Method $Method -Headers $Headers -ContentType $ContentType
                }
            } catch {
                $attempt++
                if ($attempt -ge $MaxRetries) {
                    throw "Request failed after $MaxRetries attempts: $_"
                }
                Write-Host "Request failed. Retrying in $RetryDelay seconds... ($attempt/$MaxRetries)"
                Start-Sleep -Seconds $RetryDelay
            }
        }
    }
    
    <#
    .SYNOPSIS
    Commits a file to an Azure DevOps Repository's branch.
    
    .PARAMETER ADOAPIHost
    The host for the Azure DevOps Instance (e.g., https://dev.azure.com)
    
    .PARAMETER OwnerName
    The name of the GitHub repository owner.
    
    .PARAMETER RepositoryName
    The name of the GitHub repository.
    
    .PARAMETER AccessToken
    The access token to authenticate with the Azure DevOps API.
    
    .PARAMETER BranchName
    The name of the branch to commit the file to.
    
    .PARAMETER Path
    The file path of the file to commit.
    
    .PARAMETER Content
    The content to write to the file.
    
    .PARAMETER CommitMessage
    The commit message to use when committing the file.
    
    .EXAMPLE
        Add-FileToAzureDevOpsRepo -ADOAPIHost "https://dev.azure.com" `
            -OrganizationName "OrgName" `
            -ProjectName "ProjectX" `
            -RepositoryName "Adamantium" `
            -AccessToken "{Personal Access Token}" `
            -BranchName "development" `
            -Path "/Canada/testfile.txt" `
            -Content "This is a sample" `
            -CommitMessage "Updating test file..."
    #>
    function Add-FileToAzureDevOpsRepo {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$BaseUrl,
            [Parameter(Mandatory = $true)]
            [string]$ProjectName,
            [Parameter(Mandatory = $true)]
            [string]$RepositoryName,
            [Parameter(Mandatory = $true)]
            [string]$AccessToken,
            [Parameter(Mandatory = $true)]
            [string]$BranchName,
            [Parameter(Mandatory = $true)]
            [string]$Path,
            [Parameter(Mandatory = $true)]
            [string]$Content,
            [Parameter(Mandatory = $true)]
            [string]$CommitMessage
        )
        Write-Host "CommitMessage $($CommitMessage)"
    
        $uriOrga = "$($BaseUrl)"
        $aDOAuthenicationHeader = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($AccessToken)")) }
       
        $uriRepoID = "$($uriOrga)/$($ProjectName)/_apis/git/repositories/?api-version=5.1"
    
        $repoInfo = Invoke-WithRetry -Uri $uriRepoID -Method Get -Headers $aDOAuthenicationHeader
    
        if($repoInfo) {
           $aDORepo = $repoInfo.value | Where-Object { $_.name -eq $RepositoryName }
           
           if(!$aDORepo) {
                throw "Unable to get repository id for the repository name supplied $($RepositoryName)"
           }
    
           $aDORepoId = $aDORepo.id
    
           $uriRef = "$($uriOrga)$($ProjectName)/_apis/git/repositories/$($aDORepoId)/refs?api-version=7.0"
           $uriPush = "$($uriOrga)$($ProjectName)/_apis/git/repositories/$($aDORepoId)/pushes?api-version=7.0"
           
           $refResult = Invoke-WithRetry -Uri $uriRef -Method Get -Headers $aDOAuthenicationHeader
           $branchRef = $refResult.value | Where-Object { $_.name -eq "refs/heads/$($BranchName)" }
           
           if(!$branchRef) {
                throw "Unable to get referenced Id for repository: $($aDORepoId) and branch: $($BranchName)."
           }
           
           $addTemplate = @{ "refUpdates" = @( @{ "name" = "refs/heads/$($BranchName)"; "oldObjectId" = $branchRef.objectId } );
                             "commits" = @( @{ "comment" = "$($CommitMessage)"; "changes" = @( @{ "changeType" = "add"; "item" = @{ "path" = "$($Path)" };
                                                 "newContent" = @{ "content" = "$($Content)"; "contentType" = "rawtext" } } ) } ) }
    
           $editTemplate = @{ "refUpdates" = @( @{ "name" = "refs/heads/$($BranchName)"; "oldObjectId" = $branchRef.objectId } );
            "commits" = @( @{ "comment" = "$($CommitMessage)"; "changes" = @( @{ "changeType" = "edit"; "item" = @{ "path" = "$($Path)" };
                                "newContent" = @{ "content" = "$($Content)"; "contentType" = "rawtext" } } ) } ) }
           
           $jSONAddBody = $addTemplate | ConvertTo-Json -Depth 10
           $jSONEditBody = $editTemplate | ConvertTo-Json -Depth 10
           
           # Try adding first, then edit
           try{
                $returnValue = Invoke-WithRetry -Uri $uriPush -Method Post -Headers $aDOAuthenicationHeader -Body $jSONAddBody
           }catch{
                return Invoke-WithRetry -Uri $uriPush -Method Post -Headers $aDOAuthenicationHeader -Body $jSONEditBody
           }
        } else {
            throw "Unable to get repository information at $uriRepoID endpoint."
        }
    }
    
    # Export the cmdlet to make it available in the module
    Export-ModuleMember -Function Add-FileToAzureDevOpsRepo