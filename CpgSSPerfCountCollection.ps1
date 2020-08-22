<#
  This script is an extension of Microsoft DMA SkuRecommendationDataCollectionScript.ps1:
    - Allow remote server access with credentials
#>
param
(
    [Parameter(Mandatory=$true)][string]$ComputerName,
    [Parameter(Mandatory=$true)][string]$OutputFilePath,
    [Parameter(Mandatory=$true)][string]$CollectionTimeInSeconds,
    [Parameter(Mandatory=$true)][string]$DbConnectionString,
    [Parameter(Mandatory=$false)][string]$ComputerUser = "",
    [Parameter(Mandatory=$false)][string]$ComputerPassword = "",
    [Parameter(Mandatory=$false)][switch]$NoPromptForLongConnectionTime = $false
)

function CheckLogin
{
    param
    (
        [Parameter(Mandatory=$true)]$DbConnectionString
    )

    Try
    {
        $query = "SELECT 'test' AS test;"

        $connection = New-Object System.Data.SqlClient.SqlConnection($DbConnectionString)
        $command = New-Object System.Data.SqlClient.SqlCommand($query, $connection)
        $connection.Open()
        
        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $command
        $dataset = New-Object System.Data.DataSet
        $adapter.Fill($dataSet) | Out-Null

        $connection.Close()
        return $true
    }
    Catch
    {
        return $false
    }
}

function CheckMachineConnection
{
    param
    (
        [Parameter(Mandatory=$true)]$ComputerName
    )
    Write-Host "ComputerUser: " $ComputerUser
    Write-Host "Credential: " $Credential

    Try
    {
		if ($ComputerUser) {
           Write-Host "Credential: " $Credential
           New-CimSession -ComputerName $ComputerName -Credential $Credential -ErrorAction Stop
		} else {
           New-CimSession -ComputerName $ComputerName -ErrorAction Stop
		}
        return $true
    }
    catch
    {
        Write-Host $_.Exception.Message
		return $false
    }
}

function CheckPowershellVersion
{
    # On powershell versions <2.0, there is no $PSVersionTable.
    if (!$PSVersionTable)
    {
        return $false
    }
    
    return $PSVersionTable.PSVersion.Major -gt 3 
}

function GetSqlServerVersion
{
    param
    (
        [Parameter(Mandatory=$true)]$DbConnectionString
    )

    $query = "SELECT SERVERPROPERTY('EngineEdition') AS EngineEdition, SERVERPROPERTY('ProductVersion') AS ProductVersion;"

    $connection = New-Object System.Data.SqlClient.SqlConnection($DbConnectionString)
    $command = New-Object System.Data.SqlClient.SqlCommand($query, $connection)
    $connection.Open()
    
    $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $command
    $dataset = New-Object System.Data.DataSet
    $adapter.Fill($dataSet) | Out-Null

    $connection.Close()

    # Engine edition 0-4 corresponds to on-prem server.
    # 5, 6, and 8 correspond to SQL DB, SQL DW, and SQL MI
    if ($dataset.Tables[0].Rows[0].EngineEdition -gt 4)
    {
        return $null
    }

    $buildNumbers = $dataset.Tables[0].Rows[0].ProductVersion -split "\."
    return $buildNumbers[0] 
}

function GetRemoteNumberOfCores
{
    param
    (
        [Parameter(Mandatory=$true)][string]$ComputerName
    )
    
    $sumNumberOfCores = 0
	if ($ComputerUser) {
       $sumNumberOfCores = Invoke-Command -ComputerName $ComputerName -Credential $Credential `
            -ScriptBlock { (Get-WmiObject -Namespace "root\cimv2" -Class Win32_Processor -Impersonation 3 | Measure-Object -Property NumberOfCores -Sum).Sum}
	} else {
      #(Get-WmiObject -Namespace "root\cimv2" -Class Win32_Processor -Property "NumberOfCores" -Impersonation 3 -ComputerName $ComputerName) `
      #  | foreach-object {$sumNumberOfCores += $_.NumberOfCores}
      $sumNumberOfCores = Invoke-Command -ComputerName $ComputerName `
           -ScriptBlock { (Get-WmiObject -Namespace "root\cimv2" -Class Win32_Processor -Impersonation 3 | Measure-Object -Property NumberOfCores -Sum).Sum}
      #(Get-WmiObject -Namespace "root\cimv2" -Class Win32_Processor -Property "NumberOfCores" -Impersonation 3 -ComputerName $ComputerName) `
      #  | foreach-object {$sumNumberOfCores += $_.NumberOfCores}
    }    
    return $sumNumberOfCores
}

