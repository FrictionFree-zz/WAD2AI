#
# This script will wire your Azure Cloud Service (Web/Worker Roles) to send diagnostics data to Microsoft Application Insights. After a successful execution of this script you will
# be able to search and analyze both Application logs as well as Windows logs through Application Insights. You can read more about it here 
# https://azure.microsoft.com/en-us/blog/azure-diagnostics-integration-with-application-insights/
#

#
# Required parameters
#
$Role_name = ""                         # Name of the CS Role, should be like "WebRole1"
$Service_Name = ""                      # short name of the cloud service, should be like "harelbr-app"  
$AzureSubscriptionName=""               # Subscription hosting the CS (co-admin permissions are needed)

#
# Enabling Azure Diagnostics requires a storage account to where logs will be stored (regardless of Application Insights).
# The storage account and key do not have to match the preconfigured set.
# Storage account can be on any subscription, not neccessarily where the VM is.
#
$Diagnostics_Storage_Name = ""    # e.g "webroleforwad"
$Diagnostics_Storage_Key =  ""    # "(truncated)+rDzuzAyYDvwDrq4Utg0hqA=="
#
# Instrumentation Key identifies the Application Insights resource to which your logs will get sent.
# Provide an existing Instrumentation Key or create a new one with one click at https://ms.portal.azure.com/?flight=1#blade/HubsExtension/Resources/resourceType/microsoft.insights%2Fcomponents

$ApplicationInsightsInstrumentationKey =""

If (($Service_Name -eq "") -Or ($Role_name -eq "")  -Or ($AzureSubscriptionName -eq "") -Or ($Diagnostics_Storage_Name -eq "") -Or ($Diagnostics_Storage_Key -eq "") -Or ($ApplicationInsightsInstrumentationKey -eq "") )
{
    "Required run-time paramter is missing."
    return
}

# This is where we'll keep the Azure Diagnostics Public Configuration in case you ever want to edit/reuse it
$PublicConfigPath = ".\" + $Role_name + "_DiagPublicConfig.xml"

# Enter credentials manually. Can be changed to authenticate with a management cert.
Add-AzureAccount 
Select-AzureSubscription $AzureSubscriptionName
$extensionContext = Get-AzureServiceDiagnosticsExtension –ServiceName $service_name -Slot ‘Production’ -Role $role_name 


if($extensionContext.PublicConfiguration)
{
    # Extract the current/existing Public Configuration and save it to disk so we can patch it
    $publicConfiguration = '<?xml version="1.0" encoding="utf-8"?>' + "`r`n"  + $extensionContext.PublicConfiguration
    $publicConfiguration | Out-File -Encoding utf8 -FilePath $PublicConfigPath
}
else 
{
    # Enable WAD2AI with default WAD settings
    $PublicConfigPath = ".\DiagPublicConfigTemplateCS.xml"
    "Since Azure Diagnostics is not currently enabled on $Role_name, we'll be using a template at $PublicConfigPath"
}

# All is set, let's go ahead and update the Public Configuration to enable ingestion of WAD into Application Insights.
# These setting would make decent defaults for sending data to AI, but you can change the verbosity levels if you like.
# For more info about how to edit Application Insights ingestion through Azure Diagnostics please read here
# https://azure.microsoft.com/en-us/documentation/articles/azure-diagnostics-configure-applicationinsights/
[xml] $x ='<Sink name="ApplicationInsights">
        <ApplicationInsights>' + $ApplicationInsightsInstrumentationKey + '</ApplicationInsights>
        <Channels>
        <Channel logLevel="Error" name="MyTopDiagData"  />
        <Channel logLevel="Verbose" name="MyLogData"  />
        </Channels>
    </Sink>'

[xml] $doc = Get-Content($PublicConfigPath) 

$doc.PublicConfig.WadCfg.DiagnosticMonitorConfiguration.SetAttribute(“sinks”,”ApplicationInsights.MyLogData”)

# Delete all existing sinks and recreate...
# TBD - we might be losing a non Application Inisghts sink here, but that's quite unlikely
if ($doc.PublicConfig.WadCfg.SinksConfig)
{
    $doc.PublicConfig.WadCfg.RemoveChild($doc.PublicConfig.WadCfg.SinksConfig)
}


$child = $doc.CreateElement("SinksConfig")
$child.SetAttribute("xmlns", ”http://schemas.microsoft.com/ServiceHosting/2010/10/DiagnosticsConfiguration")
$child.InnerXml = $x.InnerXml
$doc.PublicConfig.WadCfg.AppendChild($child)
$doc.Save($PublicConfigPath)


# Finally, update the Diagnostics Extension configuration
Set-AzureServiceDiagnosticsExtension -DiagnosticsConfigurationPath $PublicConfigPath –ServiceName $Service_name -Slot ‘Production’ -Role $Role_name -StorageAccountName $Diagnostics_Storage_Name -StorageAccountKey $diagnostics_storage_key