#
# This script will configure your Azure VM to send Azure Diagnostics telemetry to Visual Studio Application Insights (WAD2AI).
# After a successful execution of this script, you will be able to search and analyze both Application logs as well as Windows logs through Application Insights.
# You can read more about it here: https://azure.microsoft.com/en-us/blog/azure-diagnostics-integration-with-application-insights/
#

#
# Required parameters
#
$VM_Name = ""                                   # The name of the VM, e.g "yossia-sql-vm5"     
$AzureSubscriptionName=""                       # The name of the Azure subscription hosting the VM (co-admin permissions are needed)

#
# Mutually exclusive parameters
# This script supports configuring VMs that were provisioned by Azure Resource Manager as well as in the "Classic" way.
#
$Service_Name = ""                              # For Classic mode, specify the deployment name of the VM, e.g  "yossia-sql-vm57953"
$ResourceGroup_Name= ""                         # For ARM mode, specify the resource group name, e.g  "yossia-west-us"

#
# Enabling Azure Diagnostics requires an Azure Storage Account where logs will be stored in (regardless of Application Insights).
# As the script cannot retrieve the Storage Account details configured for the Cloud Service, you'll need to provide the name and key of a Storage Account.
# This can be any Storage Account, not necessarily the one used by the Cloud Service.
#
$Diagnostics_Storage_Name = ""    # e.g. "vmstorage"
$Diagnostics_Storage_Key =  ""    # e.g. "(truncated)+rDzuzAyYDvwDrq4Utg0hqA=="
#
# An Instrumentation Key identifies the Application Insights resource to which your Azure Diagnostics telemetry will be sent.
# Provide an existing Instrumentation Key or create a new one with one click at https://ms.portal.azure.com/?flight=1#blade/HubsExtension/Resources/resourceType/microsoft.insights%2Fcomponents

$ApplicationInsights_InstrumentationKey =""  # e.g. "ad65d3b2-b50e-46ab-a0da-e7873feba7fd"

If (($VM_Name -eq "") -Or ($AzureSubscriptionName -eq "") -Or ($Diagnostics_Storage_Name -eq "") -Or ($Diagnostics_Storage_Key -eq "") -Or ($ApplicationInsights_InstrumentationKey -eq "") )
{
    "A required paramter is missing."
    return
}

If (($Service_Name -eq "") -And ($ResourceGroup_Name) -eq "")
{
    "Missing paramter: please specify either the Service Name or Resource Group Name"
    return
}

# This is where we'll keep the Azure Diagnostics Public Configuration in case you ever want to edit/reuse it
$PublicConfigPath = ".\" + $VM_Name + "_DiagPublicConfig.xml"

# Begin running the script. You'll be prompted to insert your Azure account's credentials manually. This can be changed to authenticate with a management certificate.
If (!($Service_Name -eq ""))
{
    # Classic mode
    Add-AzureAccount 
    Select-AzureSubscription $AzureSubscriptionName
    $VM = Get-AzureVM -ServiceName $Service_Name -Name $VM_Name
    $extensionContext = Get-AzureRVMDiagnosticsExtension -VM $VM
    $PublicConfigEncoded = $extensionContext.PublicConfiguration
}
Else 
{
    # ARM mode
    Add-AzureRmAccount 
    Select-AzureRmSubscription -SubscriptionName $AzureSubscriptionName
    $extensionContext = Get-AzureRmVMDiagnosticsExtension -VMName $VM_Name -ResourceGroupName $ResourceGroup_Name
    $PublicConfigEncoded = $extensionContext.PublicSettings
}


if($PublicConfigEncoded)
{
    # Extract the current/existing Public Configuration and save it to disk so we can update it
	$config_type = "Existing"
    $publicConfiguration = $PublicConfigEncoded | ConvertFrom-Json
    [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($publicConfiguration.xmlcfg)) | Out-File -Encoding utf8 -FilePath $PublicConfigPath
}
else 
{
    # Enable WAD2AI with default Azure Diagnostics settings
	$config_type = "Template"
    $PublicConfigPath = ".\DiagPublicConfigTemplateVM.xml"
    "Since Azure Diagnostics is not currently enabled on $VM_Name, we'll be using a template at $PublicConfigPath"
}

# All is set, let's go ahead and update the Public Configuration to enable ingestion of Azure Diagnostics into Application Insights.
# These setting would make decent defaults for sending data to Application Insights, but you can change the verbosity levels if you'd like.
# For more info about how to edit Application Insights ingestion through Azure Diagnostics, please read here:
# https://azure.microsoft.com/en-us/documentation/articles/azure-diagnostics-configure-applicationinsights/
[xml] $x ='<Sink name="ApplicationInsights">
        <ApplicationInsights>' + $ApplicationInsights_InstrumentationKey + '</ApplicationInsights>
        <Channels>
        <Channel logLevel="Error" name="MyTopDiagData"  />
        <Channel logLevel="Verbose" name="MyLogData"  />
        </Channels>
    </Sink>'

[xml] $doc = Get-Content($PublicConfigPath) 
$doc.WadCfg.DiagnosticMonitorConfiguration.SetAttribute(“sinks”,”ApplicationInsights.MyLogData”)

# Delete all existing sinks and recreate...
if ($doc.WadCfg.SinksConfig)
{
    $doc.WadCfg.RemoveChild($doc.WadCfg.SinksConfig)
}

$child = $doc.CreateElement("SinksConfig")
$child.SetAttribute("xmlns", ”http://schemas.microsoft.com/ServiceHosting/2010/10/DiagnosticsConfiguration")
$child.InnerXml = $x.InnerXml
$doc.WadCfg.AppendChild($child)
$doc.Save($PublicConfigPath)

# Update the Diagnostics Extension's configuration
If (!($Service_Name -eq ""))
{
    # Classic mode
    $VM_update = Set-AzureVMDiagnosticsExtension -DiagnosticsConfigurationPath $PublicConfigPath -Version "1.*" -VM $VM -StorageAccountName $Diagnostics_Storage_Name -StorageAccountKey $Diagnostics_Storage_Key
    Update-AzureVM -ServiceName $Service_Name -Name $VM_Name -VM $VM_Update.VM
}
Else
{
    # ARM mode
    Set-AzureRmVMDiagnosticsExtension -ResourceGroupName $ResourceGroup_Name -DiagnosticsConfigurationPath $PublicConfigPath -VMName $VM_Name -StorageAccountName $Diagnostics_Storage_Name -StorageAccountKey $Diagnostics_Storage_Key
}

# Finally, report this action in your application log
$uri = "http://dc.services.visualstudio.com/v2/track"
$ikeys_array = @($ApplicationInsights_InstrumentationKey)
$json_str = '{"time":"","iKey":"","name":"Microsoft.ApplicationInsights.Event","tags":{"ai.device.type":"PC","ai.internal.sdkVersion":"PowerShell:raw","ai.user.id":"","ai.operation.name":"wad2ai"},"data":{"baseType":"EventData","baseData":{"ver":2,"name":"WAD2AI enabled successfully","properties":{"VMName":"", "Settings":""}}}}'
$body = $json_str | ConvertFrom-Json
$body.time = ((get-date).ToUniversalTime()).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
$body.tags.'ai.user.id' = $env:COMPUTERNAME
$body.data[0].baseData.properties.VMName = $VM_Name
$body.data[0].baseData.properties.Settings = $config_type

foreach ($ikey in $ikeys_array) {
	$body.ikey = $ikey
	$json_str = $body | ConvertTo-Json -Depth 3
	Invoke-RestMethod -Method Post -Uri $uri -Body $json_str
}



