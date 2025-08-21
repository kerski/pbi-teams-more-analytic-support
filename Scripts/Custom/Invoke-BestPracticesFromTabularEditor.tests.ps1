Describe "Invoke-BestPracticesFromTabularEditor.psm1" {
    BeforeAll {
        Uninstall-Module -Name Invoke-BestPracticesFromTabularEditor.psm1 -Force -ErrorAction SilentlyContinue
        Import-Module ".\Scripts\Custom\Invoke-BestPracticesFromTabularEditor.psm1" -Force

        $params = Get-Content -Raw -Path ".\Scripts\Custom\parameters.json" | ConvertFrom-Json
        # Set up parameters for the tests
        $workspaceName = $params.Fabric.WorkspaceName
        $semanticModelName = $params.Fabric.SemanticModelName
        $tenantId = $params.Fabric.TenantId
        $environment = $params.Fabric.Environment
        $bpaFilePath = $params.BPAFilePath
        $tabularEditorPath = $params.TabularEditorPath
        $tMDLFilePath = $params.TMDLFilePath
        $spCredential = New-Object -TypeName PSCredential -ArgumentList $params.Fabric.ClientId, (ConvertTo-SecureString -String $params.Fabric.ClientSecret -AsPlainText -Force)        
    }

    AfterAll{
        if(Test-Path ".\Invoke-Pester-Tests\"){
            Remove-Item -Path ".\Invoke-Pester-Tests\*" -Force    
        }
    }

    Context "When using service principal" {

        It "Should return 0 when no errors occur" -Tag "Service" {

            # Get the current time in a specific format
            $currentTime = Get-Date -Format "yyyyMMdd_HHmmss"
            # Create the file name
            $fileName = ".\Invoke-Pester-Tests\Test.xml"
            Write-Host $fileName
            $result = Invoke-BestPracticesFromTabularEditor `
                -WorkspaceName $workspaceName `
                -SemanticModelName $semanticModelName `
                -Credential $spCredential `
                -TenantId $tenantId `
                -Environment $environment `
                -BPAFilePath $bpaFilePath `
                -OutputFilePath $fileName `
                -TabularEditorPath $tabularEditorPath
            $result | Should -Be 0
        }

        It "Should throw an error if TenantId is not provided" -Tag "Service" {
            # Get the current time in a specific format
            $currentTime = Get-Date -Format "yyyyMMdd_HHmmss"
            # Create the file name
            $fileName = ".\Invoke-Pester-Tests\Test_$($currentTime).xml"
            { 
                Invoke-BestPracticesFromTabularEditor `
                -WorkspaceName $workspaceName `
                -SemanticModelName $semanticModelName `
                -Credential $spCredential `
                -Environment $environment `
                -BPAFilePath $bpaFilePath `
                -OutputFilePath $fileName `
                -TabularEditorPath $tabularEditorPath } | Should -Throw "TenantId Parameter is required when ServicePrincipal is provided"
        }
    }

    Context "When using local mode" {

        It "Should return 0 when no errors occur" -Tag "Local" {
            # Create the file name
            $fileName = ".\Invoke-Pester-Tests\TestLocal.xml"

            $result = Invoke-BestPracticesFromTabularEditor `
                -InputFile $tMDLFilePath `
                -BPAFilePath $bpaFilePath `
                -OutputFilePath $fileName `
                -TabularEditorPath $tabularEditorPath -Verbose
            $result | Should -Be 0            
        }

        It "Should return 0 when no errors occur (absolute path)" -Tag "Local" {
            # Create the file name
            $fileName = ".\Invoke-Pester-Tests\TestLocalAbs.xml"

            $result = Invoke-BestPracticesFromTabularEditor `
                -InputFile $tMDLFilePath `
                -BPAFilePath $bpaFilePath `
                -OutputFilePath $fileName `
                -TabularEditorPath $tabularEditorPath
            $result | Should -Be 0            
        }        

        It "Should throw error if Input File not found" -Tag "Local" {
            {Invoke-BestPracticesFromTabularEditor `
                -InputFile "test.tmdl" `
                -BPAFilePath $bpaFilePath `
                -OutputFilePath $fileName `
                -TabularEditorPath $tabularEditorPath
             } | Should -Throw            
        }        
    }    
}