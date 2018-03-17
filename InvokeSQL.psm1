﻿function Invoke-SQL {
    param(
        [string]$dataSource = ".\SQLEXPRESS",
        [string]$database = "MasterData",
        [string]$sqlCommand = $(throw "Please specify a query."),
        $Credential = [System.Management.Automation.PSCredential]::Empty,
        [Switch]$ConvertFromDataRow
    )

    if ($Credential -ne [System.Management.Automation.PSCredential]::Empty) {
        $connectionString = "Server=$dataSource;Database=$database;User Id=$($Credential.UserName);Password=$($Credential.GetNetworkCredential().password);"
    } else {
        $connectionString = "Data Source=$dataSource; Integrated Security=SSPI; Initial Catalog=$database"
    }

    $connection = new-object system.data.SqlClient.SQLConnection($connectionString)
    $command = new-object system.data.sqlclient.sqlcommand($sqlCommand,$connection)
    $connection.Open()
    
    $adapter = New-Object System.Data.sqlclient.sqlDataAdapter $command
    $dataset = New-Object System.Data.DataSet
    $adapter.Fill($dataSet) | Out-Null
    
    $connection.Close()
    
    if ($ConvertFromDataRow) {
        $dataSet.Tables | ConvertFrom-DataRow
    } else {
        $dataSet.Tables
    }
}

function ConvertTo-MSSQLConnectionString {
    param (
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]$Server,
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]$Database,
        $Credential = [System.Management.Automation.PSCredential]::Empty
    )
    process {
        New-MSSQLConnectionString @PSBoundParameters
    }
}

function New-MSSQLConnectionString {
    param (
        [Parameter(Mandatory)]$Server,
        [Parameter(Mandatory)]$Database,
        $Credential = [System.Management.Automation.PSCredential]::Empty
    )
    if ($Credential -ne [System.Management.Automation.PSCredential]::Empty) {
        "Server=$Server;Database=$Database;User Id=$($Credential.UserName);Password=$($Credential.GetNetworkCredential().password);"
    } else {
        "Data Source=$Server; Integrated Security=SSPI; Initial Catalog=$Database"
    }
}


function Invoke-SQLODBC {
    param (
        [string]$DataSourceName,
        [string]$SQLCommand = $(throw "Please specify a query."),
        [Switch]$ConvertFromDataRow
    )
    $ConnectionString = "DSN=$DataSourceName"
    Invoke-SQLGeneric -ConnectionString $ConnectionString -SQLCommand $SQLCommand -DatabaseEngineClassMapName ODBC -ConvertFromDataRow:$ConvertFromDataRow
}

function ConvertFrom-DataRow {
    param(
        [Parameter(
            Position=0, 
            Mandatory=$true, 
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true
        )]
        $DataRow
    )
    process {
        $DataRowProperties = $DataRow | GM -MemberType Properties | select -ExpandProperty name
        $DataRowWithLimitedProperties = $DataRow | select $DataRowProperties
        $DataRowAsPSObject = $DataRowWithLimitedProperties | % { $_ | ConvertTo-Json | ConvertFrom-Json }
#        if($DataRowAsPSObject | GM | where membertype -NE "Method") {
#            $DataRowAsPSObject
#        }

        $DataRowAsPSObject
    }
}

function Invoke-MSSQL {
    param(
        [Parameter(Mandatory,ParameterSetName="NoConnectionString")]$Server,
        [Parameter(Mandatory,ParameterSetName="NoConnectionString")]$Database,
        [Parameter(ParameterSetName="NoConnectionString")]$Credential = [System.Management.Automation.PSCredential]::Empty,
        [Parameter(Mandatory,ParameterSetName="ConnectionString")][string]$ConnectionString,
        [Parameter(Mandatory)][string]$SQLCommand,
        [Switch]$ConvertFromDataRow
    )
    if (-not $ConnectionString) {
        $ConnectionString = New-MSSQLConnectionString -Server $Server -Database $Database -Credential $Credential
        Invoke-SQLGeneric -ConnectionString $ConnectionString -SQLCommand $SQLCommand -ConvertFromDataRow:$ConvertFromDataRow -DatabaseEngineClassMapName MSSQL
    } else {
        Invoke-SQLGeneric -DatabaseEngineClassMapName MSSQL @PSBoundParameters
    }
}

function Install-InvokeSQLAnywhereSQL {
    choco install sqlanywhereclient -version 12.0.1 -y
}

function ConvertTo-SQLAnywhereConnectionString {
    param(
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)][string]$Host,
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)][string]$DatabaseName,
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)][string]$ServerName,
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)][string]$UserName,
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)][string]$Password
    )
    "UID=$UserName;PWD=$Password;Host=$Host;DatabaseName=$DatabaseName;ServerName=$ServerName"
}

