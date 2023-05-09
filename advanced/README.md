# Anforderungen
Dein Kunde möchte eine REST API zum Anzeigen und Downloaden von manuell bereitgestellten Files anbieten können. Folgende Anforderungen sind formuliert:

- Die Route GET `/files` listet alle verfügbaren Dateien auf (nur Namen)
- Die Route GET `/files/{filename}` liefert Detaileigenschaften sowie einen Download-Link der Datei
- Der Download-Link ist jeweils nur für 5 Minuten gültig
- Die API Requests können einfach statistisch ausgewertet werden, d.h. wie viele Anfragen in welchem Zeitraum getätigt werden
- Wenn mehr als 5 Detailabfragen pro Stunde erfolgen, erfolgt eine Benachrichtigung per Email (für Entwicklung kann diese frei gewählt werden)
- Die Implementation erfolgt nach den Zero Trust Prinzipen, verzichtet aber im ersten Ausarbeitungsschritt auf Netzwerksicherheit und User-Authentifikation

Ein erster Architektur Entwurf:

![Architektur-Advanced](../doc/Architektur-Advanced.drawio.png)

# Guide
Diese Challenge ist nicht als komplettes Copy-Paste Tutorial konzipiert. Sie kann verschieden gelöst werden. Nachfolgend ist ein möglicher Lösungsweg grob skizziert, bei welchem Code-Bestandteile nicht selbst erstellt werden müssen.

1. Resource Group erstellen

   Tipp Naming: https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming
   Tipp Region: Achte immer darauf was konfiguriert ist. Generell sollten alle Ressourcen wenn möglich in der gleichen Region erstellt werden. `Switzerland North` ist eine gute Wahl (fast alles Services verfügbar)

1. Log Analytics Workspace erstellen

1. Application Insights erstellen und Workspace referenzieren

1. Storage Account erstellen

   - Hinweis: Standard/LRS ist ausreichend

1. Blob Container erstellen

   - Empfehlung: Name des Containers = files
   - Hinweis: Dies kann direkt auf dem Storage Account, sowohl im Bereich `Containers` (unter `Data Storage`) als auch im `Storage browser` gemacht werden

1. Ein paar beliebige Files in den Blob Container hochladen

   - Empfehlung: Im Verzeichnis `doc` dieses Repositories liegen ein paar Bilder...
   - Hinweis: Dies kann direkt auf dem Storage Account, sowohl im Bereich `Containers` (unter `Data Storage`) als auch im `Storage browser` gemacht werden

1. Function App erstellen und Application Insights / Storage Account referenzieren

   - Consumption Plan
   - Runtime Stack je nach gewünschter Code Language: https://learn.microsoft.com/en-us/azure/azure-functions/supported-languages#language-support-details (Hinweis: `In-Portal Editing` in referenzierter Tabelle bedeutet, dass direkt im Portal ohne weitere Tools programmiert werden kann)
   - Für die Nutzung der bereitgestellten Code Snippets wähle: Publish = Code, Runtime Stack = .NET, Version = 6 (LTS), Operating System = Windows

1. Auf Function App die (System-assigned) Managed Identity aktivieren

1. Key Vault erstellen

   - Hinweis: Standard ist ausreichen und Purge Protection wird in diesem Use Case nicht benötigt
   - Access Policy für Function App erstellen: Permission `Secret/Get`
   - Access Policy für aktuellen User erstellen (bzw. editieren): Permissions `Secret/(alle)`

   .

   _Ist der Key Vault hierfür notwendig?_
   > Nein. Eine alternative Lösung wäre, die Managed Identity der Function direkt für den Storage Account zu berechtigen. Dies ist oft schlanker und in der Realität oft die präferierte Lösung (nachteilig ist aber, dass das Deployment mit hohen Privileges laufen muss).

1. Secret mit für die Connection zum Storage Account anlegen

   - Kopiere den Connection String in den Zwischenspeicher. Du findest ihn auf dem Storage Account unter `Access keys` (unter key1 -> Show)
   - Erstelle im Key Vault unter `Objects` -> `Secrets` einen neuen Eintrag:
     - Name = StorageConnectionString
     - Secret value = (der Connection String aus dem Zwischenspeicher)

   - Hinweis: Falls du keine Rechte zum Erstellen von Secrets haben solltest, dann erstelle für dich unter `Access policies` einen neuen Eintrag

