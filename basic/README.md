# Anforderungen
Dein Kunde möchte eine REST API zum Anzeigen und Downloaden von manuell bereitgestellten Files anbieten können. Folgende Anforderungen sind formuliert:

- Die Route GET `/files` listet alle verfügbaren Dateien inklusive einem Download-Link der Datei
- Der Download-Link ist jeweils nur für 5 Minuten gültig
- Die Implementation verzichtet im ersten Ausarbeitungsschritt auf Monitoring- und Sicherheitsaspekte, welche einen Mehraufwand bedeuten (d.h. einfachste Lösung genügt)

Ein erster Architektur Entwurf:

![Architektur-Basic](../doc/Architektur-Basic.drawio.png)

# Guide
Diese Challenge ist nicht als komplettes Copy-Paste Tutorial konzipiert. Sie kann verschieden gelöst werden. Nachfolgend ist ein möglicher Lösungsweg grob skizziert, bei welchem Code-Bestandteile nicht selbst erstellt werden müssen.

1. Resource Group erstellen

   Tipp Naming: https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming
   Tipp Region: Achte immer darauf was konfiguriert ist. Generell sollten alle Ressourcen wenn möglich in der gleichen Region erstellt werden. `Switzerland North` ist eine gute Wahl (fast alles Services verfügbar)

1. Storage Account erstellen

   - Hinweis: Standard/LRS ist ausreichend

1. Blob Container erstellen

   - Empfehlung: Name des Containers = files
   - Hinweis: Dies kann direkt auf dem Storage Account, sowohl im Bereich `Containers` (unter `Data Storage`) als auch im `Storage browser` gemacht werden

1. Ein paar beliebige Files in den Blob Container hochladen

   - Empfehlung: Im Verzeichnis `doc` dieses Repositories liegen ein paar Bilder...
   - Hinweis: Dies kann direkt auf dem Storage Account, sowohl im Bereich `Containers` (unter `Data Storage`) als auch im `Storage browser` gemacht werden

1. Function App erstellen und Storage Account referenzieren

   - Consumption Plan
   - Runtime Stack je nach gewünschter Code Language: https://learn.microsoft.com/en-us/azure/azure-functions/supported-languages#language-support-details (Hinweis: `In-Portal Editing` in referenzierter Tabelle bedeutet, dass direkt im Portal ohne weitere Tools programmiert werden kann)
   - Für die Nutzung der bereitgestellten Code Snippets wähle: Publish = Code, Runtime Stack = .NET, Version = 6 (LTS), Operating System = (egal)
   - Application Insights muss nicht generiert werden

1. Connection zu Storage Account in Function App konfigurieren

   - Kopiere den Connection String in den Zwischenspeicher. Du findest ihn auf dem Storage Account unter `Access keys` (unter key1 -> Show)
   - Navigiere bei der Function App in den Bereich `Configuration`
   - Erstelle ein neuer Eintrag unter `Application Settings`
     - Name = StorageConnectionString
     - Value = (der Connection String aus dem Zwischenspeicher)

   .

   _Wurde die Function App nicht schon beim Deployment mit dem Storage Account verknüpft?_
   > Stimmt, eine Function App im Consumption & Premium Plan erfordert zwingend einen Storage Account, so dass bei Skalierungsoperationen und im Standby der Memory Stack persistiert werden kann. Generell wird [nicht empfohlen, den gleichen Storage Account auch für andere (fachliche) Zwecke](https://learn.microsoft.com/en-us/azure/azure-functions/storage-considerations) zu nutzen. Daran muss man sich nicht immer halten, jedoch sollte zumindest immer eine eigene Konfiguration verwendet werden, so dass Anpassungen in späteren Phasen einfach vollziehbar sind.

1. Weitere Konfigurationen in Function App vornehmen

   - Name des Containers im Storage Account welcher die Files enthält:
     - Name = StorageBlobContainer
     - Value = files
   - Name der Metrik welche wir für die Benachrichtigung überwachen wollen:
     - Name = DownloadMetricName
     - Value = Download

1. Function für Files Listing erstellen

   - Dies kann direkt auf der Function App im Bereich `Functions` gemacht werden
   - Für die Nutzung der bereitgestellten Code Snippets wählen:
     - Development Environment = Develop in portal
     - Template = HTTP Trigger
     - New Function (entspricht Name) = ListFiles
     - Authorization level = Anonymous
   - In der erstellten Function unter `Integration` beim Trigger folgendes konfigurieren:
     - Route template = files
     - Selected HTTP methods = GET
   - Unter `Code + Test` mittels Upload die beiden Files unter `source/list-files` hochladen:
     - [`function.proj`](./source/list-files/function.proj)
     - [`run.csx`](./source/list-files/run.csx)
   - Hinweis: Leider klappt obiger Schritt nicht immer vollständig. Falls die Files nach dem Upload leer sind, muss der Inhalt manuell mittels Copy & Paste reinkopiert werden.

# Direkt zur Lösung

Wir empfehlen erste Schritte manuell im Azure Portal auszuführen. So wird man mit den Strukturen vertraut und bekommt Routine mit der teils gewöhnungsbedürftigen Navigation (dafür ist man beispielweise in Debugging Situationen froh). Wenn man Services manuell und step-by-step deployed, lassen sich Abhängigkeiten, Relationen und Sub-Komponenten leicht erkennen. Infrastructure as Code und Deployment Automatisierung ist gut und wichtig - aber man sollte verstehen was man dabei macht.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fiptch%2F2023-05-techbier-azure-basics%2Fmain%2Fbasic%2Fdeployment%2Fazuredeploy.json)