function ExtractServerNameFromConnectionString
{
    param
    (
        [Parameter(Mandatory=$true)][string]$DbConnectionString
    )

    $splitString = $DbConnectionString -split ';'

    foreach ($token in $splitString)
    {
        if ($token.StartsWith("Server="))
        {
            return $token.Replace("Server=", "").Trim()
        }
    }

    return "";
}

function GetRemoteAmountOfRamInGb
{
    param
    (
        [Parameter(Mandatory=$true)][string]$ComputerName
    )
    
    $sumAmountOfRam = 0
    $oneGb = 1024*1024*1024
    
	if ($ComputerUser) {
       #(Get-WmiObject -Class Win32_PhysicalMemory -Namespace "root\cimv2" -Impersonation 3 -ComputerName $ComputerName -Credential $Credential) `
       # | foreach-object {$sumAmountOfRam += $_.Capacity / $oneGb}
       $sumAmountOfRam = (Invoke-Command -ComputerName $ComputerName -Credential $Credential -ScriptBlock { (Get-WmiObject -Class Win32_PhysicalMemory -Namespace "root\cimv2" -Impersonation 3 | Measure-Object -Property Capacity -Sum).Sum}) / $oneGb
	} else {
       $sumAmountOfRam = (Invoke-Command -ComputerName $ComputerName -ScriptBlock { (Get-WmiObject -Class Win32_PhysicalMemory -Namespace "root\cimv2" -Impersonation 3 | Measure-Object -Property Capacity -Sum).Sum}) / $oneGb
    }
    
    return $sumAmountOfRam
}

