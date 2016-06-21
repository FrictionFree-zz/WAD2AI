#
# This script will wire your VM to send diagnostics data to Microsoft Application Insights. After a successful execution of this script you will
# be able to search and analyze both Application logs as well as Windows logs through Application Insights. You can read more about it here 
#

#
# Required parameters
#
$VM_name = ""                 # Name of the VM
$Service_Name = ""            # a.k.a Deployment Name
$AzureSubscriptionName=""     # Subscription hosting the VM (you'll need co-admin permissions)

#
# Enabling Azure Diagnostics requires a storage account to where logs will be stored (regardless of Application Insights).
# The script can not fetch the storage account and key that are already configured so you'll need provide a storage name and key. 
# Can be on any subscription, not neccessarily where the VM is.
#
$Diagnostics_Storage_Name = ""    
$Diagnostics_Storage_Key = ""
#
# Instrumentation Key identifies the Application Insights resource to which your logs will get sent.
# Provide an existing Instrumentation Key or create a new one with one click at https://ms.portal.azure.com/?flight=1#blade/HubsExtension/Resources/resourceType/microsoft.insights%2Fcomponents
#
$ApplicationInsightsInstrumentationKey =""

If (($Service_Name -eq "") -Or ($VM_name -eq "") -Or ($VM_name -eq "") -Or ($AzureSubscriptionName -eq "") -Or ($Diagnostics_Storage_Name -eq "") -Or ($Diagnostics_Storage_Key -eq "") -Or ($ApplicationInsightsInstrumentationKey -eq "") )
{
    "Required run-time paramter is missing."
    return
}

#
# This is where we'll keep the Azure Diagnostics Public Configuration in case you ever want to edit/reuse it
#
$PublicConfigPath = ".\" + $VM_name + "_DiagPublicConfig.xml"

# Let's roll the execution. Insert credentials manually. Can be changed to authenticate with a management cert.
Add-AzureAccount 
Select-AzureSubscription $AzureSubscriptionName
$VM = Get-AzureVM -ServiceName $Service_Name -Name $VM_name
$extensionContext = Get-AzureVMDiagnosticsExtension -VM $VM
$publicConfiguration = $extensionContext.PublicConfiguration | ConvertFrom-Json

#
# Extract the current/existing Public Configuration and save it to disk so we can patch it
#
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($publicConfiguration.xmlcfg)) | Out-File -Encoding utf8 -FilePath $PublicConfigPath

# 
# Go ahead and update the Public Configuration to enable ingestion of WAD into Application Insights.
# These setting would make decent defaults for sending data to AI, but you can change the verbosity levels if you like.
# For more info about how to edit Application Insights ingestion through Azure Diagnostics please read here
# https://azure.microsoft.com/en-us/documentation/articles/azure-diagnostics-configure-applicationinsights/
# 
[xml] $x ='<Sink name="ApplicationInsights">
        <ApplicationInsights>' + $ApplicationInsightsInstrumentationKey + '</ApplicationInsights>
        <Channels>
        <Channel logLevel="Error" name="MyTopDiagData"  />
        <Channel logLevel="Verbose" name="MyLogData"  />
        </Channels>
    </Sink>'

[xml] $doc = Get-Content($PublicConfigPath)
#
# Check if Application Insights is already enabled for Diagnostics on this VM and exit if so.
# TODO: Deal with cases where AI config is wrong or incomplete. For now we'll just avoid double enablement.
#
$sinks = $doc.WadCfg.DiagnosticMonitorConfiguration.GetAttribute(“sinks”)
ForEach ($_ in $sinks) {
    if ($_ -icontains ”ApplicationInsights.MyLogData”)
    {
        "Application Insights is already enabled for diagnostics on $VM_Name"
        return
    }
}
$doc.WadCfg.DiagnosticMonitorConfiguration.SetAttribute(“sinks”,”ApplicationInsights.MyLogData”)
$child = $doc.CreateElement("SinksConfig")
$child.InnerXml = $x.InnerXml
$doc.WadCfg.AppendChild($child)
$doc.Save($PublicConfigPath)

# 
# Finally, update the Diagnostics Extension configuration
#
$VM_update = Set-AzureVMDiagnosticsExtension -DiagnosticsConfigurationPath $PublicConfigPath -Version "1.*" -VM $VM -StorageAccountName $Diagnostics_Storage_Name -StorageAccountKey $Diagnostics_Storage_Key
Update-AzureVM -ServiceName $Service_Name -Name $VM_Name -VM $VM_Update.VM

