# Function to add a file to SharePoint using App-Only Authentication
Function Add-FileToSharePoint {
    <#
    .SYNOPSIS
    Adds a file to a SharePoint document library using App-Only Authentication.

    .DESCRIPTION
    This function uploads a specified file to a SharePoint document library. It uses App-Only Authentication with a certificate to connect to SharePoint.

    .PARAMETER FilePath
    The path to the file that needs to be uploaded to SharePoint.

    .PARAMETER SiteUrl
    The URL of the SharePoint site.

    .PARAMETER DocLibPath
    The path to the document library in SharePoint where the file will be uploaded.

    .PARAMETER TenantId
    The tenant ID of the Azure AD tenant.

    .PARAMETER ClientId
    The client ID of the Azure AD application.

    .PARAMETER Base64Cert
    The base64-encoded certificate used for authentication.

    .PARAMETER CertPassword
    The password for the certificate.

    .PARAMETER CheckInComment
    The comment to include when checking in the file.

    .EXAMPLE
    Add-FileToSharePoint -FilePath "C:\Reports\report.pdf" -SiteUrl "https://contoso.sharepoint.com/sites/reports" `
                         -DocLibPath "Shared Documents/Reports" -TenantId "your-tenant-id" -ClientId "your-client-id" `
                         -Base64Cert "base64-encoded-cert" -CertPassword (ConvertTo-SecureString -String "password" -AsPlainText -Force) `
                         -CheckInComment "Uploaded report.pdf"

    .NOTES
    This function requires the PnP.PowerShell module.
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Position = 0, Mandatory = $true)][String]$FilePath,
        [Parameter(Position = 1, Mandatory = $true)][String]$SiteUrl,
        [Parameter(Position = 2, Mandatory = $true)][String]$DocLibPath,
        [Parameter(Position = 3, Mandatory = $true)][String]$TenantId,
        [Parameter(Position = 4, Mandatory = $true)][String]$ClientId,
        [Parameter(Position = 5, Mandatory = $true)][String]$Base64Cert,
        [Parameter(Position = 6, Mandatory = $true)][SecureString]$CertPassword,
        [Parameter(Position = 7, Mandatory = $true)][String]$CheckInComment
    )
    Process {
        Try {
            # Install PowerShell Module if Needed
            if (Get-Module -ListAvailable -Name "PnP.PowerShell") {
                Write-Host "PnP.PowerShell already installed"
            } else {
                Install-Module -Name PnP.PowerShell -Scope CurrentUser -AllowClobber -Force
            }

            Connect-PnPOnline $SiteUrl -ClientId $ClientId `
                                        -Tenant $TenantId `
                                        -CertificateBase64Encoded $Base64Cert `
                                        -CertificatePassword $CertPassword -Verbose

            $resolvedFilePath = Resolve-Path -Path $FilePath -ErrorAction Stop

            # Add file to SharePoint
            Add-PnPFile -Path $resolvedFilePath -Folder $DocLibPath -Checkout -CheckInComment $CheckInComment -Verbose

            Return $True
        } Catch {
            Write-Host $_
            Write-Host "##vso[task.logissue type=error]Unable to upload file to SharePoint."
            Return $False
        } # End Try
    } # End Process
} # End Function

Export-ModuleMember -Function Add-FileToSharePoint