$DatabaseEngineClassMap = [PSCustomObject][Ordered]@{
    Name = "SQLAnywhere"
    NameSpace = "iAnywhere.Data.SQLAnywhere"
    Connection = "SAConnection"
    Command = "SACommand"
    Adapter = "SADataAdapter"
    AddTypeScriptBlock = {Add-iAnywhereDataSSQLAnywhereType}
},
[PSCustomObject][Ordered]@{
    Name = "Oracle"
    NameSpace = "Oracle.ManagedDataAccess.Client"
    Connection = "OracleConnection"
    Command = "OracleCommand"
    Adapter = "OracleDataAdapter"
    AddTypeScriptBlock = {Add-OracleManagedDataAccessType}
},
[PSCustomObject][Ordered]@{
    Name = "MSSQL"
    NameSpace = "system.data.sqlclient"
    Connection = "SQLConnection"
    Command = "SQLCommand"
    Adapter = "SQLDataAdapter"
},
[PSCustomObject][Ordered]@{
    Name = "ODBC"
    NameSpace = "System.Data.Odbc"
    Connection = "OdbcConnection"
    Command = "OdbcCommand"
    Adapter = "OdbcDataAdapter"
}


function Get-DatabaseEngineClassMap {
    param (
        $Name
    )
    $DatabaseEngineClassMap | where Name -EQ $Name
}

function Add-iAnywhereDataSSQLAnywhereType {
    Add-Type -AssemblyName "iAnywhere.Data.SQLAnywhere, Version=12.0.1.36052, Culture=neutral, PublicKeyToken=f222fc4333e0d400"
}

function Invoke-SQLGeneric {
    param(
        [Parameter(Mandatory)][string]$ConnectionString,
        [Parameter(Mandatory)][string]$SQLCommand,
        [Parameter(Mandatory)][ValidateSet("SQLAnywhere","Oracle","MSSQL","ODBC")]$DatabaseEngineClassMapName,
        [Switch]$ConvertFromDataRow
    )
    $ClassMap = Get-DatabaseEngineClassMap -Name $DatabaseEngineClassMapName
    $NameSpace = $ClassMap.NameSpace
    if ($ClassMap.AddTypeScriptBlock) { & $ClassMap.AddTypeScriptBlock }

    $Connection = New-Object -TypeName "$NameSpace.$($ClassMap.Connection)" $ConnectionString
    $Command = New-Object "$NameSpace.$($ClassMap.Command)" $SQLCommand,$Connection
    $Connection.Open()
    
    $Adapter = New-Object "$NameSpace.$($ClassMap.Adapter)" $Command
    $Dataset = New-Object System.Data.DataSet
    $Adapter.Fill($DataSet) | Out-Null
    
    $Connection.Close()
    
    if ($ConvertFromDataRow) {
        $DataSet.Tables | ConvertFrom-DataRow
    } else {
        $DataSet.Tables
    }
}

function Invoke-SQLAnywhereSQL {
    param(
        [Parameter(Mandatory)][string]$ConnectionString,
        [Parameter(Mandatory)][string]$SQLCommand,
        [ValidateSet("SQLAnywhere","Oracle","MSSQL")]$DatabaseEngineClassMapName = "SQLAnywhere",
        [Switch]$ConvertFromDataRow
    )
    Invoke-SQLGeneric @PSBoundParameters
}

function Install-InvokeOracleSQL {
    $ModulePath = (Get-Module -ListAvailable InvokeOracleSQL).ModuleBase
    Set-Location -Path $ModulePath

    $SourceNugetExe = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
    $TargetNugetExe = ".\nuget.exe"
    Invoke-WebRequest $sourceNugetExe -OutFile $targetNugetExe
    .\nuget.exe install Oracle.ManagedDataAccess
    Remove-Item -Path $TargetNugetExe
}

function Add-OracleManagedDataAccessType {
    $ModulePath = (Get-Module -ListAvailable InvokeOracleSQL).ModuleBase
    $OracleManagedDataAccessDirectory = Get-ChildItem -Directory -Path $ModulePath | where Name -Match Oracle

    Add-Type -Path "$ModulePath\$OracleManagedDataAccessDirectory\lib\net40\Oracle.ManagedDataAccess.dll"
}

function ConvertTo-OracleConnectionString {
    param(
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)][string]$Host,
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)][string]$Port,
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)][string]$Service_Name,
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)][string]$UserName,
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)][string]$Password,
        [Parameter(ValueFromPipelineByPropertyName)][string]$Protocol = "TCP"
    )
    "User Id=$UserName;Password=$Password;Pooling=false;Data Source=(DESCRIPTION=(ADDRESS=(PROTOCOL=$Protocol)(HOST=$Host)(PORT=$Port))(CONNECT_DATA=(SERVICE_NAME=$Service_Name)));"

}

function Invoke-OracleSQL {
    param(
        [Parameter(Mandatory)][string]$ConnectionString,
        [Parameter(Mandatory)][string]$SQLCommand,
        [Switch]$ConvertFromDataRow
    )
    Add-OracleManagedDataAccessType

    $Connection = New-Object -TypeName  Oracle.ManagedDataAccess.Client.OracleConnection($ConnectionString)
    $Command = new-object Oracle.ManagedDataAccess.Client.OracleCommand($SQLCommand,$Connection)
    $Connection.Open()
    
    $Adapter = New-Object Oracle.ManagedDataAccess.Client.OracleDataAdapter $Command
    $Dataset = New-Object System.Data.DataSet
    $Adapter.Fill($DataSet) | Out-Null
    
    $Connection.Close()
    
    if ($ConvertFromDataRow) {
        $DataSet.Tables | ConvertFrom-DataRow
    } else {
        $DataSet.Tables
    }
}
