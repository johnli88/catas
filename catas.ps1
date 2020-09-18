<#
.synaposis
  This script allows user to assess on-preimises SQL Server databases before migrating to Azure

.description
  This script is an extension of Microsoft DMA SkuRecommendationDataCollectionScript.ps1:
    - Allow remote server access with credentials

.example
  Usage:
     # Validate all SQL server host connections
     catas.ps1 -AssessName "myAssessment" -InputFile C:\John\my-sql-server-list.csv -ValidateHost

     # Validate all SQL server instance connections
     catas.ps1 -AssessName "myAssessment" -InputFile C:\John\my-sql-server-list.csv -ValidateSql

     # Assess feature parity all the servers from my-sql-server-list.csv and generate dma/json reports
     catas.ps1 -AssessName "myAssessment" -InputFile C:\John\my-sql-server-list.csv -OutputFolder OutputFolderName [-ReportName ReportName] -AssessType Feature

     # Assess compatibility all the servers from my-sql-server-list.csv and generate dma/json reports
     catas.ps1 -AssessName "myAssessment" -InputFile C:\John\my-sql-server-list.csv -OutputFolder OutputFolderName [-ReportName ReportName] -AssessType Compat

     # Evaluate recommendation for all the servers from my-sql-server-list.csv and generate json reports
     catas.ps1 -AssessName "myAssessment" -InputFile C:\John\my-sql-server-list.csv -OutputFolder OutputFolderName [-ReportName ReportName] -AssessType Evaluate

     # Assess all the servers from my-sql-server-list.csv and generate full reports
     catas.ps1 -AssessName "myAssessment" -InputFile C:\John\my-sql-server-list.csv -OutputFolder OutputFolderName [-ReportName ReportName]

     # Collect SQL server workload performance counts for 240 seconds
     catas.ps1 -AssessName "myAssessment" -InputFile ".\sql-server-list.csv" -OutputFolder "C:\John\temp" -Target "SQLdb" -AssessType workload -WorkloadTime 240

     # Collect SQL server workload performance counts for 240 seconds and write result to myReport 
     catas.ps1 -AssessName "myAssessment" -InputFile ".\sql-server-list.csv" -OutputFolder "C:\John\temp" -Target "SQLdb" `
        -AssessType workload -ReportName myReport -WorkloadTime 240

     # Estimate Azure SQL DB & MI cost from performance count file for all databases
     catas.ps1 -AssessName "test2" -InputFile ".\sql-server-list.csv" -OutputFolder "C:\John\temp" -Target "SQLdb" `
         -AssessType SKu -CountFile "C:\John\temp\counters-52.228.17.215.csv" -SubscriptionId "0f81e775-f418-4020-a53f-013122a792b8" `
         -TenantId "7d270c48-208d-49f0-ade1-e658c4ef4f18" -ClientId "8dc6a081-3a6a-45e9-bc41-47550ee9aee2"

     # Estimate Azure SQL DB & MI cost from performance count file for all databases AdventureWorksLT2014, AdventureWorks2014, AdventureWorksDW2014
     catas.ps1 -AssessName "test" -InputFile ".\sql-server-list.csv" -OutputFolder "C:\John\temp" `
          -AssessType SKu -CountFile "C:\John\temp\counters-localhost.csv" -SubscriptionId "0f81e775-f418-4020-a53f-013122a792b8" `
          -TenantId "7d270c48-208d-49f0-ade1-e658c4ef4f18" -ClientId "8dc6a081-3a6a-45e9-bc41-47550ee9aee2" `
          -DatabaseNames '"AdventureWorksLT2014" "AdventureWorks2014" "AdventureWorksDW2014"'

     # Collect SQL Server workload performance count and estimate Azure SQL DB & MI cost based on SQL instances provided
     catas.ps1 -AssessName "test2" -InputFile ".\sql-server-list.csv" -OutputFolder "C:\John\temp" `
          -AssessType WorkloadSKu -WorkloadTime 240 -SubscriptionId "0f81e775-f418-4020-a53f-013122a792b8" `
          -TenantId "7d270c48-208d-49f0-ade1-e658c4ef4f18" -ClientId "8dc6a081-3a6a-45e9-bc41-47550ee9aee2"

    # assess SSIS packages
    .\catas.ps1 -AssessName "myAssessment" -InputFile ".\sql-server-list.csv" -OutputFolder "C:\John\temp" `
     -Target "SQLdb" -AssessType ssis


 Input File: CSV comma separate fields with following columns:
   Host: Mandatory; can be hostname, FQDN, or IP address
   User: Host user ID; if not provided current user ID is used
   Password: Host user password; must provide if host user ID is provided
   Instance: SQL Server instance name; can be null, default, or named instance
   Port: SQL Server port #; valid value can be a number or null
   SqlUser: sql server authentication user ID; if not provided, current user ID is used for Windows authentication
   SqlPassword: password for SqlUser
   DBlist: list of database to be assessed; valid value "db1,db2,db3"; use "*" or null for all databases in the SQL instance
   Comment: any value

   Example:
    Host, User, Password, Instance, Port, SqlUser, SqlPassword, DBlist, Comment
    "52.228.17.215","sqladmin","Password123","Default",DEFAULT,"sqladmin","Password123","*","Azuure"
    "RHDBDV16",,,"Default",,,,"KanaResponseProd, RMarchiveFIN, Magic,rmdb_logistics","IT"
    "40.85.219.90","vmadmin","Password123","COMPUGEN",14333,"sqladmin","Password123",,"Azure"

 Output Report: 
   OutputFolderName: this is optional and default to C:\temp; if the folder does not exist, it will be created
   OuputReportName: this is optional; if OutputReportName is not provided, AssessName will be used for the report name; final format is:
                    OutputReportName_YYYYMMDDHHMMSS.dma


 DMA log location: C:\Users\jzli\AppData\Local\DataMigrationAssistant\Dma.log
#>
param
(
    [Parameter(Mandatory=$true)][string]$AssessName,
    [Parameter(Mandatory=$false)][string]$InputFile,              # required for all cases except for assessType='sku'
    [Parameter(Mandatory=$false)][string]$OutputFolder,           # Folder for output reports; default C:\temp
    [Parameter(Mandatory=$false)][string]$ReportName,             # report name will be appended by timestamp; default is AssessName
    [Parameter(Mandatory=$false)][string]$Target,                 # target platform: SQLDB (default) or SQLMI, SqlServer2012, SqlServer2014, SqlServer2016, SqlServerLinux2017 and SqlServerWindows2017
    [Parameter(Mandatory=$false)][switch]$ValidateHost = $false,
    [Parameter(Mandatory=$false)][switch]$ValidateSql = $false,
    [Parameter(Mandatory=$false)][switch]$ValidateBoth = $false,
    [Parameter(Mandatory=$false)][string]$AssessType,             # type of assessment: Feature, Compat, Evaluate, Workload, Sku, WorkloadSku, ssis; defaul both Feature & Compat
    [Parameter(Mandatory=$false)][string]$DmaHome,                # DMA home director (default: C:\Program Files\Microsoft Data Migration Assistant)
    [Parameter(Mandatory=$false)][int]$WorkloadTime = 3600,       # Workload collection time in seconds; default one hour and minimum 240
    [Parameter(Mandatory=$false)][string]$CountFile,              # Performance count file; required when SKU specified
    [Parameter(Mandatory=$false)][string]$CurrencyCode = "CAD",         # Currency code; required when SKU specified; default Canadian dollar
    [Parameter(Mandatory=$false)][string]$OfferName="MS-AZR-0003P",     # Offer name; required when SKU specified; default MS-AZR-0003P (MS-AZR-0145P: CSP)
    [Parameter(Mandatory=$false)][string]$RegionName="canadacentral",   # Geogrphic region; required when SKU specified; default Canada Central
    [Parameter(Mandatory=$false)][string]$SubscriptionId,               # Azure subscription ID; required when SKU specified
    [Parameter(Mandatory=$false)][string]$DatabaseNames,          # List of database names to be SKUed; default is all DBs "*"
    [Parameter(Mandatory=$false)][string]$ClientId,               # Client ID; required when SKU specified
    [Parameter(Mandatory=$false)][string]$TenantId,               # Tenanet ID; required when SKU specified
    [Parameter(Mandatory=$false)][switch]$Printout = $false
)

function StandardizeInput
{
    param
    (
        [Parameter(Mandatory=$true)]$InputFile
    )

    $servers = Import-Csv $InputFile
    # $server = $servers[0]
    $serverList = @()
    foreach ($server in $servers) {
        if (!$server.Host) {
            Write-Host "server host is empty" $server
            Exit
        } elseif ($server.Host.ToLower() -eq 'local' -or $server.Host.ToLower() -eq 'localhost') {
            $server.Host = "localhost"
        }
        if ($server.Instance -eq '' -or $server.Instance -eq ' ' -or $server.Instance.ToLower() -eq 'default') {
            $server.Instance = "default"
        }
        if ($server.Port -eq 1433 -or $server.Port -eq '' -or $server.Port -eq ' ' -or $server.Port.ToLower() -eq 'default') {
            $server.Port = "default"
        }
        if ($server.DBlist -eq '' -or $server.Port -eq ' ' -or $server.Port.ToLower() -eq 'all') {
            $server.DBlist = '*'
        }
        $serverList += $server
    }

    return $serverList
}

function CheckOutput
{
    param
    (
        [Parameter(Mandatory=$false)][switch]$FolderOnly = $false
    )
    $rightNow = (Get-Date).tostring("yyyyMMddHHmmss")

    # set default folder if not provided
    if (!$OutputFolder) {
       $OutputFolder = "C:\temp"
    }

    # create the report folder if it does not exist
    if (!(Test-Path -Path $OutputFolder)) {
       New-Item -ItemType directory -Path $OutputFolder
    }

    # $server = $servers[0]
    if (!$ReportName) {
       $ReportName = $AssessName
    }

    if ($FolderOnly) {
        $ReportName = $OutputFolder
    } else {
        $ReportName = $OutputFolder + "\" + $ReportName + "_" + $rightNow
    }
    #Write-Host "ReportName " $ReportName
    return $ReportName 
}

function CheckMachineConnection
{
    param
    (
        [Parameter(Mandatory=$true)]$ComputerName,
		[Parameter(Mandatory=$false)][PSCredential]$Credential
    )

    # add the server to trusted host list if it's not there unless it's localhost
    if ($ComputerName -ne 'localhost') {
        $trusted = (Get-Item WSMan:localhost\client\TrustedHosts).Value -split ','
        if (!($trusted -Contains $ComputerName)) {
            Set-Item WSMan:\localhost\Client\TrustedHosts -Value $ComputerName -Concatenate -Force
        }
    }

    Try {
		if ($Credential) {
           New-CimSession -ComputerName $ComputerName -Credential $Credential -ErrorAction Stop
		} else {
           New-CimSession -ComputerName $ComputerName -ErrorAction Stop
		}
        return $true
    }
    catch {
        return $false    #$_.Exception.Message
    }
}

function TestSqlConnection 
{
    param(
        [Parameter(Mandatory=$true)][string]$ServerName,
        [Parameter(Mandatory=$true)][string]$Instance,
        [Parameter(Mandatory=$true)][string]$Port,
        [Parameter(Mandatory=$false)][string]$User,
        [Parameter(Mandatory=$false)][string]$Password
    )
    try {
        If ($Instance -eq 'default') {
            $Instance = ""
        }
        If ($Port -eq 'default') {
            $ServerName = "$ServerName\$Instance"
        } else {
            $ServerName = "$ServerName,$Port\$Instance"
        }
        If ($User) {
            #Write-Host "Invoke-Sqlcmd -ServerInstance " $ServerName " -Username " $User " -Password " $Password " -Database 'master' -Query 'Select GetDate()'"
            Invoke-Sqlcmd -ServerInstance $ServerName -Username $User -Password $Password -Database 'master' -Query "Select GetDate()"
        } else {
            #Write-Host "Invoke-Sqlcmd -ServerInstance " $ServerName " -Database 'master' -Query 'Select GetDate()'"
            Invoke-Sqlcmd -ServerInstance $ServerName -Database 'master' -Query "Select GetDate()"
        }
        $true
    } catch {
        #Write-Host "Connection to server $ServerName failed"
        $false
    }
}

function ComposeDbConnection
{
    param
    (
        [Parameter(Mandatory=$true)]$ServerList,
		[Parameter(Mandatory=$false)][switch]$Master = $false         # master only
    )

    $dbConnectList = $null

    # Write-Host "ServerList: ", $ServerList
    # Compose data connection string 
    # loop through each SQL Server instance
    foreach ($server in $ServerList) {
        # Write-Host "server: " $server
        $sqlServer = $server.Host
        if ($server.Port -and $server.Port -ne 'default') {
            $sqlServer = $server.Host +"," + $server.Port
        } elseif ($server.Instance -and $server.Instance -ne 'default') {
            # it appears instance name is not required as long as port # is setttled
            $sqlServer = $sqlServer + "\" + $server.Instance
        }
        Write-Host "sqlServer: " $sqlServer

        if ($AssessType -eq 'ssis') {
            $dbList = @("SSISDB")
        } elseif ($Master) {
            $dbList = @("master")
        } else {
            if ($server.DBlist -eq '*') {
                # get all database names except system databases
                if ($server.SqlUser) {
                    $dbName = Invoke-Sqlcmd -ServerInstance $sqlServer -Username $server.SqlUser -Password $server.SqlPassword -Database 'master' -Query "Select name from sys.databases where name not in ('master','model','msdb','tempdb')"
                } else {
                    $dbName = Invoke-Sqlcmd -ServerInstance $sqlServer -Database 'master' -Query "Select name from sys.databases where name not in ('master','model','msdb','tempdb')"
                }
                # Write-Host "dbList: " $dbName.name
                $dbList = $dbName.name
            } else {
                # convert database list into an array
                $dbList = $server.DBlist -split ','
            }
        }

        # loop through each database
        foreach ($db in $dbList) {
            $dbName = $db.Trim()
            If ($server.User) {
                $dbConnectList += """Server=" + $sqlServer + ";Integrated Security=False;User Id=" + $server.SqlUser + ";Password=" + $server.SqlPassword + ";Initial Catalog=" + $dbName + """ "
            } else {
                $dbConnectList += """Server=" + $sqlServer + ";Integrated Security=True;Initial Catalog=" + $dbName + """ "
            }
        }
    }

    return $dbConnectList
}

function ComposeSku
{
   # compose SKU recommendation command
   $cmd = ".\DmaCmd.exe /Action=SkuRecommendation /SkuRecommendationInputDataFilePath=""" + $CountFile
   $cmd += """ /SkuRecommendationTsvOutputResultsFilePath=""" + $outputTsvFile
   $cmd += """ /SkuRecommendationJsonOutputResultsFilePath=""" + $outputJsonFile
   $cmd += """ /SkuRecommendationOutputResultsFilePath=""" + $outputHtmlFile
   $cmd += """ /SkuRecommendationPreventPriceRefresh=true /AzureAuthenticationInteractiveAuthentication=true"
   $cmd += " /SkuRecommendationCurrencyCode=""" + $CurrencyCode
   $cmd += """ /SkuRecommendationOfferName=""" + $OfferName
   $cmd += """ /SkuRecommendationRegionName=""" + $RegionName
   $cmd += """ /SkuRecommendationSubscriptionId=""" + $SubscriptionId
   $cmd += """ /AzureAuthenticationTenantId=""" + $TenantId
   $cmd += """ /AzureAuthenticationClientId=""" + $ClientId + '"'

   # Database names must be provided
   if ($DatabaseNames -and $DatabaseNames -ne '*') {
      $cmd += " /SkuRecommendationDatabasesToRecommend=" + $DatabaseNames
   }

   Return $cmd
}

function CheckInvokeExpression
{
    param
    (
        [Parameter(Mandatory=$true)][PSObject]$OutputMessage
    )

    $message = [string]$OutputMessage.get_SyncRoot()
    if ($message.Contains('Exception type')) {
        #Write-Host "Exception, Exception, Exception!!!!!!!!!!!!!!!!!"
        Return "Error " + $message
    }
    Return $message
}

#$inputServer = Import-Csv -Path $InputFile
#$inputServer
if ($InputFile) {
    $serverList = StandardizeInput $InputFile
}

if ($ValidateHost -or $ValidateBoth) {
   foreach ($server in $serverList) {
     $serverHost = $server.Host
     if ($server.Host -and $server.User) {
        $PWord = ConvertTo-SecureString -String $server.Password -AsPlainText -Force
        $Credential = New-Object -TypeName "System.Management.Automation.PSCredential" -ArgumentList $server.User,$PWord
        $result = CheckMachineConnection -ComputerName $serverHost -Credential $Credential
     } else {
        $result = CheckMachineConnection -ComputerName $serverHost
     }
     if (!$result) {
        throw "connection to $serverHost failed."
     }
   }
   Return $true
}

if ($ValidateSql -or $ValidateBoth) {
   foreach ($server in $serverList) {
     $serverHost = $server.Host
     if (TestSqlConnection -ServerName $serverHost -Instance $server.Instance -Port $server.Port -User $server.SqlUser -Password $server.SqlPassword) {
        Write-Host "SQL Connection to server " $serverHost " is good"
     } else {
        Write-Host "SQL Connection to server " $serverHost " is failed"
        throw "SQL connection to $serverHost failed."
     }
   }
   Return $true
}

# set default assessment type
if (!$AssessType) {
    $AssessType = "both"
} else {
    $AssessType = $AssessType.ToLower()
}


# Set report folder & name
$finalReport = CheckOutput #$OutputFolder $ReportName
Write-Host "finalReport " $finalReport

# set target platform
if (!$Target) {
   $Target = "AzureSqlDatabase"
} else {
   switch ($Target.ToLower()) {
      'sqlmi' {$Target = "ManagedSqlServer"}
      'sqldb' {$Target = "AzureSqlDatabase"}
      'sqlserver2012' {$Target = "SqlServer2012"}
      'sqlserver2014' {$Target = "SqlServer2014"}
      'sqlserver2016' {$Target = "SqlServer2016"}
      'sqlserverlinux2017' {$Target = "SqlServerLinux2017"}
      'sqlserverwindows2017' {$Target = "SqlServerWindows2017"}
      'sqlserverlinux2019' {$Target = "SqlServerLinux2019"}
      'sqlserverwindows2019' {$Target = "SqlServerWindows2019"}
   }
}
Write-Host "Target: " $Target

if (!$DmaHome) {
    $DmaHome = "C:\Program Files\Microsoft Data Migration Assistant"
}

$savedPath = Get-Location
Write-Host "Current location: " $savedPath

if ($AssessType -eq 'workload' -or $AssessType -eq 'workloadsku') 
{
   $ResultFolder = CheckOutput -FolderOnly
   # Write-Host "Result folder: " $ResultFolder
   $dbConnectionString = ComposeDbConnection $serverList -Master

   # remove any completed job in the system
   Invoke-Expression "Get-Job | Where-Object State -eq 'Completed' | Remove-Job"
   $loc = 0
   foreach ($db in ($dbConnectionString -split ' +(?=(?:[^\"]*\"[^\"]*\")*[^\"]*$)')) {
      if ($db) {
         # Write-Host "SQL Connection to server " $server.Host " db connection string: " $db
         $hostName = $serverList[$loc].Host
         $hostUser = $serverList[$loc].User
         $hostPassword = $serverList[$loc].Password
         $loc += 1
         if ($savedPath) {
            $cmd = "$savedPath\CpgSSPerfCountCollection.ps1" + " -ComputerName $hostName"
            if ($hostUser) {
               $cmd += " -ComputerUser $hostUser -ComputerPassword $hostPassword"
            }
            if ($WorkloadTime -lt 240) {
               $WorkloadTime = 240
            }
            $cmd += " -OutputFilePath """ + $ResultFolder + "\workload-" + $hostName + ".csv""" + " -CollectionTimeInSeconds $WorkloadTime"
            $cmd += " -DbConnectionString $db"
            Write-Host "cmd: " $cmd
            # Start-Job -Name $hostName -ScriptBlock { Invoke-Expression $cmd }
            Start-Job -Name $hostName -ScriptBlock { Param([string]$cmd)  Invoke-Expression $cmd } -ArgumentList $cmd

            #$job = Start-Job -Name $hostName -ScriptBlock { Param([string]$cmd)  Invoke-Expression $cmd } -ArgumentList $cmd
            #Wait-Job -Id $job.Id
            #$job | Receive-Job -Keep
         } else {
            # CpgSSPerfCountCollection.ps1 does not exist
            Write-Host "script CpgSSPerfCountCollection.ps1 does NOT exist in current folder. Please rerun the script from the right place."
            Return "Error: script CpgSSPerfCountCollection.ps1 does NOT exist in current folder."
         }
      }
   }

   Write-Host "collecting for $WorkloadTime seconds ..."
   # add 10 seconds for preprocessing
   $WorkloadTime += 10
   Start-Sleep -Seconds $WorkloadTime
   $receivedJobs = Get-Job | Where-Object State -eq 'Completed'
   # Write-Host "loc: " $loc
   # Write-Host "receivedJobs.Count: " $receivedJobs.Count
   $extendedTime = 0    # extend collecting time for 10 minutes more than specified for any unexpected event
   while ($receivedJobs.Count -lt $loc -and $extendedTime -lt 60) {
      Start-Sleep -Seconds 10
      $receivedJobs = Get-Job | Where-Object State -eq 'Completed'
      Write-Host "receivedJobs.Count: " $receivedJobs.Count
      $extendedTime += 1
   }
   #$job | Receive-Job -Keep

   Write-Host "Workload collection completed."

   # If it's WorkloadSku, continue
   if ($AssessType -eq 'workload') {
      Return "successful"
   }
}

cd $DmaHome


if ($AssessType -eq 'sku' -or $AssessType -eq 'workloadsku') 
{
   $ResultFolder = CheckOutput -FolderOnly
   # Write-Host "Result folder: " $ResultFolder

   # subscription ID must be provided
   if (!$SubscriptionId) {
      Return "Error: Subscription ID must be provided"
   }

   # Tenant ID must be provided
   if (!$TenantId) {
      Return "Error: Tenant ID must be provided"
   }

   # Client ID must be provided
   if (!$ClientId) {
      Return "Error: Client ID must be provided"
   }

   $returnHtml = ""
   if ($AssessType -eq 'sku')
   {
       # performance counter file must be provided
       if (!$CountFile) {
          Return "Error: Performance counter file must be provided"
       } elseif (!(Test-Path $CountFile)) {
          Write-Host 
          Return "Error: Performance counter file $CountFile does not exist. Please check file path and name"
       }

       # Set output file names
       $outputTsvFile = $OutputFolder + "\prices-" + $AssessName + ".tsv"
       $outputJsonFile = $OutputFolder + "\prices-" + $AssessName + ".json"
       $outputHtmlFile = $OutputFolder + "\prices-" + $AssessName + ".html"
       $returnHtml = "prices-" + $AssessName + ".html"

       $cmdSku = ComposeSku
       Write-Host $cmdSku
       #Invoke-Expression $cmdSku
       $output = Invoke-Expression $cmdSku
   } else {

       foreach ($server in $serverList) {
           $hostName = $server.Host
           $dbNames = $server.DBlist
           
           # check counter file
           $CountFile = "$ResultFolder" + "\workload-" + $hostName + ".csv"
           Write-Host "check counter file: " Test-Path -Path $CountFile
           
           if (!(Test-Path -Path $CountFile)) {
              Write-Host "Performance counter file $CountFile does not exist. Please check file path and name."
              Return "Error: Performance counter file $CountFile does not exist. Please check file path and name."
           }
           
           # Set output file names
           $outputTsvFile = $OutputFolder + "\prices-" + $hostName + ".tsv"
           $outputJsonFile = $OutputFolder + "\prices-" + $hostName + ".json"
           $outputHtmlFile = $OutputFolder + "\prices-" + $hostName + ".html"
           $returnHtml += "prices-" + $hostName + ".html" + ' '

           # Database names must be provided
           if (!$dbNames -or $dbNames -eq '*') {
              $DatabaseNames = "*"
           } else {
              $DatabaseNames = ""
              foreach ($db in ($dbNames -split ',')) {
                  $DatabaseNames += ' "' + $db.Trim() + '"'
                  #Write-Host "db: " $db
                  #Write-Host "DatabaseNames: " $DatabaseNames
              }
           }

           $cmdSku = ComposeSku
           Write-Host $cmdSku
           $output = Invoke-Expression $cmdSku
       }

   }
   cd $savedPath
   Write-Host "returnHtml: " $returnHtml
   $result = CheckInvokeExpression $output
   if ($result.Substring(0, 5) -eq "Error") {
      return $result
   } else {
      return $returnHtml
   }

}

$dbConnectionString = ComposeDbConnection $serverList

#$cmd = ".\DmaCmd.exe /AssessmentName=""" + $AssessName+""" /AssessmentTargetPlatform=""" + $Target + """ /AssessmentResultDma=""" + "$finalReport.dma" + """ /AssessmentResultJson=""" + "$finalReport.json" + '"'
$cmd = ".\DmaCmd.exe /AssessmentName=""" + $AssessName+""" /AssessmentTargetPlatform=""" + $Target + """ /AssessmentResultJson=""" + "$finalReport.json" + '"'
Switch ($AssessType)
{
    'feature' {$cmd +=  " /AssessmentResultDma=""" + "$finalReport.dma" + """  /AssessmentEvaluateFeatureParity /AssessmentDatabases=" + $dbConnectionString}
    'compat' {$cmd +=  " /AssessmentResultDma=""" + "$finalReport.dma" + """  /AssessmentEvaluateCompatibilityIssues /AssessmentDatabases=" + $dbConnectionString}
    'evaluate' {$cmd +=  " /AssessmentResultDma=""" + "$finalReport.dma" + """  /AssessmentEvaluateRecommendations /AssessmentDatabases=" + $dbConnectionString}
    'both' {$cmd +=  " /AssessmentResultDma=""" + "$finalReport.dma" + """  /AssessmentEvaluateFeatureParity /AssessmentEvaluateCompatibilityIssues /AssessmentDatabases=" + $dbConnectionString}
    'ssis' {$cmd +=  " /AssessmentType=IntegrationServices /AssessmentEvaluateCompatibilityIssues /AssessmentDatabases=" + $dbConnectionString}
    default {"Unknow Action: $AssessType"}
}
Write-Host $cmd
$output = Invoke-Expression $cmd
cd $savedPath
#Write $output
#Write-Host "This is the end of catas.ps1"
# check Invoke-experssion output messages for any exception
Return CheckInvokeExpression $output





