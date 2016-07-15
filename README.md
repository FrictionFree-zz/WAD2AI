# Windows Azure Diagnostics To Application Insights
This repo hosts tools and snippets to make it super easy to configure Azure Roles (Web/Worker) and VMs to send application and infra logs into Appliction Insights. Once your logs are in Application Insights, debugging and analyzing your application activities becomes a real pleasure! 

##The repo is open for contributions.

The scenario enhanced by tools in this repo:
 1. You have a Windows VM running in Azure hosting some application, it may be an app that you coded yourself or it can be a custom deployment of SQL, Exchange, AD etc. Alternatively, you may have a [PaaS Role](http://www.techrepublic.com/blog/data-center/windows-azure-web-worker-and-vm-roles-demystified/) running in Azure.
 2. Use this tool to configure your VM or CS to send all the application and infra logs (Event Source, ETW, Windows Event Logs, Performance Counters) to Microsoft Application Insights.
 3. You use the capabilities of Application Inisghts to monitor your app (e.g. metric based alerts) and debug your app using the log analytics query languance (filtering, aggregations, table joins and more)

EnableWAD2AI_VM.ps1 is a script that completely automates the process of wiring up an existing VM in Azure into an existing Application Insights instance. If you don't yet have an AI instance, it is super easy to create one [here](https://ms.portal.azure.com/?flight=1#blade/HubsExtension/Resources/resourceType/microsoft.insights%2Fcomponents) for free. 

EnableWAD2AI_CS.ps1 will do the same for a Cloud Service.

After running the script you can start seeing your application logs and diagnostics data in the [Azure Portal](https://ms.portal.azure.com/?flight=1&nocdn=true#blade/HubsExtension/Resources/resourceType/microsoft.insights%2Fcomponents). 


