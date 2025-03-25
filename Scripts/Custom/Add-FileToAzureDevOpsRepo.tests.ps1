Describe "Add-FileToAzureDevOpsRepo.psm1" {
    BeforeAll {
        Uninstall-Module -Name Add-FileTOAzureDevOpsRepo.psm1 -Force -ErrorAction SilentlyContinue
        Import-Module ".\Scripts\Custom\Add-FileTOAzureDevOpsRepo.psm1" -Force

        $params = Get-Content -Raw -Path ".\Scripts\Custom\parameters.json" | ConvertFrom-Json
    }
    Context "When Public AzureDevOps" {

        It "Should return an object of type PSCustomObject" {
            $result = Add-FileToAzureDevOpsRepo -BaseUrl $params.AzureDevOps.BaseUrl `
            -ProjectName $params.AzureDevOps.ProjectName `
            -RepositoryName $params.AzureDevOps.RepositoryName `
            -BranchName $params.AzureDevOps.BranchName `
            -AccessToken $params.AzureDevOps.AccessToken `
            -Path $params.AzureDevOps.FilePath `
            -Content $params.AzureDevOps.FileContent `
            -CommitMessage $params.AzureDevOps.CommitMessage

            # Validate the properties of the returned object
            $result | Should -BeOfType 'PSCustomObject'            

        }        
    }
}