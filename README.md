# WAD2AI
This repo hosts tools and snippets to make it super easy for people to wire application and infra logs from an Azure VM into Appliction Insights. Once your logs are in Application Insights there's no limit to your debugging and analytics capabilities!
The repo is open for contributions.

The scenario enhanced by tools in this repo:
1. You have a Windows VM running in Azure hosting some kind of app, it could be an app that you wrote yourself or it can be a custom deployment of SQL, Exchange, AD etc
2. You wire up your VM to send all the application and infra (Windows Event Logs, Performance Counters) to Microsoft Application Instance
3. You use the capabilities of Application Inisghts to monitor your app (e.g. metric based alerts) and debug your app using the rich log analytics query languance (filtering, aggregations, table joins and more)

EnableWAD2AI_VM.ps1 is a script that completely automates the process of wiring up an existing VM in Azure into an existing Application Insights instance. If you don't yet have an AI instance, it is super easy to create one here for free: https://ms.portal.azure.com/?flight=1#blade/HubsExtension/Resources/resourceType/microsoft.insights%2Fcomponents

After running the script you can start seeing your application logs and diagnostics data in the Azure Portal: https://ms.portal.azure.com/?flight=1&nocdn=true#blade/HubsExtension/Resources/resourceType/microsoft.insights%2Fcomponents