1. Connection zu Storage Account in Function App konfigurieren

   - Navigiere bei der Function App in den Bereich `Configuration`
   - Erstelle ein neuer Eintrag unter `Application Settings`
     - Name = StorageConnectionString
     - Value = @Microsoft.KeyVault(VaultName=kv-tb-azbasics-jsc;SecretName=StorageConnectionString)
   - Falls ein grünes Check-Icon in der Source Column erscheint, dann klappt die Verbindung

   .

   _Wie funktioniert dies?_
   > Mit dieser Syntax greift die Function App beim Initialisieren, resp. danach ca. alle 15 Minuten, direkt auf das Secret im Key Vault zu. Dabei authentifiziert sie sich mittels Managed Identity beim Key Vault. Das Schöne daran ist: Im Code muss keine Integration mehr gemacht werden, Secrets können so analog anderer Konfigurationen direkt genutzt werden. Mehr dazu: https://learn.microsoft.com/en-us/azure/app-service/app-service-key-vault-references
   
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
   - Hinweis: Leider funktioniert obiger Schritt nicht immer vollständig. Falls die Files nach dem Upload leer sind, muss der Inhalt manuell mittels Copy & Paste reinkopiert werden.

1. Function für Download Detail eines Files erstellen

   - (analog oben)
   - Für die Nutzung der bereitgestellten Code Snippets wählen:
     - Development Environment = Develop in portal
     - Template = HTTP Trigger
     - New Function (entspricht Name) = GetFile
     - Authorization level = Anonymous
   - In der erstellten Function unter `Integration` beim Trigger folgendes konfigurieren:
     - Route template = files/{filename}
     - Selected HTTP methods = GET
   - Unter `Code + Test` mittels Upload die beiden Files unter `source/list-files` hochladen:
     - [`function.proj`](./source/get-file/function.proj)
     - [`run.csx`](./source/get-file/run.csx)
   - Hinweis: Leider funktioniert obiger Schritt nicht immer vollständig. Falls die Files nach dem Upload leer sind, muss der Inhalt manuell mittels Copy & Paste reinkopiert werden.

1. Die Functions testen um Monitoring Daten zu generieren
   
1. Metriken in Application Insights analysieren

   - Hinweis: Es kann 2-3 Minuten dauern, bis die Daten im Application Insights verfügbar sind
   - Navigiere in der Application Insights Instanz zu `Monitoring` -> `Metrics`
   - Selektiere im Namespace `Log-based metrics` die Metric `Download` (im Bereich `Custom`) und aggregiere mittels Summe

1. Alert Rule inklusive einer Action Group für Email Notifikation erstellen

   - Grundsätzlich kann direkt aus obigem Bereich mittels `New alert rule` eine Benachrichtigung erstellt werden. Nur erscheint manchmal ein falscher Fehler, der sich wie folgt lösen lässt:
     - Condition / Signal name = Download
     - Condition / Treshold = Static
     - Condition / Aggregation type = Total (entspricht Sum)
     - Condition / Operator = Greater than
     - Condition / Treshold value = 5
     - Condition / Check every = 30 minutes
     - Condition / Lookback period = 1 hour
     - Action / -> Create Action Group (selbsterklärend)

# Direkt zur Lösung

Wir empfehlen erste Schritte manuell im Azure Portal auszuführen. So wird man mit den Strukturen vertraut und bekommt Routine mit der teils gewöhnungsbedürftigen Navigation (dafür ist man beispielweise in Debugging Situationen froh). Wenn man Services manuell und step-by-step deployed, lassen sich Abhängigkeiten, Relationen und Sub-Komponenten leicht erkennen. Infrastructure as Code und Deployment Automatisierung ist gut und wichtig - aber man sollte verstehen, was man dabei macht.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fiptch%2F2023-05-techbier-azure-basics%2Fmain%2Fadvanced%2Fdeployment%2Fazuredeploy.json)
