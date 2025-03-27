Describe "Add-FileToSharePoint.ps1" {
    BeforeAll {
        # Uninstall the module if already installed
        Uninstall-Module -Name Add-FileToSharePoint -Force -ErrorAction SilentlyContinue
        # Import the module
        Import-Module ".\Scripts\Custom\Add-FileToSharePoint.psm1" -Force

        # Load parameters from a JSON file
        $params = Get-Content -Raw -Path ".\Scripts\Custom\parameters.json" | ConvertFrom-Json      

        # Convert the certificate password to a secure string
        $securePassword = ConvertTo-SecureString -String $params.SharePoint.CertPassword -Force -AsPlainText               
    }

    Context "When adding a file to SharePoint" {
        It "Should return True on successful upload" {
            $result = Add-FileToSharePoint -FilePath $params.SharePoint.FilePath `
                                          -SiteUrl $params.SharePoint.SiteUrl `
                                          -DocLibPath $params.SharePoint.DocLibPath `
                                          -TenantId $params.SharePoint.TenantId `
                                          -ClientId $params.SharePoint.ClientId `
                                          -Base64Cert $params.SharePoint.Base64Cert `
                                          -CertPassword $securePassword `
                                          -CheckInComment "Test"

            # Validate the result is True
            $result | Should -Be $True
        }

        It "Should handle errors gracefully" {
            # Simulate an error by providing an invalid parameters
            $result = Add-FileToSharePoint -FilePath "invalidPath" `
                                          -SiteUrl "$($params.SharePoint.SiteUrl)xyz" `
                                          -DocLibPath $params.SharePoint.DocLibPath `
                                          -TenantId 1234 `
                                          -ClientId $params.SharePoint.ClientId `
                                          -Base64Cert $params.SharePoint.Base64Cert `
                                          -CertPassword $securePassword `
                                          -CheckInComment "Test"

            # Validate the result is False
            $result | Should -Be $False
        }
    }
}