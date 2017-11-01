#Daily report to check if group membership has changed, will send an e-mail listing the changes if there are any. Will also send an e-mail the first day of every month to ensure that process is still working 
#Module imports
Import-Module ActiveDirectory
Import-Module SQLPS

#Static Variables
$savedReportFolder = "Microsoft.PowerShell.Core\FileSystem::<UNC_Network_Path>" #Need to add the 'Microsoft.PowerShell.Core\FileSystem::' provider for SQL call, or else the UNC call will fail because it tries to use the SQL provider to open the path by default.
$administratorGroups = ("AD_Group1","AD_Group2") #AD Groups to check memberships for
$sqlServers = ("SQL_Server1","SQL_Server2") #Internal SQL servers to check sysadmin membership for
$formattedDateToday = (Get-Date).ToString('MMM-dd-yyyy')
$formattedDateYesterday = (Get-Date).AddDays(-1).ToString(('MMM-dd-yyyy'))
#Email Variables
$emailTo = "e-it@laserfiche.com" #group that should receive membership change alerts.
$emailFrom = "ITReport@laserfiche.com" #email to send alerts from, will need to be the same as the user that runs the script.
$emailServer = "v-exchange.laserfiche.com" #email server used to send emails.
#SQL Credentials
$sqlUsername = "ITReport" #SQL username to use when connecting to SQL servers outside of domain (SQL Authentication).
$sqlPassword = "AZ79JMr<5P3&Q}Cb" #SQL password to use when connecting to SQL servers outside of domain (SQL Authentication).

#FUNctions
#Checks to see if group membership has changed by comparing the current members to previous membership. Takes 3 arguments, the name of the group to check, a string array of users in the group, and a UNC path of where to check for old records and save new ones.
Function Get-MembershipChange()
{
    Param([string]$groupName, [string[]]$membersToCheck, [string]$recordPath)

    #Creates a text file using the name of the group and the current date and saves the text file to the UNC path passed via argument.
    $newRecordPath = $recordPath + $groupName + "_log_" + $formattedDateToday + ".txt"
    $oldRecordPath = $recordPath + $groupName + "_log_" + $formattedDateYesterday + ".txt"
    $addedMembers = @()
    $removedMembers = @()

    $membersToCheck > ($newRecordPath) #Create a record for today.
    
    if (-not (Test-Path -Path ($oldRecordPath))) #Check if a record exists.Send an email alert if an old record cannot be found
    {        
        $emailSubject = ("Yesterday's record could not be found for " + $groupName)
        $emailBody = ("There was no record available to check group membership for " + $groupName + " at " + $savedReportFolder)
        Send-MailMessage -SmtpServer $emailServer -Subject $emailSubject -Body $emailBody -to $emailTo -From $emailFrom #Send an alert that yesterday's record could not be found.
    }
    else
    {
        #read saved files and check them against the current group members.
        $recordContent = Get-Content ($oldRecordPath)
        $groupDifference = Compare-Object -ReferenceObject $recordContent -DifferenceObject $membersToCheck | Select-Object -ExpandProperty InputObject
        if($groupDifference -ne $null) #checks to see if any of values differ between groups. If different values are found, a notification email is sent.
        {
            foreach($person in $groupDifference)
            {
                if($membersToCheck.Contains($person))
                {
                    $addedMembers += $person
                }
                else 
                {
                    $removedMembers += $person    
                }
            }
            
            $emailSubject = ($groupName + " has been modified - " + $formattedDateToday)
            $emailBody = "Members Added:`n" + ($addedMembers | Out-String) + "`nMembers Removed:`n" + ($removedMembers | Out-String) + "`nCurrent Members:`n" + ($membersToCheck | Out-String) + "`nOld Members:`n" + ($recordContent | Out-String) #Constructs a list of members for each group
            Send-MailMessage -SmtpServer $emailServer -Subject $emailSubject -Body $emailBody -to $emailTo -From $emailFrom
        }
    }
}

#Monthly Health Check
if (((Get-Date -day 1).ToString('d')) -eq ((Get-Date).ToString('d')))
{
    $emailSubject = ("Administrator Membership Report - Monthly Health Check")
    $emailBody = ("The Administrator Membership report is currently checking the following AD groups for membership changes: " + $administratorGroups + 
                    "`nThe Administrator Membership Report is currently checking for changes to the sysadmin group on the following SQL servers: " + $internalSqlServers + $externalSqlServers)
    Send-MailMessage -SmtpServer $emailServer -Subject $emailSubject -Body $emailBody -to $emailTo -From $emailFrom
}

#check membership for administrative groups
foreach ($group in $administratorGroups)
{
    $checkMembership = Get-ADGroupMember $group | Select-Object -ExpandProperty name
    Get-MembershipChange -groupName $group -membersToCheck $checkMembership -recordPath $savedReportFolder
}
#check sysadmin members for internal SQL servers.
foreach ($sqlServer in $internalSqlServers)
{
    $checkSysadmins = Invoke-Sqlcmd -Query "EXEC sp_helpsrvrolemember 'sysadmin'" -ServerInstance $sqlServer | Select-Object -ExpandProperty membername
    Get-MembershipChange -groupName $sqlServer -membersToCheck $checkSysadmins -recordPath $savedReportFolder  
}
#check sysadmin members for external SQL servers
foreach ($sqlServer in $externalSqlServers)
{
    $checkSysadmins = Invoke-Sqlcmd -Query "EXEC sp_helpsrvrolemember 'sysadmin'" -Username $sqlUsername -Password $sqlPassword -ServerInstance $sqlServer | Select-Object -ExpandProperty membername
    Get-MembershipChange -groupName $sqlServer -membersToCheck ($checkSysadmins | Sort-Object) -recordPath $savedReportFolder  
}