function GetDbSsdMapping
{
     param
    (
        [Parameter(Mandatory=$true)][string]$ComputerName,
        [Parameter(Mandatory=$true)][string]$DbConnectionString
    )
   
    # Create CIM session for connection to remote computer
	if ($ComputerUser) {
       $cimSession = New-CimSession -ComputerName $computerName -Credential $Credential -ErrorAction Stop
       $availableVolumes = Invoke-Command -ComputerName $ComputerName -Credential $Credential `
           -ScriptBlock { Get-WmiObject -Class Win32_Volume | Where-Object {$_.DriveLetter -ne $null} | Foreach-Object {$_.DriveLetter[0]} }      
	} else {
       $cimSession = New-CimSession -ComputerName $computerName -ErrorAction Stop
       #$availableVolumes = Get-WmiObject -Class Win32_Volume -ComputerName $ComputerName `
       # | Where-Object {$_.DriveLetter -ne $null} `
       # | Foreach-Object {$_.DriveLetter[0]}
       $availableVolumes = Invoke-Command -ComputerName $ComputerName `
           -ScriptBlock { Get-WmiObject -Class Win32_Volume | Where-Object {$_.DriveLetter -ne $null} | Foreach-Object {$_.DriveLetter[0]} }      
    }

    $letterSsdMapping = @{}

    $missingMappings = @()
    
    foreach ($volume in $availableVolumes)
    {
        try
        {
            $mediaType = (Get-PhysicalDisk -SerialNumber (Get-Disk (Get-Partition -DriveLetter $volume -CimSession $cimSession).DiskNumber -CimSession $cimSession).SerialNumber -CimSession $cimSession).MediaType 2>$null
            $letterSsdMapping[[string]$volume] = ($mediaType -eq 'SSD')
        }
        catch
        {
            $letterSsdMapping[[string]$volume] = $false 
            $missingMappings += [string]$volume
        }
    }

    if ($missingMappings.Length -ne 0)
    {
        $msg = 'Unable to get SSD mapping for the following drives: {0}. Assuming that they are HDD drives. If any of the drives is an SSD, change the value under the "IsDbStorageSsd" metadata portion of the output file from "False" to "True" for all databases hosted on that drive.' -f [String]::Join(",", $missingMappings)
        Write-Host $msg
    }
    
    $query = "SELECT DISTINCT [db].[Name], 
                     LEFT([mf].[physical_name], 1) 
              FROM [sys].[master_files] AS [mf] 
              INNER JOIN [sys].[databases] AS [db]
              ON [db].[database_id] = [mf].[database_id]
              WHERE [db].[Name] NOT LIKE '%_log%'"

    $connection = New-Object System.Data.SqlClient.SqlConnection($DbConnectionString)
    $command = New-Object System.Data.SqlClient.SqlCommand($query, $connection)
    $connection.Open()
    
    $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $command
    $dataset = New-Object System.Data.DataSet
    $adapter.Fill($dataSet) | Out-Null

    $connection.Close()

    $dbSsdMapping = @{}
    foreach ($row in $dataset.Tables[0].Rows)
    {
        $dbName = $row.Name
        $isSsd = $letterSsdMapping[[string]$row.Column1]
        $dbSsdMapping[$dbName] = $isSsd
    }

    return $dbSsdMapping
}

function GetDbHaReplication
{
    param
    (
        [Parameter(Mandatory=$true)][string]$DbConnectionString
    )

    $query = "declare @host_platform nvarchar(max)
            set @host_platform = 'Windows'
            if exists (select * from sys.system_views where name = 'dm_os_host_info')
            begin
                -- This system view only exists in SQL Server 2017 and above. If it doesn't
                -- exist, we can assume the host platform is Windows.
                select @host_platform = host_platform from sys.dm_os_host_info;
            end

            select 
                db.name as database_name,
                COALESCE(SERVERPROPERTY ('IsHadrEnabled'), '0') as is_hadr_enabled,
                case when is_published = 1 OR is_subscribed = 1 OR is_merge_published = 1 or is_distributor = 1
                    THEN 1 
                    ELSE 0
                end as is_replication_enabled
            from sys.databases db
            where db.name not in ('master', 'tempdb', 'model', 'msdb')
            order by db.name"

    $connection = New-Object System.Data.SqlClient.SqlConnection($DbConnectionString)
    $command = New-Object System.Data.SqlClient.SqlCommand($query, $connection)
    $connection.Open()
    
    $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $command
    $dataset = New-Object System.Data.DataSet
    $adapter.Fill($dataSet) | Out-Null

    $connection.Close()

    $dbHaEnabled = @{}
    $dbReplicationEnabled = @{}
    foreach ($row in $dataset.Tables[0].Rows)
    {
        $dbName = $row.database_name
        $isReplicationEnabled = $row.is_replication_enabled
        $isHaEnabled = $row.is_hadr_enabled

        $dbHaEnabled[$dbName] = $isHaEnabled
        $dbReplicationEnabled[$dbName] = $isReplicationEnabled
    }

    return $dbHaEnabled, $dbReplicationEnabled
}

function GetDbDriveSizeInMb
{
    param
    (
        [Parameter(Mandatory=$true)][string]$DbConnectionString
    )

    $query = "WITH [fs]
                AS
                (
                    SELECT	[database_id], 
                            [type], 
                            [size] * 8.0 / 1024 AS [size]
                    FROM [sys].[master_files]
                )
                SELECT
                    [db].[name],
                    sum([fs].[size]) AS [size_in_mb]
                    FROM [fs]
                    INNER JOIN [sys].[databases] AS [db]
                    ON [db].[database_id] = [fs].[database_id]
                    WHERE [fs].[type] = 0 or [fs].[type] = 1
                    GROUP BY [db].[name]"

    $connection = New-Object System.Data.SqlClient.SqlConnection($DbConnectionString)
    $command = New-Object System.Data.SqlClient.SqlCommand($query, $connection)
    $connection.Open()
    
    $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $command
    $dataset = New-Object System.Data.DataSet
    $adapter.Fill($dataSet) | Out-Null

    $connection.Close()

    $dbSize = @{}

     foreach ($row in $dataset.Tables[0].Rows)
    {
        $dbName = $row.name
        $size = $row.size_in_mb

        $dbSize[$dbName] = $size
    }

    return $dbSize
}

function GetBufferPoolEnabled
{
    param
    (
        [Parameter(Mandatory=$true)][string]$DbConnectionString
    )

    $bufferPoolEnabled = $false

    Try
    {
        $query = "SELECT CASE WHEN state = 3 OR state = 5 Then 'T' ELSE 'F' END AS is_bufferpoolextn_enabled FROM sys.dm_os_buffer_pool_extension_configuration"

        $connection = New-Object System.Data.SqlClient.SqlConnection($DbConnectionString)
        $command = New-Object System.Data.SqlClient.SqlCommand($query, $connection)
        $connection.Open()
        
        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $command
        $dataset = New-Object System.Data.DataSet
        $adapter.Fill($dataSet) | Out-Null

        $connection.Close()

        foreach ($row in $dataset.Tables[0].Rows)
        {
            if ($dataset.is_bufferpoolextn_enabled -eq 'T')
            {
                $bufferPoolEnabled = $true
            }
        }
    }
    Catch
    {
        $bufferPoolEnabled = $false
    }

    return $bufferPoolEnabled
}

function MaxDate
{
    param
    (
        [Parameter(Mandatory=$true)][DateTime]$d1,
        [Parameter(Mandatory=$true)][DateTime]$d2
    )

    if ($d1 -gt $d2)
    {
        return $d1
    }

    return $d2
}

function QueryDmExecStats
{
    param
    (
        [Parameter(Mandatory=$true)]$DbConnectionString,
        [Parameter(Mandatory=$true)]$LastCollectionTime
    )
  
    $query = "SELECT qs.sql_handle,
                        qs.plan_generation_num,
                        qs.creation_time,
                        qs.last_execution_time,
                        qs.plan_handle,
                        qs.query_hash,
                        qs.query_plan_hash,
                        DB_NAME(CONVERT(int, pa.value)) AS db_name,
                        qs.execution_count,
                        qs.total_worker_time,
                        qs.min_worker_time,
                        qs.max_worker_time,
                        qs.total_physical_reads,
                        qs.min_physical_reads,
                        qs.max_physical_reads,
                        qs.total_logical_reads,
                        qs.min_logical_reads,
                        qs.max_logical_reads,
                        qs.total_logical_writes,
                        qs.min_logical_writes,
                        qs.max_logical_writes,
                        qs.total_clr_time,
                        qs.min_clr_time,
                        qs.max_clr_time,
                        qs.total_elapsed_time,
                        qs.min_elapsed_time,
                        qs.max_elapsed_time
                FROM sys.dm_exec_query_stats AS qs
                CROSS APPLY sys.dm_exec_plan_attributes(qs.plan_handle) AS pa
                WHERE pa.attribute = 'dbid'
                AND qs.last_execution_time > '{0}-{1}-{2} {3}:{4}:{5}'" -f $LastCollectionTime.Year, $LastCollectionTime.Month, $LastCollectionTime.Day, $LastCollectionTime.Hour, $LastCollectionTime.Minute, $LastCollectionTime.Second

    $connection = New-Object System.Data.SqlClient.SqlConnection($DbConnectionString)
    $command = New-Object System.Data.SqlClient.SqlCommand($query, $connection)
    $connection.Open()
        
    $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $command
    $dataset = New-Object System.Data.DataSet
    $adapter.Fill($dataSet) | Out-Null

    $connection.Close()

    $results = @{}
    $hashFunction = [System.Security.Cryptography.HashAlgorithm]::Create("SHA256")

    $largestTime = [DateTime]::MinValue

    foreach ($row in $dataset.Tables[0].Rows)
    {
        $currentResult = @{}
        foreach ($column in $dataset.Tables[0].Columns)
        {
            $currentResult[$column.ColumnName] = $row[$column]
        }

        $hashStringBuilder = New-Object System.Text.StringBuilder

        $hashBytes = $currentResult['sql_handle']`
            + [System.Text.Encoding]::UTF8.GetBytes($currentResult['plan_generation_num'].ToString()) `
            + [System.Text.Encoding]::UTF8.GetBytes($currentResult['plan_handle'].ToString()) `
            + $currentResult['query_hash'] `
            + $currentResult['query_plan_hash']

        $unused = $hashFunction.ComputeHash($hashBytes) | Foreach-Object {$hashStringBuilder.Append($_.ToString("x2"))}
        $hash = $hashStringBuilder.ToString()
        $currentResult['hash'] = $hash
        $results[$hash] = $currentResult

        $largestTime = MaxDate $largestTime $row['last_execution_time']
    }

    $outVal = @{}
    $outVal['results'] = $results
    $outVal['largestTime'] = $largestTime

    return $outVal
}

function FindMissingCounters
{
    param
    (
        [Parameter(Mandatory=$true)][string]$DbConnectionString,
        [Parameter(Mandatory=$true)][string[]]$Counters
    )

    $query = "EXEC sp_columns 'dm_exec_query_stats'"

    $connection = New-Object System.Data.SqlClient.SqlConnection($DbConnectionString)
    $command = New-Object System.Data.SqlClient.SqlCommand($query, $connection)
    $connection.Open()
        
    $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $command
    $dataset = New-Object System.Data.DataSet
    $adapter.Fill($dataSet) | Out-Null

    $connection.Close()

    $columns= @{}
    
    foreach ($row in $dataset.Tables[0].Rows)
    {
        $columns[$row.column_name] = ""    
    }

  
    
    $missingCounters = @()
    foreach ($counter in $counters)
    {
        if (!$columns.ContainsKey($counter))
        {
            $missingCounters += $counter
        }
    }

    return $missingCounters
}

function SaveCountersToFile
{
    param
    (
        [Parameter(Mandatory=$true)][string]$DbConnectionString,
        [Parameter(Mandatory=$true)][string]$OutputFilePath,
        [Parameter(Mandatory=$true)][int]$CollectionSeconds,
        [Parameter(Mandatory=$true)][string[]]$Counters
    )

    $firstMinute = $true
    $previousMinuteHashTable = @{}
    $currentMinuteHashTable = @{}
    $nextCollectionTime = Get-Date
    $previousMinute = $nextCollectionTime.Minute
    $collectionIntervalInSeconds = 10
    $headerWritten = $false
    $lastQueryTime = [DateTime]::MinValue

    # Initialize previousMinuteHashTable

    for ($unused = 0; $unused -lt ($CollectionSeconds / $collectionIntervalInSeconds); $unused++) 
    {
        $currentCollectionTime = $nextCollectionTime
        $currentMinute = $currentCollectionTime.Minute
        $nextCollectionTime = $nextCollectionTime.AddSeconds($collectionIntervalInSeconds)

        $stats = QueryDmExecStats $DbConnectionString $lastQueryTime
        $queryResult = $stats['results']
        $lastQueryTime = $stats['largestTime']

        foreach ($key in $queryResult.Keys)
        {
            if (!$currentMinuteHashTable.ContainsKey($key))
            {
                $currentMinuteHashTable[$key] = @()
            }
            $currentMinuteHashTable[$key] += @($queryResult[$key])
        }

        if ($currentMinute -ne $previousMinute)
        {
            if (!$headerWritten)
            {
                $headerLine = [string]::Join(",", $Counters) + ",db_name,timestamp,hash"
                Out-File -InputObject $headerLine.ToString([System.Globalization.CultureInfo]::InvariantCulture) -FilePath $OutputFilePath -NoClobber -Append -Encoding UTF8
                $headerWritten = $true
            }

            $thisMinuteTotalValues = @{}

            foreach ($key in $currentMinuteHashTable.Keys)
            {
                $lineSb = New-Object System.Text.StringBuilder
                
                $previousMinuteTotalValues = $null
                if ($previousMinuteHashTable.ContainsKey($key))
                {
                    $previousMinuteTotalValues = $previousMinuteHashTable[$key]
                }

                $thisMinuteHashTotalValues = @{}

                for ($i = 0; $i -lt $Counters.Length; $i++)
                {
                    $value = 0
                    if ($Counters[$i].Contains('min'))
                    {
                        $value = [double]::MaxValue
                        for ($j = 0; $j -lt $currentMinuteHashTable[$key].Length; $j++)
                        {
                            $value = [Math]::Min($value, $currentMinuteHashTable[$key][$j][$Counters[$i]])
                        }
                    }
                    else
                    {
                        $value = [double]::MinValue
                        for ($j = 0; $j -lt $currentMinuteHashTable[$key].Length; $j++)
                        {
                            $value = [Math]::Max($value, $currentMinuteHashTable[$key][$j][$Counters[$i]])
                        }
                    }
                    
                    # If not a min or max feature, diff with previous minute value
                    if (!$Counters[$i].Contains('min') -and !$Counters[$i].Contains('max'))
                    {
                        $thisMinuteHashTotalValues[$Counters[$i]] = $value
                        if ($previousMinuteTotalValues -ne $null -and ($previousMinuteTotalValues[$Counters[$i]] -le $value))
                        {
                            $value = $value - $previousMinuteTotalValues[$Counters[$i]]
                        }
                    }

                    $lineSb.Append($value.ToString([System.Globalization.CultureInfo]::InvariantCulture)) | Out-Null
                    $lineSb.Append(",") | Out-Null
                }

                $thisMinuteTotalValues[$key] = $thisMinuteHashTotalValues

                $lineSb.Append($currentMinuteHashTable[$key][0].db_name.ToString([System.Globalization.CultureInfo]::InvariantCulture).Replace('#', '#HASH#').Replace(",", "#COMMA#")) | Out-Null
                $lineSb.Append(",") | Out-Null
                $lineSb.Append($currentCollectionTime.ToString([System.Globalization.CultureInfo]::InvariantCulture)) | Out-Null
                $lineSb.Append(",") | Out-Null
                $lineSb.Append($key.ToString([System.Globalization.CultureInfo]::InvariantCulture)) | Out-Null

                if (!$firstMinute -and (($previousMinuteTotalValues -ne $null) -and ($thisMinuteHashTotalValues['execution_count'] -ne $previousMinuteTotalValues['execution_count'])))
                {
                    Out-File -InputObject $lineSb.ToString() -FilePath $OutputFilePath -NoClobber -Append -Encoding UTF8
                }
            }

            foreach ($key in $thisMinuteTotalValues.Keys)
            {
                $previousMinuteHashTable[$key] = $thisMinuteTotalValues[$key]
            }

            $currentMinuteHashTable = @{}
            $previousMinute = $currentMinute
            $firstMinute = $false
        }

        

        Start-Sleep ([Math]::Max(0, ((($nextCollectionTime - (Get-Date)).TotalMilliseconds) / 1000.0)))
    }
}

function OutputMetadataDict
{
    param
    (
        [Parameter(Mandatory=$true)][hashtable]$Dict,
        [Parameter(Mandatory=$true)][string]$MetadataName,
        [Parameter(Mandatory=$true)][string]$OutputFilePath
    )

    Out-File -InputObject "$MetadataName=" -FilePath $OutputFilePath -NoClobber -Append -Encoding UTF8
    foreach ($key in $Dict.Keys)
    {
       if($Dict[$key] -ne $null)
       {
           Out-File -InputObject $key.ToString([System.Globalization.CultureInfo]::InvariantCulture).Replace("#", "#HASH#").Replace(",", "#COMMA#") -FilePath $OutputFilePath -NoClobber -Append -Encoding UTF8
           Out-File -InputObject $Dict[$key].ToString([System.Globalization.CultureInfo]::InvariantCulture) -FilePath $OutputFilePath -NoClobber -Append -Encoding UTF8
       }
       else
       {
           Write-Host "Metadata empty value for the key: " $key 
       }
    }
    Out-File -InputObject "EndMapping" -FilePath $OutputFilePath -NoClobber -Append -Encoding UTF8
}

function DeleteFile
{
    param
    (
        [Parameter(Mandatory=$true)][string]$FilePath
    )

    $error = $false
    try
    {
        [System.IO.File]::Delete($FilePath)
    }
    catch
    {
        $error = $true
    }

    if ([System.IO.File]::Exists($FilePath))
    {
        $error = $true
    }

    if ($error)
    {
        Write-Host ""
        Write-Host ""
        Write-Host "DMA could not delete $FilePath."
        Write-Host "Please manually delete this file or specify a different output path."
        Write-Host ""
        Write-Host ""
    }

    return !$error
}

function ValidateOutputFilePath
{
    param
    (
        [Parameter(Mandatory=$true)][string]$OutputFilePath
    )

    if ([System.IO.File]::Exists($OutputFilePath))
    {
        Write-Host "The file $OutputFilePath already exists."
        Write-Host "Overwrite [Y/n]?"
        # if (Confirm)
        if ($true)
        {
            Write-Host "Deleting file."
            $deleted = DeleteFile $OutputFilePath
            if (!$deleted)
            {
                return $false
            }
        }
        else
        {
            Write-Host ""
            Write-Host ""
            Write-Host "Collection aborted. Please retry specifying a new file path."
            Write-Host ""
            Write-Host ""
            return $false
        }
    }

    $exists = $false
    try
    {
        Out-File -InputObject "test" -FilePath $OutputFilePath
        $exists = [System.IO.File]::Exists($OutputFilePath)
    }
    catch
    {
        $exists = $false
    }

    if (!$exists)
    {
        Write-Host ""
        Write-Host ""
        Write-Host "DMA was not able to write to the path $OutputFilePath."
        Write-Host "Please check that the path is accessable and that the current user has write permission."
        Write-Host ""
        Write-Host ""
        return $false
    }
  
    return DeleteFile $OutputFilePath
}

function Confirm
{
    $confirmation = 'q'
    while ($confirmation -ne 'y' -and $confirmation -ne 'n')
    {
        $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        if ($key.VirtualKeyCode -eq 13)
        {
            $confirmation = 'y'
        }
        else
        {
            $confirmation = [System.Char]::ToLowerInvariant($key.Character)
        }
    }

    return $confirmation -eq 'y'
}

Write-Host "Checking powershell version..."
$powershellVersionSupported = CheckPowershellVersion
if (!$powershellVersionSupported)
{
    Write-Host ""
    Write-Host ""
    Write-Host "Powershell version 4.0 or greater is required to run this script."
    Write-Host ""
    Write-Host ""
    return
}
else
{
    Write-Host "Powershell version is version 4 or greater."
}

$outputFilePathValid = ValidateOutputFilePath $OutputFilePath
if (!$outputFilePathValid)
{
    return
}

Write-Host "Validating collection time..."
if (!($CollectionTimeInSeconds -match "^\d+$"))
{
    Write-Host ""
    Write-Host ""
    Write-Host "The specified collection time of $CollectionTimeInSeconds seconds is not an integer value."
    Write-Host "Please retry with an integer collection time of at least 60 seconds."
    Write-Host ""
    Write-Host ""
    return
}
elseif ([int]$CollectionTimeInSeconds -lt 120)
{
    Write-Host ""
    Write-Host ""
    Write-Host "The specified collection time of $CollectionTimeInSeconds seconds is less than two minutes."
    Write-Host "DMA requires a collection time of at least two minutes to operate."
    Write-Host "Please retry with a collection time of at least 120 seconds."
    Write-Host ""
    Write-Host ""
    return
}
elseif ([int]$CollectionTimeInSeconds -gt 18000 -and !$NoPromptForLongConnectionTime)
{
    Write-Host ""
    Write-Host ""
    Write-Host "The collection time is set to $CollectionTimeInSeconds seconds."
    Write-Host "Are you sure you would like to collect for this amount of time [Y/n]?"
    
    # $confirmation = Confirm
    $confirmation = $true
   
    if ($confirmation)
    {
        Write-Host "Confirmed. Continuing execution."
    }
    else
    {
        Write-Host "Collection aborted."
        return
    }
}
else
{
    Write-Host "Collecting for $CollectionTimeInSeconds seconds."
}

$serverName = ExtractServerNameFromConnectionString $DbConnectionString
$str = 'Server name: {0}' -f $serverName
Write-Host $str
$serverNameStr = 'ServerName={0}' -f $serverName

Write-Host "Checking connection to server..."
$ableToLogin = CheckLogin $DbConnectionString
if (!$ableToLogin)
{
    Write-Host ""
    Write-Host ""
    Write-Host "Unable to connect to server. Verify that the connection string is correct."
    Write-Host ""
    Write-Host ""
    return
}
else
{
    Write-Host "Able to connect to server."
}

Write-Host "Getting the source SQL Server product version..."
$sqlServerVersion = GetSqlServerVersion $DbConnectionString

if ($sqlServerVersion -ne $null)
{
    Write-Host "Found SQL Server version $sqlServerVersion"
}
else
{
    Write-Host "Found an unidentified SQL Server version.";
}

if (($sqlServerVersion -eq $null) -or ($sqlServerVersion -lt 10))
{
    Write-Host ""
    Write-Host ""
    Write-Host "SKU recommendations for Azure SQL database are currently available from SQL Server 2008 or later."
    Write-Host "If you have multiple versions of SQL Server installed, verify that the correct port has been specified in the connection string and that the correct instance name has been specified, if applicable."
    Write-Host ""
    Write-Host ""
    return
}
else
{
    Write-Host "SKU Recommendations for Azure SQL Database are supported on this SQL Server version."
}

$counters = @(`
              "execution_count",`
              "total_worker_time",`
              "min_worker_time",`
              "max_worker_time",`
              "total_physical_reads",`
              "min_physical_reads",`
              "max_physical_reads",`
              "total_logical_reads",`
              "min_logical_reads",`
              "max_logical_reads",`
              "total_logical_writes",`
              "min_logical_writes",`
              "max_logical_writes",`
              "total_clr_time",`
              "min_clr_time",`
              "max_clr_time",`
              "total_elapsed_time",`
              "min_elapsed_time",`
              "max_elapsed_time"
            )

Write-Host "Checking for availability of required system metadata."
$missingCounters = FindMissingCounters $DbConnectionString $counters
if ($missingCounters.Length -eq 0)
{
    Write-Host "All required metadata information present."
}
else
{
    Write-Host ""
    Write-Host ""
    Write-Host "DMA detected that the following required pieces of system metadata are missing from the input file:"
    
    foreach ($missingCounter in $missingCounters)
    {
        Write-Host "`t$missingCounter"
    }

    Write-Host "These counters are available in all versions of SQL Server 2008 or later from the sys.dmv_exec_query_stats view."
    Write-Host "To troubleshoot this issue, use the following steps:"
    Write-Host "`t1) Connect to the SQL Server. Verify that the system view sys.dmv_exec_query_stats is functional"
    Write-Host "`t2) Re-run the powershell data collection script."
    Write-Host "`t3) If the error persists, try restarting the server and rerunning the powershell script."
    Write-Host "`t4) If the error persists, please contact us at DMAFeedback@microsoft.com"

    Write-Host ""
    Write-Host ""
    return
}

$Credential = [pscredential]::Empty
if ($ComputerUser) {
   $PWord = ConvertTo-SecureString -String $ComputerPassword -AsPlainText -Force
   $Credential = New-Object -TypeName "System.Management.Automation.PSCredential" -ArgumentList $ComputerUser,$PWord
}
Write-Host "Checking connection to machine..."
$ableToConnectToMachine = CheckMachineConnection $ComputerName

if (!$ableToConnectToMachine)
{
    Write-Host "Unable to connect to machine. Verify that the computer name is correct and that the current user has permission to connect."
    return
}
else
{
    Write-Host "Connection succeeded."
}
$numberOfCores = GetRemoteNumberOfCores $ComputerName
$str = 'Number of cores: {0}' -f $numberOfCores
Write-Host $str
$numberOfCoresStr = 'NumberOfCores={0}' -f $numberOfCores 

$amountOfRamInGb = GetRemoteAmountOfRamInGb $ComputerName
$str = 'Amount of Ram (in GB): {0}' -f $amountOfRamInGb
Write-Host $str
$amountOfRamInGbStr = 'AmountOfRamInGb={0}' -f $amountOfRamInGb

$mapping = GetDbSsdMapping $ComputerName $DbConnectionString
Write-Host "Successfully captured DB-SSD mapping"

$values = GetDbHaReplication $DbConnectionString
$haEnabled = $values[0]
$replicationEnabled = $values[1]
Write-Host "Successfully captured HA / Replication state"

$dbSize = GetDbDriveSizeInMb $DbConnectionString
Write-Host "Successfully captured DB size"

$bufferPoolEnabled = GetBufferPoolEnabled $DbConnectionString
Write-Host "Successfully captured buffer pool state"

if ([int]$CollectionTimeInSeconds -lt (40 * 60))
{
    Write-Host ""
    Write-Host ""
    Write-Host "DMA has detected that the requested collection time is less than 40 minutes (2400 seconds)."
    Write-Host "This may decrease the accuracy of the resulting recommendations."
    Write-Host ""
    Write-Host "DMA recommends collecting data for at least 40 minutes, and ideally 2 hours, during peak load."
    Write-Host "For more information, refer to the documentation: https://docs.microsoft.com/en-us/sql/dma/dma-sku-recommend-sql-db?view=sql-server-2017"
    Write-Host ""
    Write-Host ""
}

Write-Host "Collecting for $CollectionTimeInSeconds seconds..."
SaveCountersToFile $DbConnectionString $OutputFilePath $CollectionTimeInSeconds $counters
Write-Host "Collection Complete. Writing system metadata..."

Out-File -InputObject "Metadata" -FilePath $OutputFilePath -NoClobber -Append -Encoding UTF8
Out-File -InputObject $numberOfCoresStr -FilePath $OutputFilePath -NoClobber -Append -Encoding UTF8
Out-File -InputObject $amountOfRamInGbStr -FilePath $OutputFilePath -NoClobber -Append -Encoding UTF8
Out-File -InputObject $serverNameStr -FilePath $OutputFilePath -NoClobber -Append -Encoding UTF8

OutputMetadataDict $mapping "IsDbStorageSsd" $OutputFilePath
OutputMetadataDict $haEnabled "HaEnabled" $OutputFilePath
OutputMetadataDict $replicationEnabled "ReplicationEnabled" $OutputFilePath
OutputMetadataDict $dbSize "DbSize" $OutputFilePath

Out-File -InputObject "IsBufferPoolEnabled=$bufferPoolEnabled" -FilePath $OutputFilePath -NoClobber -Append -Encoding UTF8

$str = "Done. Output saved to {0}" -f $OutputFilePath
Write-Host $str
Write-Host "You can now use DMA to get SKU recommendations for Azure SQL DB."
Write-Host "For more information, refer to the documentation: https://docs.microsoft.com/en-us/sql/dma/dma-sku-recommend-sql-db?view=sql-server-2017"
