<#
Disclaimer:
This sample script is not supported under any Microsoft standard support program or service.
The sample script is provided AS IS without warranty of any kind. Microsoft further disclaims
all implied warranties including, without limitation, any implied warranties of merchantability
or of fitness for a particular purpose. The entire risk arising out of the use or performance of
the sample scripts and documentation remains with you. In no event shall Microsoft, its authors,
or anyone else involved in the creation, production, or delivery of the scripts be liable for any
damages whatsoever (including, without limitation, damages for loss of business profits, business
interruption, loss of business information, or other pecuniary loss) arising out of the use of or
inability to use the sample scripts or documentation, even if Microsoft has been advised of the
possibility of such damages
#>
<#
.Synopsis
    This script generates a csv file of the Exchange Configuration for Exchange Security Insight project.
.DESCRIPTION
    This script has to be scheduled to generate a CSV file of the Exchange configuration that will be imported into Sentinel by ALA Agent.
    Multiple Exchange Cmdlets are used to extract information.

.EXAMPLE
.INPUTS
    .\CollectExchSecIns.ps1
        
.OUTPUTS
    The output a csv file of collected data
.NOTES
    Developed by ksangui@microsoft.com and Nicolas Lepagnez
    Version : 6.2 - Released : ? - nilepagn
        - Possibility to use Log Analytics API and CSV in same time.

    Version : 6.1.1 - Released : 24/08/2022 - nilepagn
        - Correcting bug on multithreading.
        - Version published on On-Premises testing environment and validated.

    Version : 6.1 - Released : 24/08/2022 - nilepagn
        - Adding ESIEnvironment column in entries adding the possibility to audit multiple On-Premises and Online Exchange configuration

    Version : 6.0.1 - Released : 24/08/2022 - nilepagn
        - Bug on Write-LogMessage during function loading.
        
    Version : 6.0 - Released : 24/08/2022 - nilepagn
        - Merge of On-Premises version and Cloud Version of ESI Collector
        - Deactivate the possibility to launch multi-threading in Azure Automation
        - Add "ESIProcessingType":"Online" in Global Section of JSON File. The value can be "Online" or "On-Premises"
        - Add "ProcessingCategory":"All" for Audit Functions. The value can be "All", "Online" or "On-Premises"
        - Reorganization of functions in the code by category

    Version : 5.0 - Released : 24/08/2022 - nilepagn
        - Version Cloud with autonomous Azure Log Monitor loading. No more dependant of a script.
        - Be able to work on an Azure Automation Runbook
        - Connect Exchange Online to retrieve Information

    Version : 4.2 - Released : 15/08/2022 - Nilepagn
        - Adding an automous Sentinel log upload mechanism to be able to be independant from Log Analytics Agents.
            The Upload-AzMonitorLog Script is needed and can be installed here : https://www.powershellgallery.com/packages/Upload-AzMonitorLog
            The system needs to be explicitally enabled in the config file with the Sentinel Workspace Id and Workspace

    Version : 4.1 - Released : 15/08/2022 - Nilepagn
        - Testing Function transfert into JSON File
        - Adding possibility to activate only specific function of to deactivate a specific function
            => "Deactivated":"false" on function level
            => "OnlyExplicitActivation":"True" on "Advanced" level + "ExplicitActivation":"true" on function level
        - Adding Default Exchange Path on JSON Config
        - Transforming all the parallelism system to use Runspace on multi-threading
        - Adding the possibility to explicitally fill Exchange Server list to use
        - Insert multiple variables that can be used on functions : 
            "#LastDateTracking#" = $script:LastDateTracking; 
            "#ForestDN#" = $script:ForestDN; 
            "#ForestName#" = $script:ForestName; 
            "#ExchOrgName#" = $script:ExchOrgName; 
            "#GCRoot#" = $script:GCRoot;
            "#GCServer#" = $script:gc;
            "#SIDRoot#" = $script:sidroot;

    Version : 4.0 - Released : 02/08/2022 - Nilepagn
        - Transfering Configuration of functions in the JSON File [NOT TESTED]
    Version : 3.0 - Released : 27/03/2022 - Nilepagn
        - Refactorization for parallelism in function execution.
        - Possibility to redirect result on another file
        - Possibility to use a date of last execution.
        - Configuration file creation for variables
    Version : 2.8 - Released : 24/06/2022
        - Add Exch CU/SU
    Version : 2.7 - Released : 24/03/2022
        - Add Search-MailboxAuditlog
        - Add DatabaseAvailabilityGroup
    Version : 2.6 - Released : 17/03/2022
        - Add ReceiveConnector : AuthMecnismstring and Permissions Group string
        - ExchangeServer : AdminDisplayVersion
        -Transport Rule SentoString,CopytoString,RedirecttoString,BlindCopyToString
    Version : 2.5 - Released : 17/03/2022
        - Add Logon and Last PwdSet as String for ADGroup
        - Correct bug on ParentGroup
    Version : 2.4 - Released : 16/03/2022
        - Bug on Local Administrators group with Domain user
        - Add Service Status of POP and IMAP
    Version : 2.3 - Released : 10/03/2022
        - Add Select Expression on few attributes where String is needed. Like User, Rights
    Version : 2.2 - Released : 24/02/2022
        - Adding Business Logic to process Management Role direct assignments
    Version : 2.1 - Released : 11/02/2022
        - Adding Business Logic to process WMI User/Group Information
        - Correct a bug on Transform for each object switch
        - Align Member object properties to have same information
    Version : 2.0 - Released : 11/02/2022
        - Adding Tranformation Function possibility before injecting data
        - Adding Group Hierarchy Calculation
    Version : 1.3 - Released : 04/01/2021
        - Adding Exchange Server information
        - Adding Mailbox Database Information
        - Correct Bug on Section Name where Space at the end was present
    Version : 1.2 - Released : 31/12/2021
        - Modify header of the file to add script information.
        - Adding Logs generation
        - Adding a Cleaning function for log and data csv file
        - Adding CSV file with date
        - Introduce a Configuration Instance ID and a Generation Date in CSV

    Version : 1.1 - Released : 10/12/2021
        - Generates only 1 CSV file with standard column for all cmdlets
    
#>

Param (
    [String] $JSONFileCondiguration = "CollectExchSecConfiguration.json",
    [System.Int32] $ClearFilesOlderThan = 7,
    [switch] $ForceOutputWithoutDate,
    [Parameter(Mandatory=$false,HelpMessage="Specify if a PowerhShell session is connected to an Exchange 2010")]
    $EPS2010=$false,
    [switch] $NoDateTracing
)

