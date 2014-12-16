###########################################################################################################
###########################################################################################################
###########################################################################################################
#######################################    CONFIGURATION           ########################################
###########################################################################################################
###########################################################################################################
###########################################################################################################

#this script migrates a data from one sql azure database to another and can migrate between azure subscriptions
#we use this as part of our build process from production to qa before running regression tests
#current limitations, only supports 2 servers, non transactional, make sure you install certificates and correctly insert thumbprints
#USAGE -> fill out config and credentials, script returns 1 if ok and 0 if error if you are piping
--------------------------------------------------------------------------------

#Config
$srcServer = 'server1.database.windows.net'
$dstServer = 'server2.database.windows.net'
$StorageName = 'name_of_my_store'
$StorageKey = 'key for my storage'
$ContainerName = 'container name'

#configure src and destination databases here with matching array indexes - databases must already exist.
$srcDatabaseNames = 'src db1', 'src db2','src db 3'
$dstDatabaseNames = 'dst db1', 'dst db2', 'dst db3' 

#subscription stuff
$srcSubId = 'source subscription id'
$dstSubId = 'dst subscription id'
$thumbprint = 'certificate thumbprint'

$myCert = Get-Item Cert:\LocalMachine\Root\$thumbprint
Set-AzureSubscription -SubscriptionName "srcSubscription" -SubscriptionId $srcSubId -Certificate $myCert
Set-AzureSubscription -SubscriptionName "dstSubscription" -SubscriptionId $dstSubId -Certificate $myCert

$dstusername = "dst db username"
$password = "dbpassword"
$secstr = New-Object -TypeName System.Security.SecureString
$password.ToCharArray() | ForEach-Object {$secstr.AppendChar($_)}
$srcCred = new-object -typename System.Management.Automation.PSCredential -argumentlist $srcUsername, $secstr
$dstCred = new-object -typename System.Management.Automation.PSCredential -argumentlist $dstusername, $secstr






#########################################################################################################
##################################     END OF CONFIGURATION           ###################################
#########################################################################################################

$ErrorActionPreference = "Stop"
Select-AzureSubscription -SubscriptionName "srcSubscription"
$srcSqlCtx = New-AzureSqlDatabaseServerContext -FullyQualifiedServerName $srcServer -Credential $srcCred
Select-AzureSubscription -SubscriptionName "dstSubscription"
$dstSqlCtx = New-AzureSqlDatabaseServerContext -FullyQualifiedServerName $dstServer -Credential $dstCred
$StorageCtx = New-AzureStorageContext -StorageAccountName $StorageName -StorageAccountKey $StorageKey
$Container = Get-AzureStorageContainer -Name $ContainerName -Context $StorageCtx
$BlobPostfix = [string]::Concat('_',(Get-Date -Format yyyy-MM-dd_HH-mm-ss).ToString(), '.bacpac')

Function Start-Backup
{
    [CmdletBinding()]
    param (
        [string] $dbname,
        [string] $blob
    )

    $request = Start-AzureSqlDatabaseExport -SqlConnectionContext $srcSqlCtx -StorageContainer $Container -DatabaseName $dbname -BlobName $blob
    write-host( $exportRequest )
    
    Check-Task($request)

}

Function Start-Restore
{
    [CmdletBinding()]
    param (
        [string] $dbname,
        [string] $blob
    )
    
    #dumb api doesn't support overwrite so have to delete it first.
    Remove-AzureSqlDatabase -ConnectionContext $dstSqlCtx -DatabaseName $dbname -Force 

    $request = Start-AzureSqlDatabaseImport -SqlConnectionContext $dstSqlCtx -StorageContainer $Container -DatabaseName $dbName -BlobName $blob
    Check-Task($request)

}

Function Check-Task([Microsoft.WindowsAzure.Commands.SqlDatabase.Services.ImportExport.ImportExportRequest] $request)
{    
    do
    {
        $status = Get-AzureSqlDatabaseImportExportStatus -Request $request
        Write-Host($status.status,' (the progress on this API is horribly inaccurate)')
        sleep -Seconds 15
    }
    while($status.status -notmatch "Completed")
}


#Control logic aka main
TRY
{
    for($i=0; $i -ilt $srcDatabaseNames.Count; $i++)
    {
        $BlobName = [string]::Concat("copy/", $srcDatabaseNames[$i], $BlobPostfix)
        Write-Host
        Write-Host('BACKING UP ', ($srcDatabaseNames[$i]))
        Write-Host('------> using blob', $BlobName)
        Start-Backup $srcDatabaseNames[$i] $BlobName
        Write-Host("RESTORING ", ($dstDatabaseNames[$i]))
        Write-Host('------>using blob', $BlobName)
        Start-Restore $dstDatabaseNames[$i] $BlobName
        echo 'RESTORE SUCCESSFUL'
        Write-Host        
    }
}
CATCH
{
    Write-Host
    Write-Host '!!!!FAILURE!!!!' -foregroundcolor red -backgroundcolor yellow
    Write-Host $_ -foregroundcolor red -backgroundcolor yellow
    exit 1;
}

exit 0
