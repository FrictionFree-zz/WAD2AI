#
# This script will configure your Azure Cloud Service (Web or Worker role) to send Azure Diagnostics telemetry to Visual Studio Application Insights (WAD2AI).
# After a successful execution of this script, you will be able to search and analyze both Application logs as well as Windows logs through Application Insights.
# You can read more about it here: https://azure.microsoft.com/en-us/blog/azure-diagnostics-integration-with-application-insights/
#

#
# Required parameters
#
$Role_Name = ""                         # The name of the Web or Worker Role, should be like "WebRole1"
$Service_Name = ""                      # The name of the Cloud Service, should be like "my-service"  
$AzureSubscription_Name=""              # The Azure subscription in which the Cloud Service was created (co-admin permissions are required)

#
# Enabling Azure Diagnostics requires an Azure Storage Account where logs will be stored in (regardless of Application Insights).
# As the script cannot retrieve the Storage Account details configured for the Cloud Service, you'll need to provide the name and key of a Storage Account.
# This can be any Storage Account, not necessarily the one used by the Cloud Service.
#
$Diagnostics_Storage_Name = ""    # e.g. "webrolestorage"
$Diagnostics_Storage_Key =  ""    # e.g. "(truncated)+rDzuzAyYDvwDrq4Utg0hqA=="
#
# An Instrumentation Key identifies the Application Insights resource to which your Azure Diagnostics telemetry will be sent.
# Provide an existing Instrumentation Key or create a new one with one click at https://ms.portal.azure.com/?flight=1#blade/HubsExtension/Resources/resourceType/microsoft.insights%2Fcomponents

$ApplicationInsights_InstrumentationKey =""

If (($Service_Name -eq "") -Or ($Role_Name -eq "")  -Or ($AzureSubscription_Name -eq "") -Or ($Diagnostics_Storage_Name -eq "") -Or ($Diagnostics_Storage_Key -eq "") -Or ($ApplicationInsights_InstrumentationKey -eq "") )
{
    "A required paramter is missing."
    return
}

# This is where we'll keep the Azure Diagnostics Public Configuration in case you ever want to edit/reuse it
$PublicConfigPath = ".\" + $Role_Name + "_DiagPublicConfig.xml"

# Begin running the script. You'll be prompted to insert your Azure account's credentials manually. This can be changed to authenticate with a management certificate.
Add-AzureAccount 
Select-AzureSubscription $AzureSubscription_Name
$extensionContext = Get-AzureServiceDiagnosticsExtension –ServiceName $Service_Name -Slot ‘Production’ -Role $Role_Name 


if($extensionContext.PublicConfiguration)
{
    # Extract the current/existing Public Configuration and save it to disk so we can update it
    $config_type = "Existing"
    $publicConfiguration = '<?xml version="1.0" encoding="utf-8"?>' + "`r`n"  + $extensionContext.PublicConfiguration
    $publicConfiguration | Out-File -Encoding utf8 -FilePath $PublicConfigPath
}
else 
{
    # Enable WAD2AI with default Azure Diagnostics settings
    $config_type = "Template"
    $PublicConfigPath = ".\DiagPublicConfigTemplateCS.xml"
    "Since Azure Diagnostics is not currently enabled on $Role_Name, we'll be using a template from $PublicConfigPath"
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
$doc.PublicConfig.WadCfg.DiagnosticMonitorConfiguration.SetAttribute(“sinks”,”ApplicationInsights.MyLogData”)

# Delete all existing sinks and recreate...
if ($doc.PublicConfig.WadCfg.SinksConfig)
{
    $doc.PublicConfig.WadCfg.RemoveChild($doc.PublicConfig.WadCfg.SinksConfig)
}

$child = $doc.CreateElement("SinksConfig")
$child.SetAttribute("xmlns", ”http://schemas.microsoft.com/ServiceHosting/2010/10/DiagnosticsConfiguration")
$child.InnerXml = $x.InnerXml
$doc.PublicConfig.WadCfg.AppendChild($child)
$doc.Save($PublicConfigPath)

# Update the Diagnostics Extension's configuration
Set-AzureServiceDiagnosticsExtension -DiagnosticsConfigurationPath $PublicConfigPath –ServiceName $Service_Name -Slot ‘Production’ -Role $Role_Name -StorageAccountName $Diagnostics_Storage_Name -StorageAccountKey $Diagnostics_Storage_Key

# Finally, report this action in your application log
$uri = "http://dc.services.visualstudio.com/v2/track"
$ikeys_array = @($ApplicationInsights_InstrumentationKey)
$json_str = '{"time":"","iKey":"","name":"Microsoft.ApplicationInsights.Event","tags":{"ai.device.type":"PC","ai.internal.sdkVersion":"PowerShell:raw","ai.user.id":"","ai.operation.name":"wad2ai"},"data":{"baseType":"EventData","baseData":{"ver":2,"name":"WAD2AI enabled successfully","properties":{"RoleName":"", "Settings":""}}}}'
$body = $json_str | ConvertFrom-Json
$body.time = ((get-date).ToUniversalTime()).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
$body.tags.'ai.user.id' = $env:COMPUTERNAME
$body.data[0].baseData.properties.RoleName = $Role_Name
$body.data[0].baseData.properties.Settings = $config_type

foreach ($ikey in $ikeys_array) {
	$body.ikey = $ikey
	$json_str = $body | ConvertTo-Json -Depth 3
	Invoke-RestMethod -Method Post -Uri $uri -Body $json_str
}
