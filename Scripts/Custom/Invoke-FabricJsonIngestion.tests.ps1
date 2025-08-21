Describe "Invoke-FabricJsonIngestion.ps1" {
    BeforeAll {
        # Import the module using relative path from script location
        $ModulePath = Join-Path $PSScriptRoot "Invoke-FabricJsonIngestion.psm1"
        if (-not (Test-Path $ModulePath)) {
            throw "Module file not found at: $ModulePath"
        }
        Import-Module $ModulePath -Force

        # Load parameters from a JSON file
        $ParamsPath = Join-Path $PSScriptRoot "parameters.json"
        if (-not (Test-Path $ParamsPath)) {
            throw "Parameters file not found at: $ParamsPath"
        }
        $params = Get-Content -Raw -Path $ParamsPath | ConvertFrom-Json      

        # Validate that required Fabric parameters exist
        if (-not $params.Fabric) {
            throw "Fabric configuration section not found in parameters.json"
        }
    }

    Context "When invoking Invoke-FabricTableCreation" {
        It "Should return True on successful creation" {
            $result = Invoke-FabricTableCreation -ClusterUrl $params.Fabric.ClusterUrl `
                -Database $params.Fabric.Database `
                -TableName $params.Fabric.TableName `
                -JsonFilePath $params.Fabric.JsonFilePath `
                -TenantId $params.Fabric.TenantId `
                -ClientId $params.Fabric.ClientId `
                -ClientSecret $params.Fabric.ClientSecret -Verbose

            # Validate the result is True
            $result | Should -Be $True

            # Should be idempotent, so running again should not fail
            $result = Invoke-FabricTableCreation -ClusterUrl $params.Fabric.ClusterUrl `
                -Database $params.Fabric.Database `
                -TableName $params.Fabric.TableName `
                -JsonFilePath $params.Fabric.JsonFilePath `
                -TenantId $params.Fabric.TenantId `
                -ClientId $params.Fabric.ClientId `
                -ClientSecret $params.Fabric.ClientSecret -Verbose

            # Validate the result is True
            $result | Should -Be $True            
        }

        It "Should handle ingestion gracefully" {
            $result = Invoke-KustoJsonIngest -ClusterUrl $params.Fabric.ClusterUrl  `
                -Database $params.Fabric.Database `
                -TableName $params.Fabric.TableName `
                -JsonFilePath $params.Fabric.JsonFilePath `
                -TenantId $params.Fabric.TenantId `
                -ClientId $params.Fabric.ClientId `
                -ClientSecret $params.Fabric.ClientSecret -Verbose

            $result | Should -Be 2
        }
        
        It "Should throw on invalid Database" {
            { Invoke-KustoJsonIngest -ClusterUrl $params.Fabric.ClusterUrl `
                    -Database "InvalidDatabase" `
                    -TableName $params.Fabric.TableName `
                    -JsonFilePath $params.Fabric.JsonFilePath `
                    -TenantId $params.Fabric.TenantId `
                    -ClientId $params.Fabric.ClientId `
                    -ClientSecret $params.Fabric.ClientSecret -Verbose } | Should -Throw
        }
        It "Should handle invalid TableName gracefully" {
            { Invoke-FabricJsonIngestion -ClusterUrl $params.Fabric.ClusterUrl `
                    -Database $params.Fabric.Database `
                    -TableName "InvalidTable" `
                    -JsonFilePath $params.Fabric.JsonFilePath `
                    -TenantId $params.Fabric.TenantId `
                    -ClientId $params.Fabric.ClientId `
                    -ClientSecret $params.Fabric.ClientSecret } | Should -Throw

        }

        It "Should handle invalid JsonFilePath gracefully" {
            { $result = Invoke-FabricJsonIngestion -ClusterUrl $params.Fabric.ClusterUrl `
                    -Database $params.Fabric.Database `
                    -TableName $params.Fabric.TableName `
                    -JsonFilePath "C:\invalid\path\nonexistent.json" `
                    -TenantId $params.Fabric.TenantId `
                    -ClientId $params.Fabric.ClientId `
                    -ClientSecret $params.Fabric.ClientSecret } | Should -Throw

        }

        It "Should handle invalid TenantId gracefully" {
            { $result = Invoke-FabricJsonIngestion -ClusterUrl $params.Fabric.ClusterUrl `
                    -Database $params.Fabric.Database `
                    -TableName $params.Fabric.TableName `
                    -JsonFilePath $params.Fabric.JsonFilePath `
                    -TenantId "invalid-tenant-id" `
                    -ClientId $params.Fabric.ClientId `
                    -ClientSecret $params.Fabric.ClientSecret } | Should -Throw

        }

        It "Should handle invalid ClientId gracefully" {
            { $result = Invoke-FabricJsonIngestion -ClusterUrl $params.Fabric.ClusterUrl `
                    -Database $params.Fabric.Database `
                    -TableName $params.Fabric.TableName `
                    -JsonFilePath $params.Fabric.JsonFilePath `
                    -TenantId $params.Fabric.TenantId `
                    -ClientId "invalid-client-id" `
                    -ClientSecret $params.Fabric.ClientSecret } | Should -Throw

        }

        It "Should handle invalid ClientSecret gracefully" {
            { Invoke-FabricJsonIngestion -ClusterUrl $params.Fabric.ClusterUrl `
                    -Database $params.Fabric.Database `
                    -TableName $params.Fabric.TableName `
                    -JsonFilePath $params.Fabric.JsonFilePath `
                    -TenantId $params.Fabric.TenantId `
                    -ClientId $params.Fabric.ClientId `
                    -ClientSecret "invalid-secret" } | Should -Throw

          
        }
    }
}