#region Exchange & AD Connection Management

    function Connect-ESIExchangeOnline
    {
        Param (
            $TenantName
        )

        if ($Global:isRunbook)
        {
            $Session = Get-AutomationConnection -Name AzureRunAsConnection
            Connect-ExchangeOnline -CertificateThumbprint $Session.CertificateThumbprint -AppId $Session.ApplicationID -ShowBanner:$false -Organization $TenantName
        }
        else {
            Connect-ExchangeOnline
        }
    }
        
    Function Get-ExchangeServerList
    {
        Param(
            $EPS2010,
            [switch] $Parallel,
            $ServerList = $null,
            [switch] $BypassTest
        )

        if ($BypassTest) {$Parallel = $false}

        if ($null -eq $ServerList)
        {
            $servers= get-exchangeserver
        }
        else 
        {
            Write-Host "Server list restricted to list in config file"
            $servers = @()
            foreach ($targetServer in $ServerList)
            {
                $servers += Get-ExchangeServer -Identity $targetServer
            }
        }

        #Check and Count theservers for each version
        $ExchangeServerConfig = [PSCustomObject]@{
                    ListSRVUp = @();
                    ListSRVDown = @();
                    exch2010 = @();
                    exch2013 = @();
                    exch2016 = @();
                    exch2019 = @();
                    $EPS2010 = $EPS2010
                }
        
        $servers = $servers | Sort-Object Name
        $JobList = @()

        foreach ($srv in $servers)
        {
            if (-not $BypassTest)
            {
                if (-not $Parallel) 
                {
                    Write-Host "Test server $srv"
                    $srvstatus = Test-Connection -ComputerName $srv -Protocol wsman -Quiet
                    if ($srvstatus)
                    {
                        $ExchangeServerConfig.ListSRVUp += $srv.name
                    }
                    else {
                        $ExchangeServerConfig.ListSRVDown += $srv.name
                    }
                }
                else
                {
                    $StartAnalysis = Get-Date
                    $countRunning = Get-Job -Name "TestConn*" | Where-Object {$_.State -eq "Running"}
                    while ($countRunning.Count -ge $script:MaxParallel)
                    {
                        if (((Get-Date) - $StartAnalysis).Minute -gt $Script:ParallelTimeout) 
                        {
                            $Timeout = $true; 
                            $countRunning | Stop-Job
                            break;
                        }
                        Write-Host "$($countRunning.count) jobs running, max $($script:MaxParallel) - Wait $($Script:ParralelPingWaitRunning) Seconds"
                        Start-Sleep -Seconds $Script:ParralelPingWaitRunning  
                        $countRunning = Get-Job -Name "TestConn*" | Where-Object {$_.State -eq "Running"}
                    }
                    
                    Write-Host "Test server $srv as job"
                    $JobList += Start-Job -ScriptBlock {$srvstatus = Test-Connection -ComputerName $args[0] -Protocol wsman -Quiet; return $srvstatus} -ArgumentList $srv -Name "TestConn$($srv.name)"
                }
            }
            else 
            { 
                Write-Host "Server availability check bypassed. Adding $($srv.name) as available"
                $ExchangeServerConfig.ListSRVUp += $srv.name 
            }

            If ($srv.AdminDisplayVersion -like "*14.*")
            {
                $ExchangeServerConfig.exch2010 += $srv.name
            }
            elseif ($srv.AdminDisplayVersion -like "*15.0*")
            {
                $ExchangeServerConfig.exch2013 += $srv.name
            }
            elseif ($srv.AdminDisplayVersion -like "*15.1*")
            {
                $ExchangeServerConfig.exch2016 += $srv.name
            }
            elseif ($srv.AdminDisplayVersion -like "*15.2*")
            {
                $ExchangeServerConfig.exch2019 += $srv.name
            }
        }

        if ($Parallel)
        {
            $DoneList = @()
            $NoJob = $false
            $StartAnalysis = Get-Date
            $Timeout = $false
            $runningJobs = $JobList.count

            Write-Host "Process Test Server Jobs"
            while ($runningJobs -gt 0 -and -not $Timeout)
            {
                if (((Get-Date) - $StartAnalysis).Minute -gt $Script:ParallelTimeout) {$Timeout = $true}
                $runningJobs = 0
                foreach ($job in $JobList)
                {
                    if ($job.Name -notin $DoneList)
                    {
                        $status = Get-Job $job.Id
                        $SrvName = $job.Name -replace 'TestConn',""

                        if ($status.State -eq "Running") 
                        {
                            if (-not $Timeout) { $runningJobs += 1 }
                            else {
                                Write-Host "Process $SrvName failed job due to Timeout"
                                $ExchangeServerConfig.ListSRVDown += $SrvName
                                $DoneList += $job.Name
                                Remove-Job $job
                            }
                        }
                        else
                        {
                            Write-Host "Process $SrvName completed job"
                            $Result = Receive-Job $job
                            if ($Result)
                            {
                                $ExchangeServerConfig.ListSRVUp += $SrvName
                            }
                            else {
                                $ExchangeServerConfig.ListSRVDown += $SrvName
                            }
                            $DoneList += $job.Name
                            Remove-Job $job
                        }
                    }
                }
                if ($runningJobs -gt 0)
                {
                    Write-Host "$runningJobs Test Server availability jobs running. Wait $($Script:ParralelPingWaitRunning) seconds"
                    Start-Sleep -Seconds $Script:ParralelPingWaitRunning
                }
            }
        }

        Write-Host "List of current servers that respond to ping" $ExchangeServerConfig.ListSRVUp -ForegroundColor magenta
        Write-Host "List of current servers that are unavailable" $ExchangeServerConfig.ListSRVDown -ForegroundColor red

        #Check if the parameter EPS2010 has set to true when launching the script or there is no Exchange server other than Exchange 2010. Some tasks will be adapt depending of powershell version
        If (($ExchangeServerConfig.exch2013+$ExchangeServerConfig.exch2016+$ExchangeServerConfig.exch2019) -eq 0  -or $EPS2010 -eq $true  )
        {
            $ExchangeServerConfig.EPS2010 = $true
        }
        return $ExchangeServerConfig
    }

    Function Get-ADInfo
    {
        #Check if the Active Directory module is install if not remote session to a DC

        #Retrieve AD info
        $forest = [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest()
        $forest_context = [System.DirectoryServices.ActiveDirectory.DirectoryContext]::new("forest",$forest)
        $gc= $forest.NamingRoleOwner.name
        $config = ([ADSI]"LDAP://RootDSE").configurationNamingContext.Value

        #for each of the domains get the netbios name and locate the closest DC
        $forest.Domains.Name | ForEach-Object `
        {
            $domain_name = $_
            $domain_context = [System.DirectoryServices.ActiveDirectory.DirectoryContext]::new("domain",$domain_name)
            $domain_dc_fqdn = ([System.DirectoryServices.ActiveDirectory.DomainController]::findOne($domain_context)).Name

            #Only the config partition has the netbios name of the domain
            $config = ([ADSI]"LDAP://RootDSE").configurationNamingContext.Value
            $config_search = [System.DirectoryServices.DirectorySearcher]::new("LDAP://CN=Partitions,$config","(&(dnsRoot=$domain_name)(systemFlags=3))","nETBIOSName",1)
            $domain_netbios = $($config_search.FindOne().Properties.netbiosname)
            $script:ht_domains[$domain_netbios] = @{
                    DCFQDN = $domain_dc_fqdn
                    DomainFQDN = $domain_name
                    #JustAdd
                    DomainDN = (Get-ADDomain $domain_context.name).DistinguishedName
                }
        }
        $installmodule = Get-Module -ListAvailable | select-string  "ActiveDirectory"
        if ($installmodule -notlike "*ActiveDirectory*")
        {
            $adsession = new-pssession -computername $gc
            Import-pssession -session $adsession -module ActiveDirectory
        }
        $forestDN =($forest.Schema| ForEach-Object {$_ -replace ("CN=Schema,CN=Configuration,","")})
        $SIDRoot=(Get-ADDomain $forestDN).domainSID.value
        Return $forest, $forestDN, $gc, $SIDRoot
    }

#endregion Exchange & AD Connection Management

#region Time Management

    function Get-LastLaunchTime
    {
        if ($Global:isRunbook)
        {
            $script:LastDateTracking = Get-AutomationVariable -Name LastDateTracking

            if ([String]::IsNullOrEmpty($script:LastDateTracking) -or $script:LastDateTracking -like "Never")
            {
                $script:LastDateTracking = (Get-Date).AddDays($Script:DefaultDurationTracking * -1)
            }
            else {
                $script:LastDateTracking = Get-Date  $script:LastDateTracking
            }
        }
        else {
            if (Test-Path ((Split-Path $outputpath) + "\DateTracking.esi"))
        {
            $script:LastDateTracking = Get-Date (Get-Content ((Split-Path $outputpath) + "\DateTracking.esi"))
        }
        else
        {
            $script:LastDateTracking = (Get-Date).AddDays($Script:DefaultDurationTracking * -1)
        }
        }  
    }

    function Set-CurrentLaunchTime
    {
        if ($Global:isRunbook)
        {
            Set-AutomationVariable -Name LastDateTracking -Value $DateSuffix.ToString()
        }
        else { $DateSuffix | Set-Content ((Split-Path $outputpath) + "\DateTracking.esi") }
    }

#endregion Time Management

#region Log and file Management
    function Write-LogMessage {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$true)]
            [string]
            $Message,
            [Parameter(Mandatory=$false)]
            [string]
            $Category="General",
            [Parameter(Mandatory=$false)]
            [ValidateSet("Info","Warning","Error","Verbose")]
            [string]
            $Level="Info",
            [switch] $NoOutput
        )
        $line = "$(Get-Date -f 'yyyy/MM/dd HH:mm:ss')`t$Level`t$Category`t$Message"
        Set-Variable -Name UDSLogs  -Value "$UDSLogs`n$line" -Scope Script
        if($NoOutput -or $Global:DeactivateWriteOutput){
            Write-Host $line
            if ($script:FASTVerboseLevel) { Write-Verbose $line }
        }else{
            Write-Output $line
        }
        switch ($Level) {
            "Verbose" {
                if ($script:FASTVerboseLevel) { Write-Verbose "[VERBOSE] $Category :`t$Message" }
            }
            "Info" {
                Write-Information "[INFO] $Category :`t$Message"
            }
            "Warning" {
                Write-Warning "$Category :`t$Message"
            }
            "Error" {
                Write-Error "$Category :`t$Message"
            }
            Default {}
        }    
    }

    function Get-UDSLogs
    {
        [CmdletBinding()]
        param()

        return $Script:UDSLogs
    }

    function CleanFiles
    {
        Param(
            $ClearFilesOlderThan,
            $ScriptLogPath,
            $outputpath
        )

        $DirectoryList = @()
        $DirectoryList += $ScriptLogPath
        $DirectoryList += (Split-Path $outputpath)

        Write-Host "`t ..Cleaning Report and log files older than $ClearFilesOlderThan days."
        $MaxDate = (Get-Date).AddDays($ClearFilesOlderThan*-1)

        $OtherOldFiles = @()
        $FileList = @()
        if ($DirectoryList.count -gt 0)
        {
            foreach ($dir in $DirectoryList)
            {
                if (Test-Path $dir)
                {
                    $OtherPathObj = Get-Item -Path $dir
                    $OtherFiles = $OtherPathObj.GetFiles()
                    $OtherOldFiles = $OtherFiles | Where-Object {$_.LastWriteTime -le $MaxDate}
                    Write-Host ("`t`t There is "+ $OtherFiles.Count + " existing files in $dir with "+ $OtherOldFiles.Count +" files older than $MaxDate.")
                }
                elseif (Test-Path ($scriptFolder + "\" + $dir))
                {
                    $OtherPathObj = Get-Item -Path $dir
                    $OtherFiles = $OtherPathObj.GetFiles()
                    $OtherOldFiles = $OtherFiles | Where-Object {$_.LastWriteTime -le $MaxDate}
                    Write-Host ("`t`t There is "+ $OtherFiles.Count + " existing files in $dir with "+ $OtherOldFiles.Count +" files older than $MaxDate.")
                }
                $FileList += $OtherOldFiles
            }
        }

        $NbRemove = 0
        foreach ($File in $FileList)
        {
            Remove-Item $File.FullName
            $NbRemove += 1
            Write-Host ("`t`t`t File "+ $File.Name + " Removed.")
        }
        
        Write-Host ("`t`t $NbRemove Files Removed for cleaning process.")
    }

#endregion Log and file Management

#region Sentinel Upload Management

    Function Build-Signature ($customerId, $sharedKey, $date, $contentLength, $method, $contentType, $resource)
    {
        $xHeaders = "x-ms-date:" + $date
        $stringToHash = $method + "`n" + $contentLength + "`n" + $contentType + "`n" + $xHeaders + "`n" + $resource

        $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
        $keyBytes = [Convert]::FromBase64String($sharedKey)

        $sha256 = New-Object System.Security.Cryptography.HMACSHA256
        $sha256.Key = $keyBytes
        $calculatedHash = $sha256.ComputeHash($bytesToHash)
        $encodedHash = [Convert]::ToBase64String($calculatedHash)
        $authorization = 'SharedKey {0}:{1}' -f $customerId,$encodedHash
        return $authorization
    }

    Function Post-LogAnalyticsData($customerId, $sharedKey, $body, $logType)
    {
        $method = "POST"
        $contentType = "application/json"
        $resource = "/api/logs"
        $TimeStampField = [DateTime]::UtcNow
        $rfc1123date = [DateTime]::UtcNow.ToString("r")
        $contentLength = $body.Length
        $signature = Build-Signature `
            -customerId $customerId `
            -sharedKey $sharedKey `
            -date $rfc1123date `
            -contentLength $contentLength `
            -method $method `
            -contentType $contentType `
            -resource $resource
        $uri = "https://" + $customerId + ".ods.opinsights.azure.com" + $resource + "?api-version=2016-04-01"

        $headers = @{
            "Authorization" = $signature;
            "Log-Type" = $logType;
            "x-ms-date" = $rfc1123date;
            "time-generated-field" = $TimeStampField;
        }

        #validate that payload data does not exceed limits
        if ($body.Length -gt (31.9 *1024*1024))
        {
            throw("Upload payload is too big and exceed the 32Mb limit for a single upload. Please reduce the payload size. Current payload size is: " + ($body.Length/1024/1024).ToString("#.#") + "Mb")
        }

        Write-LogMessage -Message ("Upload payload size is " + ($body.Length/1024).ToString("#.#") + "Kb")

        try {
            $response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $headers -Body $body -UseBasicParsing
        }
        catch {
            if ($_.Exception.Message.startswith('The remote name could not be resolved'))
            {
                throw ("Error - data could not be uploaded. Might be because workspace ID or private key are incorrect")
            }

            throw ("Error - data could not be uploaded: " + $_.Exception.Message)
        }
        
        # Present message according to the response code
        if ($response.StatusCode -eq 200) 
        { Write-LogMessage  "200 - Data was successfully uploaded" }
        else
        { throw ("Server returned an error response code:" + $response.StatusCode)}
    }
#endregion Sentinel Upload Management

#region Dynamic Cmdlet Management

    #Function to construc list of cmdlet to execute
    function New-Entry
    {
        Param (
            [Parameter(Mandatory=$True)] [String] $Section,
            [Parameter(Mandatory=$True)] [String] $PSCmdL,
            [Parameter(Mandatory=$False)] $Select = @(),
            [Parameter(Mandatory=$False)] [String] $OutputStream = "Default",
            [Parameter(Mandatory=$False)] [String] $TransformationFunction = $null,
            [Parameter(Mandatory=$False)] [Switch] $TransformationForeach,
            [Parameter(Mandatory=$False)] [Switch] $ProcessPerServer
        )

        $Object = New-Object PSObject
        $Object | Add-Member Noteproperty -Name Section -value $Section
        $Object | Add-Member Noteproperty -Name PSCmdL -value $PSCmdL
        $Object | Add-Member Noteproperty -Name OutputStream -value $OutputStream
        $Object | Add-Member Noteproperty -Name Select -value $Select
        $Object | Add-Member Noteproperty -Name TransformationFunction -value $TransformationFunction
        $Object | Add-Member Noteproperty -Name TransformationForeach -value $TransformationForeach
        $Object | Add-Member Noteproperty -Name ProcessPerServer -value $ProcessPerServer
        
        return $Object
    }

    #Function to construct the output file which depend on the section currently processing
    Function GetCmdletExec
    {
        Param(
            $Section,
            $PSCmdL,
            $Select = $null,
            $TransformationFunction = $null,
            [switch] $TransformationForeach,
            $TargetServer = $null
        )
        
        try {
            if ([String]::IsNullOrEmpty($TargetServer))
            {
                Write-LogMessage -Message ("`tLaunch collection of $Section - $PSCmdL - Global Configuration ...")  -NoOutput
                $PSCmdLResult = Invoke-Expression $PSCmdL
            }
            else
            {
                Write-LogMessage -Message ("`tLaunch collection of $Section - $PSCmdL - Per Server Configuration for $TargetServer ...")  -NoOutput
                $PSCmdL = $PSCmdL -replace "#TargetServer#", $TargetServer
                $PSCmdLResult = Invoke-Expression $PSCmdL
            }

            if (-not [String]::IsNullOrEmpty($TransformationFunction))
            {
                if ($TransformationForeach)
                {
                    $ExecutionForEach = @()
                    $intMax = $PSCmdLResult.Count
                    $inc = 0
                    foreach ($resultObject in $PSCmdLResult)
                    {
                        $inc++
                        Write-LogMessage -Message ("`tTransform Foreach $inc/$intMax - $Section - $PSCmdL - With function $TransformationFunction")  -NoOutput
                        $ExecutionForEach += Invoke-Expression ("$TransformationFunction -ObjectInput " + '$resultObject')
                    }
                    $Execution = $ExecutionForEach
                }
                else {
                    Write-LogMessage -Message ("`tTransform $Section - $PSCmdL - With function $TransformationFunction")  -NoOutput
                    $Execution = Invoke-Expression ("$TransformationFunction -ObjectInput " + '$PSCmdLResult')
                }   
            }
            else 
            {
                $Execution = $PSCmdLResult
            }

            if (-not [String]::IsNullOrEmpty($select))
            {
                Write-LogMessage -Message ("`tSelect Attribute $Section - $PSCmdL - With list $select")  -NoOutput
                $Execution = $Execution | Select-Object $select | Sort-Object $select[0]
            }

            if ($null -ne $Execution) {
                Write-LogMessage -Message ("`t`t Generate Result ...")  -NoOutput
                $Object = New-Result -Section $Section -PSCmdL $PSCmdL -CmdletResult $Execution -EntryDate $Script:DateSuffix -ScriptInstanceID $Script:ScriptInstanceID
            }
            else {
                Write-LogMessage -Message ("`t`t Generate empty result ...")  -NoOutput
                $Object = New-Result -Section $Section -PSCmdL $PSCmdL -EmptyCmdlet -EntryDate $Script:DateSuffix -ScriptInstanceID $Script:ScriptInstanceID
            }
        }
        catch {
            $Object = New-Result -Section $Section -PSCmdL $PSCmdL -ErrorText $_.Exception -EntryDate $Script:DateSuffix -ScriptInstanceID $Script:ScriptInstanceID
            Write-LogMessage -Message ("`t`t Error during data collection - $($_.Exception)")  -NoOutput -Level Error
        }
        
        Write-LogMessage -Message ("`tEnd Cmdlet Collection")  -NoOutput
        return $Object
    }
    function New-Result
    {
        Param (
            [Parameter(Mandatory=$True)] [String] $Section,
            [Parameter(Mandatory=$True)] [String] $PSCmdL,
            [Parameter(Mandatory=$True,ParameterSetName = 'Success')] $CmdletResult,
            [Parameter(Mandatory=$True,ParameterSetName = 'Empty')] [switch] $EmptyCmdlet,
            [Parameter(Mandatory=$True,ParameterSetName = 'Failure')] $ErrorText,
            [Parameter(Mandatory=$False)] [String] $EntryDate = $null,
            [Parameter(Mandatory=$False)] [String] $ScriptInstanceID = $null
        )

        if ([String]::IsNullOrEmpty($EntryDate)) { $EntryDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"}

        $ObjectList = @()

        if ($EmptyCmdlet -or -not [String]::IsNullOrEmpty($ErrorText))
        {
            $Object = New-Object PSObject
            $Object | Add-Member Noteproperty -Name GenerationInstanceID -value $ScriptInstanceID
            $Object | Add-Member Noteproperty -Name ESIEnvironment -value $Script:ESIEnvironmentIdentification
            $Object | Add-Member Noteproperty -Name EntryDate -value $EntryDate
            $Object | Add-Member Noteproperty -Name Section -value $Section
            $Object | Add-Member Noteproperty -Name PSCmdL -value $PSCmdL
            $Object | Add-Member Noteproperty -Name Name -value $null
            $Object | Add-Member Noteproperty -Name Identity -value $null
            $Object | Add-Member Noteproperty -Name WhenCreated -value $null
            $Object | Add-Member Noteproperty -Name WhenChanged -value $null
        
            if ($EmptyCmdlet)
            {
                $Object | Add-Member Noteproperty -Name ExecutionResult -value "EmptyResult"
                $Object | Add-Member Noteproperty -Name rawData -value "{'Error':'EmptyResult'}"
            }
            else {
                $Object | Add-Member Noteproperty -Name ExecutionResult -value "Error"
                $ErrorText = $ErrorText -replace "`r`n", " "
                $Object | Add-Member Noteproperty -Name rawData -value "{'Error':'ExecutionException','ErrorDetail':'$ErrorText'}"
            }
            $ObjectList += $Object
        }
        else {
            $inc = 0
            foreach ($Entry in $CmdletResult)
            {
                $inc++
                Write-LogMessage -Message ("`t`t Generate result $inc/$($CmdletResult.count) ...")  -NoOutput
                $Object = New-Object PSObject
                $Object | Add-Member Noteproperty -Name GenerationInstanceID -value $ScriptInstanceID
                $Object | Add-Member Noteproperty -Name ESIEnvironment -value $Script:ESIEnvironmentIdentification
                $Object | Add-Member Noteproperty -Name EntryDate -value $EntryDate
                $Object | Add-Member Noteproperty -Name Section -value $Section
                $Object | Add-Member Noteproperty -Name PSCmdL -value $PSCmdL
                $Object | Add-Member Noteproperty -Name Name -value $Entry.Name
                $Object | Add-Member Noteproperty -Name Identity -value $Entry.Identity
                $Object | Add-Member Noteproperty -Name WhenCreated -value $Entry.WhenCreated
                $Object | Add-Member Noteproperty -Name WhenChanged -value $Entry.WhenChanged
                $Object | Add-Member Noteproperty -Name ExecutionResult -value "Success"
            
                # Compile other Attributes
                $Object | Add-Member Noteproperty -Name rawData -value ($Entry | ConvertTo-Json -Compress)

                $ObjectList += $Object
            }
        }

        
        return $ObjectList
    }

#endregion Dynamic Cmdlet Management

#region Multithreading Management

    function New-JobEntry
    {
        Param (
            [Parameter(Mandatory=$True)] $Entry,
            [Parameter(Mandatory=$True)] $Job,
            [Parameter(Mandatory=$True)] $JobName,
            [Parameter(Mandatory=$True)] $RealCmdlet,
            [Parameter(Mandatory=$false)] $TargetServer = "",
            [Parameter(Mandatory=$True)] $PSInstance,
            [Parameter(Mandatory=$true)] $RunspaceName
        )

        $Object = New-Object PSObject
        $Object | Add-Member Noteproperty -Name Entry -value $Entry
        $Object | Add-Member Noteproperty -Name Job -value $Job
        $Object | Add-Member Noteproperty -Name JobName -value $JobName
        $Object | Add-Member Noteproperty -Name TargetServer -value $TargetServer
        $Object | Add-Member Noteproperty -Name RealCmdlet -value $RealCmdlet
        $Object | Add-Member Noteproperty -Name PSInstance -value $PSInstance
        $Object | Add-Member Noteproperty -Name RunspaceName -value $RunspaceName
        return $Object
    }

    Function processParallel
    {
        Param (
            [Parameter(Mandatory=$True)] $Entry,
            $TargetServer = $null
        )

        $AvailableRunspaceName = WaitAndProcess -FindAvailableSlots

        if ($null -eq $AvailableRunspaceName)
        {
            throw "Impossible to find an available runspace to launch the function"
        }

        $Section = $Entry.Section
        $PSCmdL = $Entry.PSCmdL

        if ([String]::IsNullOrEmpty($TargetServer))
        {
            Write-LogMessage -Message ("`tLaunch collection of $Section - $PSCmdL - Global Configuration ...") -NoOutput
            $jobName = $section
        }
        else
        {
            Write-LogMessage -Message ("`tLaunch collection of $Section - $PSCmdL - Per Server Configuration for $TargetServer ...") -NoOutput
            $PSCmdL = $PSCmdL -replace "#TargetServer#", $TargetServer
            $jobName = "$section-$TargetServer"
        }


        $Script:RunspaceResults.$AvailableRunspaceName.RunningExecution = $PSCmdL
        $ExecutionCode = {
            $RunspaceResults.$ESIRunspaceName.JobStatus = "Running"
            try
            {
                Write-Host "Launching Expression $($RunspaceResults.$ESIRunspaceName.RunningExecution)"
                $RunspaceResults.$ESIRunspaceName.JobResult = Invoke-Expression $RunspaceResults.$ESIRunspaceName.RunningExecution -ErrorAction Stop

                Write-Host "Updating JobStatus"
                $RunspaceResults.$ESIRunspaceName.JobStatus = "DataAvailable"
            }
            catch {
                Write-Host "Error $_"
                $RunspaceResults.$ESIRunspaceName.JobStatus = "Failed"
                $RunspaceResults.$ESIRunspaceName.JobResult = $_
            }
        }

        $PSinstance = $Script:RunspaceResults.$AvailableRunspaceName.PSInstance
        $PSinstance.AddScript($ExecutionCode) | Out-null

        $Job = $PSinstance.BeginInvoke()
        $script:RunningProcesses += New-JobEntry -Entry $Entry -Job $Job -JobName $jobName -TargetServer $TargetServer -RealCmdlet $PSCmdL -PSInstance $PSinstance -RunspaceName $AvailableRunspaceName
        $Script:RunspaceResults.AvailableRunspaces--
    }

    function WaitAndProcess
    {
        Param(
            [switch] $FindAvailableSlots
        )

        if ($FindAvailableSlots)
        {
            $MaxCount = $script:MaxParallel
        }
        else {$MaxCount = 0}

        $StartAnalysis = Get-Date
        $Timeout = $false

        $Iteration1 = 0
        $Iteration2 = 0

        while ($script:RunningProcesses.count -ge $MaxCount -and $script:RunningProcesses.count -gt 0)
        {
            Write-LogMessage -Message "Max running job raised - $Iteration1 - $Iteration2" -NoOutput
            # Find terminated processes
            for ($i = 0; $i -lt $script:RunningProcesses.count; $i++)
            {
                $RunspaceName = $script:RunningProcesses[$i].RunspaceName
                #$jobStatus = $Script:RunspaceResults.$RunspaceName.JobStatus
                #if ($jobStatus.State -ne "Running")
                if ($script:RunningProcesses[$i].job.IsCompleted)
                {
                    Write-LogMessage -Message "Completed job found. Launch of Transformation and result process on $($script:RunningProcesses[$i].JobName)" -NoOutput
                    $Script:RunspaceResults.$RunspaceName.PSInstance.EndInvoke($script:RunningProcesses[$i].job)
                    processTransformationAndResult -JobEntry $script:RunningProcesses[$i]
                    $script:RunningProcesses.RemoveAt($i)
                    $Script:RunspaceResults.$RunspaceName.JobStatus = "Ready"
                    $Script:RunspaceResults.$RunspaceName.ExecutionHistory += $Script:RunspaceResults.$RunspaceName.RunningExecution
                    $Script:RunspaceResults.$RunspaceName.RunningExecution = $null
                    $Script:RunspaceResults.$RunspaceName.JobResult = $null
                    $Script:RunspaceResults.$RunspaceName.PSInstance.Commands.Clear()
                    $Script:RunspaceResults.$RunspaceName.PSInstance.Streams.ClearStreams()
                    $i--
                    $Script:RunspaceResults.AvailableRunspaces++
                }
            }

            # Wait if condition not satisfied
            if ($script:RunningProcesses.count -ge $MaxCount -and $script:RunningProcesses.count -gt 0)
            {
                Write-LogMessage -Message "Impossible to reduce quantity of running job, wait $($Script:ParralelWaitRunning) seconds to retry." -NoOutput
                Start-Sleep -Seconds $Script:ParralelWaitRunning
                $Iteration1++
            }

            $Iteration2++

            if (((Get-Date) - $StartAnalysis).Minute -gt $Script:ParallelTimeout) {$Timeout = $true; break;}
        }

        if ($Timeout)
        {
            Write-LogMessage -Message "Timeout, entries not processed" -NoOutput
            for ($i = 0; $i -lt $script:RunningProcesses.count; $i++)
            {
                #$job = $script:RunningProcesses[$i]
                $RunspaceName = $script:RunningProcesses[$i].RunspaceName
                $Script:RunspaceResults.$RunspaceName.PSInstance.EndInvoke($script:RunningProcesses[$i].job)
                processTransformationAndResult -JobEntry $script:RunningProcesses[$i] -Timeout
                $script:RunningProcesses.RemoveAt($i)
                $Script:RunspaceResults.$RunspaceName.JobStatus = "Ready"
                $Script:RunspaceResults.$RunspaceName.ExecutionHistory += $Script:RunspaceResults.$RunspaceName.RunningExecution
                $Script:RunspaceResults.$RunspaceName.RunningExecution = $null
                $Script:RunspaceResults.$RunspaceName.JobResult = $null
                $Script:RunspaceResults.$RunspaceName.PSInstance.Commands.Clear()
                $Script:RunspaceResults.$RunspaceName.PSInstance.Streams.ClearStreams()
                $i--
                $Script:RunspaceResults.AvailableRunspaces++
            }
        }

        if ($FindAvailableSlots)
        {
            foreach ($RunpaceKey in $Script:Runspaces.Keys)
            {
                if ($Script:RunspaceResults.$RunpaceKey.JobStatus -like "Ready")
                {
                    if ($Script:Runspaces.$RunpaceKey.RunspaceStateInfo.State -notlike "Opened" -and $Script:Runspaces.$RunpaceKey.RunspaceAvailability -notlike "Available")
                    {
                        Write-LogMessage -Message "Bad runspace found. Removed from available slots. Runspace $RunpaceKey, State $($Script:Runspaces.$RunpaceKey.State) and Availability $($Script:Runspaces.$RunpaceKey.Availability)" -NoOutput
                        $Script:RunspaceResults.$RunpaceKey.JobStatus = "FailedRunspace"
                    }
                    else 
                    {                    
                        Write-LogMessage -Message "Runspace avalaible found : $RunpaceKey" -NoOutput
                        $Script:RunspaceResults.$RunpaceKey.JobStatus = "Assigned"
                        return $RunpaceKey
                    }
                }
            }
        }
    }

    function processTransformationAndResult
    {
        Param(
            [Parameter(Mandatory=$True)] $JobEntry,
            [switch] $Timeout
        )

        $RunspaceName = $JobEntry.RunspaceName
        $PSCmdLResult = $Script:RunspaceResults.$RunspaceName.JobResult
        #$PSCmdLResultFromJob = $JobEntry.PSInstance.EndInvoke($JobEntry.Job)
        $TransformationForeach = $JobEntry.Entry.TransformationForeach
        $TransformationFunction = $JobEntry.Entry.TransformationFunction
        $Section = $JobEntry.Entry.Section
        $PSCmdL = $JobEntry.RealCmdlet
        $select = $JobEntry.Entry.select
        
        try
        {
            
            Write-LogMessage -Message "##### Instance Results #####"  -NoOutput
            if (-not [string]::IsNullOrEmpty($JobEntry.PSInstance.Streams.Verbose)) 
            {   
                Write-LogMessage -Message "## Verbose" -NoOutput -Level Verbose
                Write-LogMessage -Message $JobEntry.PSInstance.Streams.Verbose -NoOutput -Level Verbose
                Write-LogMessage -Message "## ---- `n" -NoOutput -Level Verbose
            }
            
            if (-not [string]::IsNullOrEmpty($JobEntry.PSInstance.Streams.Information)) 
            { 
                Write-LogMessage -Message "## Information" -NoOutput
                Write-LogMessage -Message $JobEntry.PSInstance.Streams.Information -NoOutput
                Write-LogMessage -Message "## ---- `n" -NoOutput
            }

            if (-not [string]::IsNullOrEmpty($JobEntry.PSInstance.Streams.Warning)) 
            { 
                Write-LogMessage -Message "## Warning" -NoOutput -Level Warning
                Write-LogMessage -Message $JobEntry.PSInstance.Streams.Warning -NoOutput -Level Warning
                Write-LogMessage -Message "## ---- `n" -NoOutput -Level Warning
            }

            if (-not [string]::IsNullOrEmpty($JobEntry.PSInstance.Streams.Error)) 
            { 
                Write-LogMessage -Message "## Error" -NoOutput -Level Error
                Write-LogMessage -Message $JobEntry.PSInstance.Streams.Error -NoOutput -Level Error
                Write-LogMessage -Message "## ---- `n" -NoOutput -Level Error
            }

            if ($Timeout) { throw "Parallel Timeout, $($Script:ParallelTimeout)"}

            if (-not [String]::IsNullOrEmpty($TransformationFunction))
            {
                if ($TransformationForeach)
                {
                    $ExecutionForEach = @()
                    $intMax = $PSCmdLResult.Count
                    $inc = 0
                    foreach ($resultObject in $PSCmdLResult)
                    {
                        $inc++
                        Write-LogMessage -Message ("`tTransform Foreach $inc/$intMax - $Section - $PSCmdL - With function $TransformationFunction") -NoOutput
                        $ExecutionForEach += Invoke-Expression ("$TransformationFunction -ObjectInput " + '$resultObject')
                    }
                    $Execution = $ExecutionForEach
                }
                else {
                    Write-LogMessage -Message ("`tTransform $Section - $PSCmdL - With function $TransformationFunction") -NoOutput
                    $Execution = Invoke-Expression ("$TransformationFunction -ObjectInput " + '$PSCmdLResult')
                }   
            }
            else 
            {
                $Execution = $PSCmdLResult
            }

            if (-not [String]::IsNullOrEmpty($select))
            {
                Write-LogMessage -Message ("`tSelect Attribute $Section - $PSCmdL - With list $select") -NoOutput
                $Execution = $Execution | Select-Object $select | Sort-Object $select[0]
            }

            if ($null -ne $Execution) {
                Write-LogMessage -Message ("`t`t Generate Result ...") -NoOutput
                $Object = New-Result -Section $Section -PSCmdL $PSCmdL -CmdletResult $Execution -EntryDate $Script:DateSuffix -ScriptInstanceID $Script:ScriptInstanceID
            }
            else {
                Write-LogMessage -Message ("`t`t Generate empty result ...") -NoOutput
                $Object = New-Result -Section $Section -PSCmdL $PSCmdL -EmptyCmdlet -EntryDate $Script:DateSuffix -ScriptInstanceID $Script:ScriptInstanceID
            }
        }
        catch {
            $Object = New-Result -Section $Section -PSCmdL $PSCmdL -ErrorText $_.Exception -EntryDate $Script:DateSuffix -ScriptInstanceID $Script:ScriptInstanceID
            Write-LogMessage -Message ("`t`t Error during data collection - $($_.Exception)") -NoOutput -Level Error
        }

        $Script:Results[$JobEntry.Entry.OutputStream] += $Object
    }
        
    function CreateRunspaces
    {
        Param(
            $NumberRunspace
        )
        
        $Script:RunspaceResults = [hashtable]::Synchronized(@{})
        $Script:RunspaceResults.AvailableRunspaces = 0
        
        $ExchangeStartingCode = {
            try {
                Get-OrganizationConfig | Out-Null
            }
            catch
            {
                Connect-ExchangeServer -auto;
            }

            Set-ADServerSettings -ViewEntireForest $true
        }

        $JobList = @()
        Write-Host "Launching Runspace creation ..."

        for ($i = 0; $i -lt $NumberRunspace; $i++)
        {
            
            $RunspaceName = "Runspace$i"
            Write-Host "Creation of Runspace $RunspaceName"

            $iss = [InitialSessionState]::CreateDefault()
            $iss.ApartmentState = "STA"
            $iss.ThreadOptions = "ReuseThread"
            $iss.ImportPSModule("$($Script:DefaultExchangeServerBinPath)\RemoteExchange.ps1")
            
            $Script:RunspaceResults.$RunspaceName = New-Object PSObject
            $Script:RunspaceResults.$RunspaceName | Add-Member Noteproperty -Name JobResult -value $Null
            $Script:RunspaceResults.$RunspaceName | Add-Member Noteproperty -Name JobStatus -value "Ready"
            $Script:RunspaceResults.$RunspaceName | Add-Member Noteproperty -Name ExecutionHistory -value @()
            $Script:RunspaceResults.$RunspaceName | Add-Member Noteproperty -Name RunningExecution -value $null
            $Script:RunspaceResults.$RunspaceName | Add-Member Noteproperty -Name PSInstance -value $null
            
            $Script:Runspaces.$RunspaceName = [runspacefactory]::CreateRunspace($iss)
            $Script:Runspaces.$RunspaceName.ApartmentState = "STA"
            $Script:Runspaces.$RunspaceName.ThreadOptions = "ReuseThread"
            $Script:Runspaces.$RunspaceName.Open()
            $Script:Runspaces.$RunspaceName.SessionStateProxy.SetVariable("ESIRunspaceName",$RunspaceName)
            $Script:Runspaces.$RunspaceName.SessionStateProxy.SetVariable("RunspaceResults",$Script:RunspaceResults)
            
            $PSinstance = [powershell]::Create().AddScript($ExchangeStartingCode)
            $PSinstance.Runspace = $Script:Runspaces.$RunspaceName

            $Script:RunspaceResults.$RunspaceName.PSInstance = $PSinstance

            $JobList += @{"PSInstance"=$PSinstance; "Job"=$PSinstance.BeginInvoke(); "Finished"=$false}
        }

        $Iteration = 0
        $IsFinished = $false

        Write-Host "Monitoring Runspace creation ..."
        while (-not $IsFinished)
        {
            $Running = $false
            foreach ($job in $JobList)
            {
                if (-not $job.Finished -and -not $job.Job.IsCompleted)
                {
                    $running = $true;
                    continue
                }
                else {
                    
                    if (-not $job.Finished) 
                    { 
                        $Script:RunspaceResults.AvailableRunspaces++ 
                    
                        $job.PSInstance.EndInvoke($job.Job)
                        $job.PSInstance.Commands.Clear()
                        $job.PSInstance.Streams.ClearStreams()
                        $job.Finished=$true
                    }
                }
            }

            if (-not $Running) { $IsFinished = $true; break;}

            if ($Iteration -gt 100) {
                throw "Impossible to create Runspaces after 1000 seconds"
            }
            
            Write-Host "Runspace creation running, waiting 10 seconds ... "
            Start-Sleep -Seconds 10
            $Iteration++
        }

        Write-Host "$NumberRunspace Runspaces created"
    }

    function CloseRunspaces
    {
        foreach ($RunKey in $Script:Runspaces.Keys)
        {
            $Script:RunspaceResults.$RunKey.PSInstance.Dispose()

            $Script:Runspaces[$RunKey].Close()
            $Script:Runspaces[$RunKey].Dispose()
        }
    }

#endregion Multithreading Management

#region Business Functions

    #Retrieve group member, retrieve information for local user, call Function GetInfo and GetAllData
    Function GetDetails
    {
        Param(
            $TargetObject,
            $Level,
            $ParentgroupI
        )

        $MyObject = new-Object PSCustomObject
        $MyObject | Add-Member -MemberType NoteProperty -Name "Parentgroup" -Value $ParentgroupI
        $MyObject | Add-Member -MemberType NoteProperty -Name "Level" -Value $Level
        $MyObject | Add-Member -MemberType NoteProperty -Name "ObjectClass" -Value $TargetObject.objectClass
        $MyObject | Add-Member -MemberType NoteProperty -Name "MemberPath" -Value $TargetObject.Name
        $MyObject | Add-Member -MemberType NoteProperty -Name "ObjectGuid" -Value $TargetObject.ObjectGuid
        if ($TargetObject.objectClass -like "User")
        {
            $DN=[string]$TargetObject
            if ($script:GUserArray.keys -notcontains $DN)
            {
                $User = Get-ADUser $TargetObject.SAMAccountName -server ($DN.Substring($dn.IndexOf("DC=")) -replace ",DC=","." -replace "DC=") -Properties SamAccountName,Name,GivenName,Enabled,homemdb,LastLogonDate,PasswordLastSet,DistinguishedName,CanonicalName,UserPrincipalName | Select-Object SamAccountName,Name,GivenName,Enabled,homemdb,LastLogonDate,PasswordLastSet,DistinguishedName,CanonicalName,UserPrincipalName
                If ($Null -ne $User.homeMDB)
                {
                    $HasMbx = "True"
                }
                Else
                {
                    $HasMbx = "False"
                }
                
                $script:GUserArray[$User.DistinguishedName] = @{
                        UDN = $User.DistinguishedName
                        USamAccountName = $User.SamAccountName
                        ULastLogonDate = $User.LastLogonDate
                        UPasswordLastSet = $User.PasswordLastSet
                        UEnabled = $User.Enabled
                        UHasMbx=$HasMbx
                        UCanonicalName = $User.CanonicalName
                        UUPN = $User.UserPrincipalName
                    }
            }
            $MyObject | Add-Member -MemberType NoteProperty -Name "DN" -Value $script:GUserArray[$DN].UDN
            $MyObject | Add-Member -MemberType NoteProperty -Name "LastLogon" -Value $script:GUserArray[$DN].ULastLogonDate
            $MyObject | Add-Member -MemberType NoteProperty -Name "LastPwdSet" -Value $script:GUserArray[$DN].UPasswordLastSet
            $MyObject | Add-Member -MemberType NoteProperty -Name "Enabled" -Value $script:GUserArray[$DN].UEnabled
            $MyObject | Add-Member -MemberType NoteProperty -Name "SamAccountName" -Value $script:GUserArray[$DN].USamAccountName
            $MyObject | Add-Member -MemberType NoteProperty -Name "CanonicalName" -Value $script:GUserArray[$DN].UCanonicalName
            $MyObject | Add-Member -MemberType NoteProperty -Name "UserPrincipalName" -Value $script:GUserArray[$DN].UUPN
            $MyObject | Add-Member -MemberType NoteProperty -Name "HasMbx" -Value $script:GUserArray[$DN].UHasMbx
            # Has to be NULL
            $MyObject | Add-Member -MemberType NoteProperty -Name "Members" -Value $null
        }
        elseif ($TargetObject.objectClass -like "Group")
        {
            $MyObject | Add-Member -MemberType NoteProperty -Name "Members" -Value $null

            # Has to be NULL
            $MyObject | Add-Member -MemberType NoteProperty -Name "LastLogon" -Value $null
            $MyObject | Add-Member -MemberType NoteProperty -Name "LastPwdSet" -Value $null
            $MyObject | Add-Member -MemberType NoteProperty -Name "Enabled" -Value $null
            $MyObject | Add-Member -MemberType NoteProperty -Name "HasMbx" -Value $null
            $MyObject | Add-Member -MemberType NoteProperty -Name "SamAccountName" -Value $null
            $MyObject | Add-Member -MemberType NoteProperty -Name "CanonicalName" -Value $null
            $MyObject | Add-Member -MemberType NoteProperty -Name "UserPrincipalName" -Value $null
            $MyObject | Add-Member -MemberType NoteProperty -Name "DN" -Value $null
        }
        else
        {
            # Has to be NULL
            $MyObject | Add-Member -MemberType NoteProperty -Name "LastLogon" -Value $null
            $MyObject | Add-Member -MemberType NoteProperty -Name "LastPwdSet" -Value $null
            $MyObject | Add-Member -MemberType NoteProperty -Name "Enabled" -Value $null
            $MyObject | Add-Member -MemberType NoteProperty -Name "HasMbx" -Value $null
            $MyObject | Add-Member -MemberType NoteProperty -Name "Members" -Value $null
            $MyObject | Add-Member -MemberType NoteProperty -Name "SamAccountName" -Value $null
            $MyObject | Add-Member -MemberType NoteProperty -Name "CanonicalName" -Value $null
            $MyObject | Add-Member -MemberType NoteProperty -Name "UserPrincipalName" -Value $null
            $MyObject | Add-Member -MemberType NoteProperty -Name "DN" -Value $null
        }
        return $MyObject
    }

    #Retrieve group member
    Function GetMember
    {
        Param (
            $TargetObject,
            $dnsrvobj
        )
        $list = Get-ADGroupMember $TargetObject.SamAccountName -server $dnsrvobj
        return $List
    }

    #Create the MemberPath value
    Function GenerateMembersDetail
    {
        Param (
            $ResultTable,
            $Name
        )

        foreach ($Result in $ResultTable)
        {
            $Result.MemberPath = $Name + "\" + $Result.MemberPath
        }
        return $ResultTable
    }

    #Call Function to retrieve group member and user spceific information and Function to create the MemberPath
    Function GetInfo
    {
        Param (
            $ObjectInput,
            $Level = $null,
            $parentgroup
        )

        if ($null -ne $level)
        {
            $Level++
        }
        else
        {
            $level = 0
            $entry = $ObjectInput.DistinguishedName
            $DN=($entry.Substring($entry.IndexOf("DC=")))
            $parentgroup =  ($entry.split(","))[0].replace("CN=","")
        }

        $InfoTable = @()

        #Call Function to create member path parameter
        $InfoResult = GetDetails -TargetObject $ObjectInput -Level $Level -Parentgroup $parentgroup
        $InfoTable += $InfoResult
        if ($ObjectInput.ObjectClass -like "Group")
        {
            #Call Function to retrieve group content
            $dnsrv= (($ObjectInput.DistinguishedName).Substring(($ObjectInput.DistinguishedName).IndexOf("DC=")) -replace ",DC=","." -replace "DC=")
            $list = GetMember -TargetObject $ObjectInput -dnsrvobj $dnsrv
            $InfoResult.Members = $list
            foreach ($member in $list)
            {
                $ResultTable = GetInfo -ObjectInput $member -Level $Level -Parentgroup $parentgroup
                $ResultTable = GenerateMembersDetail -ResultTable $ResultTable -Name $ObjectInput.Name -ParentgroupI $parentgroup
                $InfoTable += $ResultTable
            }
        }

        if ($ObjectInput.ObjectClass -like "ManagementRoleAssignment")
        {         
            #Call Function to retrieve group content
            $dnsrv= $ObjectInput.RoleAssignee.DomainId
            $AssigneeObject = Get-ADObject $ObjectInput.RoleAssignee.DistinguishedName -Server $dnsrv -Properties SAMAccountName
            $ResultTable = GetInfo -ObjectInput $AssigneeObject -Level $Level -Parentgroup $ObjectInput.Name
            $ResultTable = GenerateMembersDetail -ResultTable $ResultTable -Name $ObjectInput.Name -ParentgroupI $parentgroup
            $InfoTable += $ResultTable
        }
        return $InfoTable
    }

    Function GetWMILocalAdmins
    {
        Param (
        $ObjectInput
        )

        $TheObject = $ObjectInput.List
        $srv = $ObjectInput.Srv

        $ObjectList = @()

        $TheObject2 = new-Object PSCustomObject
        $TheObject2 | Add-Member -MemberType NoteProperty -Name "Parentgroup" -Value "$srv\Local Administrators"
        $TheObject2 | Add-Member -MemberType NoteProperty -Name "Level" -Value 0
        $TheObject2 | Add-Member -MemberType NoteProperty -Name "ObjectClass" -Value "Local Group"
        $TheObject2 | Add-Member -MemberType NoteProperty -Name "MemberPath" -Value "Local Administrators"
        $TheObject2 | Add-Member -MemberType NoteProperty -Name "ObjectGuid" -Value $null
        $TheObject2 | Add-Member -MemberType NoteProperty -Name "DN" -Value $null
        $TheObject2 | Add-Member -MemberType NoteProperty -Name "Members" -Value $ObjectInput.List
        $TheObject2 | Add-Member -MemberType NoteProperty -Name "LastLogon" -Value $null
        $TheObject2 | Add-Member -MemberType NoteProperty -Name "LastPwdSet" -Value $null
        $TheObject2 | Add-Member -MemberType NoteProperty -Name "Enabled" -Value $null
        $TheObject2 | Add-Member -MemberType NoteProperty -Name "HasMbx" -Value $null
        $TheObject2 | Add-Member -MemberType NoteProperty -Name "SamAccountName" -Value "Administrators"
        $TheObject2 | Add-Member -MemberType NoteProperty -Name "CanonicalName" -Value $null
        $TheObject2 | Add-Member -MemberType NoteProperty -Name "UserPrincipalName" -Value $null

        $ObjectList += $TheObject2

        foreach ($entry in $TheObject)
        {
            if($entry.split(";")[0] -like "*Win32_UserAccount*" -and $entry.split(";")[1] -like "$srv\*"  )
            {
                #For Local User in the Local Administrators group
                $TheObject2 = new-Object PSCustomObject
                $TheObject2 | Add-Member -MemberType NoteProperty -Name "Parentgroup" -Value "$srv\Local Administrators"
                $TheObject2 | Add-Member -MemberType NoteProperty -Name "Level" -Value 1
                $TheObject2 | Add-Member -MemberType NoteProperty -Name "ObjectClass" -Value "Local User"
                $TheObject2 | Add-Member -MemberType NoteProperty -Name "ObjectGuid" -Value $null
                $TheObject2 | Add-Member -MemberType NoteProperty -Name "MemberPath" -Value ($entry.split(";"))[1].split("\")[1]
                $TheObject2 | Add-Member -MemberType NoteProperty -Name "DN" -Value $null
                $TheObject2 | Add-Member -MemberType NoteProperty -Name "Members" -Value $null
                $TheObject2 | Add-Member -MemberType NoteProperty -Name "LastLogon" -Value $null
                $TheObject2 | Add-Member -MemberType NoteProperty -Name "LastPwdSet" -Value $null
                $TheObject2 | Add-Member -MemberType NoteProperty -Name "Enabled" -Value $null
                $TheObject2 | Add-Member -MemberType NoteProperty -Name "HasMbx" -Value $null
                $TheObject2 | Add-Member -MemberType NoteProperty -Name "SamAccountName" -Value ($entry.split(";"))[1]
                $TheObject2 | Add-Member -MemberType NoteProperty -Name "CanonicalName" -Value $null
                $TheObject2 | Add-Member -MemberType NoteProperty -Name "UserPrincipalName" -Value $null
            }
            elseif($entry.split(";")[0] -like "*Win32_UserAccount*")
            {
                $DomUser=$entry.split(";")[1]
                if ($ht_domains.Keys -contains $DomUser.Split("\")[0])
                {
                    $DN = ($script:GUserArray.GetEnumerator() | Where-Object{$_.value.USamAccountName -like $entry.split(";")[1].split("\")[1]}).key
                    if ($script:GUserArray.keys -notcontains $DN)
                    {
                        $User = Get-ADUser $DomUser.Split("\")[1] -Server $script:ht_domains[$DomUser.Split("\")[0]].DCFQDN -Properties SamAccountName,Name,GivenName,Enabled,homemdb,LastLogonDate,PasswordLastSet,DistinguishedName,CanonicalName,UserPrincipalName | Select-Object SamAccountName,Name,GivenName,Enabled,homemdb,LastLogonDate,PasswordLastSet,DistinguishedName,CanonicalName,UserPrincipalName
                        If ($Null -ne $User.homeMDB)
                        {
                            $HasMbx = "True"
                        }
                        Else
                        {
                            $HasMbx = "False"
                        }
                        
                        $script:GUserArray[$User.DistinguishedName] = @{
                                UDN = $User.DistinguishedName
                                USamAccountName = $User.SamAccountName
                                ULastLogonDate = $User.LastLogonDate
                                UPasswordLastSet = $User.PasswordLastSet
                                UEnabled = $User.Enabled
                                UHasMbx=$HasMbx
                                UCanonicalName = $User.CanonicalName
                                UUPN = $User.UserPrincipalName
                            }
                        $DN = $User.DistinguishedName
                    }
                    $TheObject2 = new-Object PSCustomObject
                    $TheObject2 | Add-Member -MemberType NoteProperty -Name "Parentgroup" -Value "$srv\Local Administrators"
                    $TheObject2 | Add-Member -MemberType NoteProperty -Name "Level" -Value 1
                    $TheObject2 | Add-Member -MemberType NoteProperty -Name "ObjectClass" -Value "User"
                    $TheObject2 | Add-Member -MemberType NoteProperty -Name "MemberPath" -Value ($entry.split(";"))[1]
                    $TheObject2 | Add-Member -MemberType NoteProperty -Name "Members" -Value $null
                    $TheObject2 | Add-Member -MemberType NoteProperty -Name "LastLogon" -Value $script:GUserArray[$DN].ULastLogonDate
                    $TheObject2 | Add-Member -MemberType NoteProperty -Name "LastPwdSet" -Value $script:GUserArray[$DN].UPasswordLastSet
                    $TheObject2 | Add-Member -MemberType NoteProperty -Name "Enabled" -Value $script:GUserArray[$DN].UEnabled
                    $TheObject2 | Add-Member -MemberType NoteProperty -Name "HasMbx" -Value $script:GUserArray[$DN].UHasMbx
                    $TheObject2 | Add-Member -MemberType NoteProperty -Name "DN" -Value $script:GUserArray[$DN].UDN
                    $TheObject2 | Add-Member -MemberType NoteProperty -Name "SamAccountName" -Value $script:GUserArray[$DN].USamAccountName
                    $TheObject2 | Add-Member -MemberType NoteProperty -Name "CanonicalName" -Value $script:GUserArray[$DN].UCanonicalName
                    $TheObject2 | Add-Member -MemberType NoteProperty -Name "UserPrincipalName" -Value $script:GUserArray[$DN].UUPN
                }
                else
                {
                    #User from another Forest, Information can't be retrieve
                    $TheObject2 = new-Object PSCustomObject
                    $TheObject2 | Add-Member -MemberType NoteProperty -Name "Parentgroup" -Value "$srv\Local Administrators"
                    $TheObject2 | Add-Member -MemberType NoteProperty -Name "Level" -Value 1
                    $TheObject2 | Add-Member -MemberType NoteProperty -Name "ObjectClass" -Value "Trusted Forest User"
                    $TheObject2 | Add-Member -MemberType NoteProperty -Name "MemberPath" -Value ($entry.split(";"))[1].split("\")[1]
                    $TheObject2 | Add-Member -MemberType NoteProperty -Name "DN" -Value $null
                    $TheObject2 | Add-Member -MemberType NoteProperty -Name "Members" -Value $null
                    $TheObject2 | Add-Member -MemberType NoteProperty -Name "LastLogon" -Value "N/A"
                    $TheObject2 | Add-Member -MemberType NoteProperty -Name "LastPwdSet" -Value "N/A"
                    $TheObject2 | Add-Member -MemberType NoteProperty -Name "Enabled" -Value "N/A"
                    $TheObject2 | Add-Member -MemberType NoteProperty -Name "HasMbx" -Value "N/A"
                    $TheObject2 | Add-Member -MemberType NoteProperty -Name "SamAccountName" -Value "N/A"
                    $TheObject2 | Add-Member -MemberType NoteProperty -Name "CanonicalName" -Value "N/A"
                    $TheObject2 | Add-Member -MemberType NoteProperty -Name "UserPrincipalName" -Value "N/A"
                }
            }
            else {
                $dn=(Get-ADDomain ($entry.split(";"))[1].split("\")[0]).DistinguishedName
                $entry=($entry.split(";"))[1].split("\")[1]
                $DNobj=($DN.Substring($dn.IndexOf("DC=")) -replace ",DC=","." -replace "DC=")
                $GroupObject = Get-ADGroup -filter 'Name -eq $entry' -server $DNobj
                $TheObject2 = GetInfo -ObjectInput $GroupObject -Level 0 -Parentgroup "$srv\Local Administrators"
            }
            $ObjectList += $TheObject2
        }

        return $ObjectList
    }

#Endregion Business Functions

#region Configuration Loading

    function LoadConfiguration 
    {
        Param (
            $configurationFile,
            [switch] $VariableFromAzureAutomation,
            $ReceivedTenantName
        )

        try
        {
            if ($VariableFromAzureAutomation)
            {
                $jsonConfig = Get-AutomationVariable -Name GlobalConfiguration -ErrorAction Stop
                $jsonConfig = $jsonConfig | ConvertFrom-Json
                $script:TenantName = Get-AutomationVariable -Name TenantName -ErrorAction Stop
            }
            else {
                $jsonConfig = Get-Content $configurationFile | ConvertFrom-Json
                if (-not [String]::IsNullOrEmpty($ReceivedTenantName)) { $script:TenantName = $ReceivedTenantName}
                else { $script:TenantName = $Global:TenantName }
            }
            
                
            [int] $Script:ParallelTimeout = $jsonConfig.Global.ParallelTimeoutMinutes # Minutes
            [int] $script:MaxParallel = $jsonConfig.Global.MaxParallelRunningJobs
            $Script:ParallelProcessPerServer = [Convert]::ToBoolean($jsonConfig.Global.PerServerParallelProcessing)
            $Script:GlobalParallelProcess = [Convert]::ToBoolean($jsonConfig.Global.GlobalParallelProcessing)
            [int] $Script:DefaultDurationTracking = $jsonConfig.Global.DefaultDurationTracking
            $Script:ESIProcessingType = $jsonConfig.Global.ESIProcessingType
            if ($Script:ESIProcessingType -notin ('Online', 'On-Premises'))
            {
                Write-LogMessage -Message "Processing $($Script:ESIProcessingType) not in authorized list : 'Online', 'On-Premises'. Unable to continue" -Level Error
                throw "Processing $($Script:ESIProcessingType) not in authorized list : 'Online', 'On-Premises', 'All'. Unable to continue"
            }
            if ($Script:ESIProcessingType -like "Online" -and [String]::IsNullOrEmpty($script:TenantName)) 
            { 
                Write-LogMessage -Message 'No Tenant Name in an Online Configuration. Tenant name is mandatory. By passing as parameter to the script of setting global value $Global:TenantName'  -Level Error
                throw 'No Tenant Name in an Online Configuration. Tenant name is mandatory. By passing as parameter to the script of setting global value $Global:TenantName' 
            }

            $Script:ESIEnvironmentIdentification = $jsonConfig.Global.EnvironmentIdentification
            if (-not [String]::IsNullOrEmpty($script:TenantName) -and [String]::IsNullOrEmpty($Script:ESIEnvironmentIdentification))
            {
                $Script:ESIEnvironmentIdentification = $script:TenantName
            }

            if (($VariableFromAzureAutomation -or $Script:ESIProcessingType -like "Online") -and ($Script:ParallelProcessPerServer -or $Script:GlobalParallelProcess))
            {
                Write-LogMessage -Level Warning -Message "Impossible to use Multithreading in an Azure Automation or for Exchange Online. Multithreading automatically deactivated"
                $Script:ParallelProcessPerServer = $false
                $Script:GlobalParallelProcess = $false
            }

            if ([string]::IsNullOrEmpty($jsonConfig.Output.DefaultOutputFile) -and -not $Global:isRunbook) {throw "No Output file in config, mandatory"} else {$Script:outputpath = $jsonConfig.Output.DefaultOutputFile}

            [int] $Script:ParralelWaitRunning
            if ($null -eq $jsonConfig.Advanced.ParralelWaitRunning) {[int] $Script:ParralelWaitRunning = 60} else {[int] $Script:ParralelWaitRunning = $jsonConfig.Advanced.ParralelWaitRunning}
            if ($null -eq $jsonConfig.Advanced.ParralelPingWaitRunning) {[int] $Script:ParralelPingWaitRunning = $Script:ParralelWaitRunning} else {[int] $Script:ParralelPingWaitRunning = $jsonConfig.Advanced.ParralelPingWaitRunning}

            if (-not [string]::IsNullOrEmpty($jsonConfig.Advanced.OnlyExplicitActivation)) 
            {   
                $Script:OnlyExplicitActivation = [Convert]::ToBoolean($jsonConfig.Advanced.OnlyExplicitActivation)
            }
            else { $Script:OnlyExplicitActivation = $false }

            if (-not [string]::IsNullOrEmpty($jsonConfig.Advanced.BypassServerAvailabilityTest)) 
            {   
                $Script:BypassServerAvailabilityTest = [Convert]::ToBoolean($jsonConfig.Advanced.BypassServerAvailabilityTest)
            }
            else { $Script:BypassServerAvailabilityTest = $false }

            if (-not [string]::IsNullOrEmpty($jsonConfig.Advanced.ExplicitExchangeServerList)) 
            {   
                $Script:ExplicitExchangeServerList = $jsonConfig.Advanced.ExplicitExchangeServerList
            }
            else { $Script:ExplicitExchangeServerList = $null }

            if (-not [string]::IsNullOrEmpty($jsonConfig.Advanced.ExchangeServerBinPath)) 
            {   
                $Script:DefaultExchangeServerBinPath = $jsonConfig.Advanced.ExchangeServerBinPath
            }
            else { $Script:DefaultExchangeServerBinPath = "c:\\Program Files\\Microsoft\\Exchange Server\\V15\\bin" }

            $Script:JSonAuditFunctionList = $jsonConfig.AuditFunctions

            if (-not [string]::IsNullOrEmpty($jsonConfig.LogCollection))
            {
                $Script:SentinelLogCollector = New-Object PSObject
                if (-not [string]::IsNullOrEmpty($jsonConfig.LogCollection))
                {
                    $Script:SentinelLogCollector | Add-Member Noteproperty -Name ActivateLogUpdloadToSentinel -value ([Convert]::ToBoolean($jsonConfig.LogCollection.ActivateLogUpdloadToSentinel))
                }
                else {
                    $Script:SentinelLogCollector | Add-Member Noteproperty -Name ActivateLogUpdloadToSentinel -value $false
                }
                $Script:SentinelLogCollector | Add-Member Noteproperty -Name WorkspaceId -value $jsonConfig.LogCollection.WorkspaceId
                $Script:SentinelLogCollector | Add-Member Noteproperty -Name WorkspaceKey -value $jsonConfig.LogCollection.WorkspaceKey
                $Script:SentinelLogCollector | Add-Member Noteproperty -Name LogTypeName -value $jsonConfig.LogCollection.LogTypeName
                $Script:SentinelLogCollector | Add-Member Noteproperty -Name TogetherMode -value ([Convert]::ToBoolean($jsonConfig.LogCollection.TogetherMode))

                if ($Script:SentinelLogCollector.ActivateLogUpdloadToSentinel)
                {
                    if ([string]::IsNullOrEmpty($Script:SentinelLogCollector.WorkspaceId) -or
                    [string]::IsNullOrEmpty($Script:SentinelLogCollector.WorkspaceKey) -or
                    [string]::IsNullOrEmpty($Script:SentinelLogCollector.LogTypeName))
                    {
                        throw "Sentinel Log Collector configuration is activated and contains wrong values."
                    }
                }
            }

        }
        catch
        {
            Write-LogMessage -Message "Impossible to process configuration " + $_.Exception -Level Error
            throw $_
        }
    }

    function LoadAuditFunctions
    {
        Param (
            $AuditFunctionList,
            $ProcessingType
        )

        $Replacements = @{
            "#LastDateTracking#" = $script:LastDateTracking; 
            "#ForestDN#" = $script:ForestDN; 
            "#ForestName#" = $script:ForestName; 
            "#ExchOrgName#" = $script:ExchOrgName; 
            "#GCRoot#" = $script:GCRoot;
            "#GCServer#" = $script:gc;
            "#SIDRoot#" = $script:sidroot;
        }

        $FunctionListFromConfig = @()
        foreach ($AuditFunction in $AuditFunctionList)
        {
            if (-not [string]::IsNullOrEmpty($AuditFunction.Deactivated)) 
            {   
                $FunctionDeactivated = [Convert]::ToBoolean($AuditFunction.Deactivated)
                if ($FunctionDeactivated) { Write-LogMessage -Message "Function $($AuditFunction.Section) Deactivated" -NoOutput; continue;}
            }

            $FunctionProcessingCategory = $AuditFunction.ProcessingCategory
            if ([string]::IsNullOrEmpty($FunctionProcessingCategory)) {$FunctionProcessingCategory = 'On-Premises'}

            if ($FunctionProcessingCategory -notlike "All" -and $FunctionProcessingCategory -notlike $ProcessingType)
            {
                Write-LogMessage -Message "Function $($AuditFunction.Section) with Processing Category $FunctionProcessingCategory is not compatible with current processing $ProcessingType" -NoOutput; 
                continue;
            }

            if ($Script:OnlyExplicitActivation)
            {
                if (-not [string]::IsNullOrEmpty($AuditFunction.ExplicitActivation)) 
                {   
                    $FunctionExpliciallyActivated = [Convert]::ToBoolean($AuditFunction.ExplicitActivation)
                    if (-not $FunctionExpliciallyActivated) 
                    { 
                        Write-LogMessage -Message "Function $($AuditFunction.Section) not explicitaly activated and ExplicitActivation flag present" -NoOutput; 
                        continue;
                    }
                    else {
                        Write-LogMessage -Message "Function $($AuditFunction.Section) explicitaly activated and ExplicitActivation flag present / Will be launched" -NoOutput;
                    }
                }
                else
                {
                    Write-LogMessage -Message "Function $($AuditFunction.Section) not explicitaly activated and ExplicitActivation flag present" -NoOutput; 
                    continue;
                }
            }

            $TargetCmdlet = $AuditFunction.Cmdlet
            foreach ($ReplaceKey in $Replacements.Keys)
            {
                $TargetCmdlet = $TargetCmdlet -replace $ReplaceKey, $Replacements[$ReplaceKey]
            }

            if ([string]::IsNullOrEmpty($AuditFunction.ProcessPerServer)) {$TargetProcessPerServer = $false}
            else {$TargetProcessPerServer = [Convert]::ToBoolean($AuditFunction.ProcessPerServer)}

            if ([string]::IsNullOrEmpty($AuditFunction.TransformationForeach)) {$TransformationForeach = $false}
            else {$TransformationForeach = [Convert]::ToBoolean($AuditFunction.TransformationForeach)}

            if ([string]::IsNullOrEmpty($AuditFunction.PropertySelection)) {$TargetSelect = @("*")} else { $TargetSelect = $AuditFunction.PropertySelection}
            
            if (-not [string]::IsNullOrEmpty($AuditFunction.CustomExpressionForSelection)) 
            {
                foreach ($CustomExp in $AuditFunction.CustomExpressionForSelection)
                {
                    $TargetSelect += @{Name=$CustomExp.Name; Expression=[ScriptBlock]::Create($CustomExp.Expression)}
                }
            }

            if ([string]::IsNullOrEmpty($AuditFunction.OutputStream)) {$TargetOutputStream = "Default"}
            else {$TargetOutputStream = $AuditFunction.OutputStream}

            $FunctionListFromConfig += New-Entry -Section $AuditFunction.Section -PSCmdL $TargetCmdlet -Select $TargetSelect -TransformationFunction $AuditFunction.TransformationFunction -ProcessPerServer:$TargetProcessPerServer  -TransformationForeach:$TransformationForeach -OutputStream $TargetOutputStream
        }

        return $FunctionListFromConfig
    }

#endregion Configuration Loading

$InformationPreference = "Continue"
$start = Get-Date
$DateSuffixForFile = Get-Date -Format "yyyy-MM-dd-HH-mm-ss"
$DateSuffix = Get-Date -Format "yyyy-MM-dd HH:mm:ss K"
$Global:isRunbook = !($null -eq (Get-Command "Get-AutomationVariable" -ErrorAction SilentlyContinue))
$Script:Runspaces = @{}

if (-not $Global:isRunbook )
{
    $scriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Definition
    $ScriptLogPath = $scriptFolder + '\Logs'

    Push-Location ($scriptFolder);
    if (! (Test-Path $ScriptLogPath)) { mkdir $ScriptLogPath }

    $ScriptLogFile = "$ScriptLogPath\ScriptLog-$DateSuffixForFile.log"
    Start-Transcript -Path $ScriptLogFile
}

LoadConfiguration -configurationFile $JSONFileCondiguration -VariableFromAzureAutomation:$Global:isRunbook -ErrorAction Stop

$ScriptInstanceID = ([Guid]::NewGuid()).Guid
Write-LogMessage -Message "Launching Exchange Configuration Collector Script, with ID $ScriptInstanceID on date $DateSuffix"


if (-not $NoDateTracing)
{
    Get-LastLaunchTime
}

Write-LogMessage -Message ("Connect to Exchange with Type $($Script:ESIProcessingType) ...")
try {
    Get-OrganizationConfig | Out-Null
}
catch
{
    if ($Script:ESIProcessingType -like "Online")
    {
        Write-LogMessage -Message "Connect to Exchange Online"
        Connect-ESIExchangeOnline -TenantName $Script:TenantName
    }
    else {
        . "$($Script:DefaultExchangeServerBinPath)\RemoteExchange.ps1";
        Connect-ExchangeServer -auto;
    }
}

if ($Script:ESIProcessingType -notlike "Online")
{
    Write-LogMessage -Message ("Set Exchange View Entire Forest ...")
    Set-ADServerSettings -ViewEntireForest $true
}

if ($Script:ParallelProcessPerServer -or $Script:GlobalParallelProcess) {
    CreateRunspaces -NumberRunspace $Script:MaxParallel
}

$script:ht_domains = @{}
$script:GUserArray=@{}
[System.Collections.ArrayList] $script:RunningProcesses = @()

Write-LogMessage -Message ("Retrieve Environment information ...")
if ($Script:ESIProcessingType -notlike "Online")
{
    $script:ExchOrgName = (Get-OrganizationConfig).Identity
    $script:GCRoot = (Get-ADServerSettings).DefaultGlobalCatalog

    $ExchangeServerList = Get-ExchangeServerList -EPS2010 $EPS2010 -Parallel:$Script:ParallelProcessPerServer -ServerList $Script:ExplicitExchangeServerList -BypassTest:$script:BypassServerAvailabilityTest

    $ADInfo = Get-ADInfo
    $script:ForestName = $ADInfo[0]
    $script:ForestDN = $ADInfo[1]
    $script:gc = $ADInfo[2]
    $script:sidroot = $ADInfo[3]

    if ([String]::IsNullOrEmpty($Script:ESIEnvironmentIdentification)) {$Script:ESIEnvironmentIdentification = $script:ForestName}
}

if (-not $Global:isRunbook)
{
    Write-Host ("Create/Validate Output file path")
    if (-not (Test-Path (Split-Path $outputpath))) {mkdir (Split-Path $outputpath)}
    if (-not $ForceOutputWithoutDate -or $null -eq $ForceOutputWithoutDate)
    {
        $outputpath = $outputpath -replace ".csv", "-$DateSuffixForFile.csv"
    }
}

$FunctionList = LoadAuditFunctions -AuditFunctionList $Script:JSonAuditFunctionList -ProcessingType $Script:ESIProcessingType

Write-LogMessage -Message ("Launch Data collection ...")
$Script:Results = @{}
$Script:Results["Default"] = @()
$inc = 1

foreach ($Entry in $FunctionList)
{
    if ($Entry.OutputStream -notin $Script:Results.Keys) {
        $Script:Results[$Entry.OutputStream] = @()
    }

    Write-LogMessage -Message ("`tLaunch collection $inc on $($FunctionList.count)")
    if ($Entry.ProcessPerServer)
    {
        foreach ($ExchangeServer in $ExchangeServerList.ListSRVUp)
        {
            if ($Script:ParallelProcessPerServer -or $Script:GlobalParallelProcess) {
                processParallel -Entry $Entry -TargetServer $ExchangeServer
            }
            else {
                $Script:Results[$Entry.OutputStream] += GetCmdletExec -Section $Entry.Section -PSCmdL $Entry.PSCmdL -Select $Entry.Select -TransformationFunction $Entry.TransformationFunction -TargetServer $ExchangeServer -TransformationForeach:$Entry.TransformationForeach
            }
        }
    }
    else
    {
        if ($Script:GlobalParallelProcess) {
            processParallel -Entry $Entry
        }
        else {
            $Script:Results[$Entry.OutputStream] += GetCmdletExec -Section $Entry.Section -PSCmdL $Entry.PSCmdL -Select $Entry.Select -TransformationFunction $Entry.TransformationFunction -TransformationForeach:$Entry.TransformationForeach
        }
    }

    $inc++
}

if ($Script:ParallelProcessPerServer -or $Script:GlobalParallelProcess) {
    WaitAndProcess
    Write-LogMessage -Message ("Close Created Runspaces")
    CloseRunspaces
}

Write-LogMessage -Message ("Launch CSV Creation / Sentinel Payload uploading ...")
$Global:InjectionTest = @()

foreach ($OutputName in $Script:Results.Keys)
{
    if ($Script:SentinelLogCollector.ActivateLogUpdloadToSentinel)
    {
        try
        {   
            $ResultInjsonFormat = $script:Results[$OutputName] | ConvertTo-Json -Compress
            $Global:InjectionTest += $script:Results[$OutputName] 
        }
        catch
        {
            throw("Input data cannot be converted into a JSON object. Please make sure that the input data is a standard PowerShell table")
        }

        # Submit the data to the API endpoint
        Post-LogAnalyticsData -customerId $Script:SentinelLogCollector.WorkspaceId `
            -sharedKey $Script:SentinelLogCollector.WorkspaceKey `
            -body ([System.Text.Encoding]::UTF8.GetBytes($ResultInjsonFormat)) `
            -logType $Script:SentinelLogCollector.LogTypeName
    }

    if (-not $Script:SentinelLogCollector.ActivateLogUpdloadToSentinel -or $Script:SentinelLogCollector.TogetherMode)
    {
        if ($OutputName -eq "Default") {
            $Results[$OutputName] | Export-Csv -Path $outputpath -NoTypeInformation
        }
        else
        {
            $OutputFileName = $OutputName
            $outputdirectorypath = Split-Path $outputpath
            if (-not $ForceOutputWithoutDate -or $null -eq $ForceOutputWithoutDate)
            {
                $OutputFileName = $OutputFileName -replace ".csv", "-$DateSuffixForFile.csv"
            }
            $generatedOutputName = $outputdirectorypath + "\" + $OutputFileName
            $Results[$OutputName] | Export-Csv -Path $generatedOutputName -NoTypeInformation
        }
    }
}

if (-not $NoDateTracing)
{
    Set-CurrentLaunchTime
}

Write-LogMessage -Message ("Exchange Configuration Collector script finished")
Write-Output "`n**************** LOGS **********************"
Write-Output (Get-UDSLogs)
Write-Output "**************** END LOGS **********************`n"
$end = Get-Date
Write-LogMessage -Message "Execution done. Time elapsed: $(($end-$start).TotalSeconds)s Processed messages: $processedMessagesCount"
Write-LogMessage -Message "Execution done. Time elapsed: $(($end-$start).TotalSeconds)s Processed messages: $processedMessagesCount" -Level Warning