# Stable-Diffusion-Cluster (CPU/GPU, Docker)

Ein einheitliches Docker-Image, das je nach Umgebungsvariable als **Bildgenerator**, als **Textmodell-Server** oder als **Rechenknecht (RPC-Worker)** startet. Damit lässt sich ein kleiner KI-Cluster auf ganz normaler Hardware betreiben – ohne CUDA und ohne zwingende NVIDIA-GPU. Vorhandene Grafikkarten (AMD, Intel, NVIDIA) werden über Vulkan genutzt, ansonsten rechnet alles auf der CPU.

---

## 1. Management Summary

### Worum geht es?

Das Projekt baut aus mehreren normalen Computern (Servern) einen gemeinsamen KI-Cluster. Auf einem Rechner läuft der „Chef" (Master), der Aufträge annimmt. Die eigentliche Rechenarbeit kann auf beliebig viele weitere Rechner ausgelagert werden. Alle Rechner benutzen **dasselbe Docker-Image**; nur eine Umgebungsvariable entscheidet, welche Aufgabe ein Rechner übernimmt.

### Die Bausteine

**llama.cpp**
Eine freie Software, die große Sprachmodelle („Large Language Models", LLM) auf gewöhnlicher Hardware laufen lässt. Bekannt ist sie vor allem durch Programme wie ChatGPT-Alternativen, die lokal auf dem eigenen Rechner antworten. `llama.cpp` ist in C++ geschrieben und auf Geschwindigkeit optimiert.

**stable-diffusion.cpp**
Das gleiche Prinzip, nur für Bilder: Aus einer Textbeschreibung („ein Hund auf einer Wiese, Ölgemälde") erzeugt die Software ein Bild. `stable-diffusion.cpp` ist die C++-Variante der bekannten Stable-Diffusion-Software und benötigt – wie `llama.cpp` – keine spezielle Grafikkarte.

**GGML-RPC (das „Nervensystem")**
Beide Programme beruhen auf derselben Rechen-Bibliothek (GGML). Diese bringt eine Funktion mit, mit der ein Rechner Teile seiner Arbeit an andere Rechner im Netzwerk weitergeben kann: RPC (Remote Procedure Call, „entfernter Funktionsaufruf"). Der Master schickt also Rechenaufträge an die Worker und bekommt die Ergebnisse zurück.

### Die drei Modi unseres Images

| Modus | Was der Container tut | Vergleich |
|---|---|---|
| **MASTER** | Nimmt Bildwünsche über eine HTTP-Schnittstelle (REST-API) entgegen und erzeugt daraus Bilder. | Der Koch, der Bestellungen annimmt. |
| **LLAMA** | Stellt ein Sprachmodell über eine HTTP-Schnittstelle bereit (Fragen beantworten, Texte schreiben). | Ein zweiter Koch für eine andere Speisekarte. |
| **RPC** | Führt Rechenaufträge aus, die ihm ein Master schickt. Hat selbst keine eigene API für Endnutzer. | Die Küchenhilfen, die zuarbeiten. |

Wichtig: Ein RPC-Worker kann sowohl dem Bild-Master als auch dem Sprach-Master zuarbeiten. Die Rollen sind also kombinierbar, und man kann mehrere Worker gleichzeitig betreiben, um mehr Leistung zu bekommen.

### Wie das zusammenspielt

```
        Bildwunsch (HTTP)                Textfrage (HTTP)
                │                               │
                ▼                               ▼
        ┌───────────────┐               ┌───────────────┐
        │ MASTER (Bild) │               │ LLAMA (Text)  │
        └───────┬───────┘               └───────┬───────┘
                │        RPC (Port 50052)       │
                └───────────────┬───────────────┘
                                ▼
              ┌─────────────────┼─────────────────┐
              ▼                 ▼                 ▼
        ┌───────────┐     ┌───────────┐     ┌───────────┐
        │ RPC-Worker│     │ RPC-Worker│     │ RPC-Worker│
        └───────────┘     └───────────┘     └───────────┘
```

### Umsetzung in Kürze

* **Ein Image, drei Rollen:** Die Umgebungsvariable `SD_ROLE` (`MASTER`, `LLAMA`, `RPC`) entscheidet beim Start, welches Programm läuft.
* **Modelle bleiben draußen:** Die eigentlichen Modelldateien werden nicht ins Image gepackt, sondern als Volume vom Host eingebunden. Das Image bleibt dadurch klein und für alle Rollen gleich.
* **Zweistufiger Build:** Das Image wird in zwei Schritten gebaut. Zuerst wird kompiliert (viel Werkzeug nötig), danach werden nur die fertigen Programme in ein schlankes Laufzeit-Image kopiert.
* **CPU zuerst, GPU optional:** Das Image enthält das Vulkan-Backend und kann damit eine vorhandene Grafikkarte (AMD, Intel oder NVIDIA) nutzen. Ist keine GPU vorhanden oder kein Treiber durchgereicht, rechnet die Software automatisch auf der CPU weiter. Das Image bleibt dadurch auf praktisch jeder Hardware lauffähig.
* **Web-Oberfläche inklusive:** Das Image bringt die offizielle Weboberfläche des Bild-Servers mit. Sie ist nach dem Start unter `http://<master>:8080/` erreichbar und wird direkt aus dem Programm ausgeliefert (kein zusätzlicher Webserver nötig).

### Was das System nicht leistet

* Der RPC-Dienst besitzt **keine Authentifizierung und keine Verschlüsselung**. Er darf nur in einem vertrauenswürdigen, internen Netz betrieben werden.
* Es ist kein Hochverfügbarkeits-Cluster: Fällt ein Worker aus, schlägt die Arbeit fehl, die ihm zugewiesen wurde.

---

## 2. Übersicht für Administratoren

### 2.1 Voraussetzungen

| Punkt | Anforderung |
|---|---|
| Docker | Auf **allen** Hosts installiert (Docker Engine ≥ 24 empfohlen). |
| Image-Version | Auf **allen** Hosts exakt dieselbe Image-Version. Das RPC-Protokoll ist versionsgebunden; gemischte Builds funktionieren nicht. |
| Netzwerk | Der Master muss die Worker auf Port **50052/tcp** erreichen. |
| Arbeitsspeicher | Ausreichend RAM für das jeweilige Modell (Bildmodelle: mehrere GB; LLMs je nach Größe). |
| Modelle | Liegen auf dem Master-Host und werden als Volume eingebunden. Die RPC-Worker benötigen **keine** Modelldateien. |
| GPU (optional) | Vulkan-fähige Grafikkarte plus Host-Treiber. NVIDIA über das `nvidia-container-toolkit`, AMD/Intel über `/dev/dri` und Mesa-Treiber. Ohne GPU läuft alles auf der CPU. |
| Sicherheit | Port 50052 **nicht** ins Internet freigeben. |

### 2.2 Image bereitstellen

Da alle Hosts dasselbe Image benötigen, gibt es drei übliche Wege:

**Variante A – auf jedem Host selbst bauen** (einfachste Variante, benötigt überall die Build-Werkzeuge):

```bash
git clone <repository-url> stable-diffusion-cluster
cd stable-diffusion-cluster
docker build -t sd-cluster .
```

Das Image wird standardmäßig **mit Vulkan** gebaut. Zwei optionale Build-Argumente:

| Build-Argument | Standard | Wirkung |
|---|---|---|
| `WITH_VULKAN` | `ON` | `OFF` baut ein reines CPU-Image (kleiner, kürzere Build-Zeit). |
| `INSTALL_MESA_VULKAN` | `false` | `true` installiert die Mesa-Vulkan-Treiber (AMD/Intel und Software-Vulkan). Zieht `libllvm19` (~125 MB) und weitere Treiberbibliotheken nach (zusammen rund 250 MB). Für NVIDIA **nicht** nötig. |

Beispiel für einen AMD/Intel-Host:

```bash
docker build --build-arg INSTALL_MESA_VULKAN=true -t sd-cluster .
```

**Variante B – einmal bauen und verteilen** (empfohlen bei vielen Hosts):

```bash
# auf einem Build-Host
docker build -t sd-cluster .
docker save sd-cluster | gzip > sd-cluster.tar.gz

# Datei auf die anderen Hosts kopieren, dort:
gunzip -c sd-cluster.tar.gz | docker load
```

**Variante C – Registry:** Image mit `docker push` in eine interne Registry schieben und auf den Hosts mit `docker pull` abholen.

> **Für AMD/Intel-GPUs:** Das Image muss einmalig mit `--build-arg INSTALL_MESA_VULKAN=true` gebaut werden (siehe oben). Das gilt dann für alle Hosts, die dieses Image verwenden.

> **Hinweis:** Der Build lädt die Quellen von GitHub sowie die Frontend-Abhängigkeiten über `pnpm` und kompiliert `stable-diffusion.cpp` und `llama.cpp` inklusive Vulkan-Shadern. Er dauert je nach CPU etwa 15–30 Minuten und benötigt temporär mehrere GB Plattenplatz.

### 2.3 Modelle ablegen

Auf dem Master-Host (Beispiel: `192.168.41.57`) ein Verzeichnis anlegen:

```
/srv/models/
├── sd_model.gguf        # Bildmodell (alternativ: .safetensors)
└── llama_model.gguf     # Sprachmodell (GGUF)
```

Das Verzeichnis wird in den Container als `/models` eingebunden. `SD_MODEL_PATH` verweist auf die Datei **innerhalb** des Containers.

### 2.4 Schritt 1: RPC-Worker starten

Auf **jedem** Worker-Host (`192.168.41.20`, `192.168.41.42`, `192.168.40.10`) den identischen Befehl ausführen:

```bash
docker run -d \
  --name sd-rpc \
  --restart unless-stopped \
  -e SD_ROLE=RPC \
  -p 50052:50052 \
  sd-cluster
```

Kurzprüfung auf jedem Worker:

```bash
docker logs sd-rpc
# erwartete Ausgabe (gekürzt):
# Starte als RPC-Worker...
# ... listening on 0.0.0.0:50052
```

**GPU-Worker:** Soll der Worker seine Grafikkarte anbieten, muss sie in den Container durchgereicht werden. Der `rpc-server` bietet automatisch alle Nicht-CPU-Geräte an, also die Vulkan-GPU(s) – ein zusätzliches Argument ist nicht nötig.

```bash
# NVIDIA
docker run -d --name sd-rpc --restart unless-stopped --gpus all \
  -e SD_ROLE=RPC -p 50052:50052 sd-cluster

# AMD/Intel (Image mit INSTALL_MESA_VULKAN=true gebaut)
docker run -d --name sd-rpc --restart unless-stopped \
  --device /dev/dri \
  -e SD_ROLE=RPC -p 50052:50052 sd-cluster
```

Ohne Durchreichung meldet der Worker nur seine CPU und den freien Arbeitsspeicher – das ist der normale CPU-Cluster-Betrieb.

### 2.5 Schritt 2: Verbindung vom Master testen

Auf dem Master-Host prüfen, ob alle Worker erreichbar sind. Dazu das Entrypoint-Skript umgehen und direkt `sd-server` mit `--list-devices` aufrufen:

```bash
docker run --rm --entrypoint ./sd-server sd-cluster \
  --rpc-servers 192.168.41.20:50052,192.168.41.42:50052,192.168.40.10:50052 \
  --list-devices
```

Erwartete Ausgabe (Beispiel):

```
CPU     AMD Ryzen 9 5900X 12-Core Processor
RPC0    192.168.41.20:50052
RPC1    192.168.41.42:50052
RPC2    192.168.40.10:50052
```

Besitzt der Master selbst eine nutzbare GPU, erscheint zusätzlich ein Eintrag wie `Vulkan0`. Die Namen `RPC0`, `RPC1`, `RPC2` werden später bei `--backend` verwendet. Sie werden in der Reihenfolge vergeben, in der die Server in `--rpc-servers` aufgelistet sind.

### 2.6 Schritt 3: Bild-Master starten

#### Variante A – Automatik (empfohlen für den Einstieg)

Es genügt, die Worker **bekannt zu machen**; die Platzierung übernimmt die Software:

```bash
docker run -d \
  --name sd-master \
  --restart unless-stopped \
  -e SD_ROLE=MASTER \
  -e SD_MODEL_PATH=/models/sd_model.gguf \
  -e SD_ARGS="--rpc-servers 192.168.41.20:50052,192.168.41.42:50052,192.168.40.10:50052" \
  -v /srv/models:/models \
  -p 8080:8080 \
  sd-cluster
```

Wie das funktioniert:

* `stable-diffusion.cpp` hat eine automatische Platzierung (`--auto-fit`), die **standardmäßig eingeschaltet** ist.
* RPC-Worker erscheinen für das Programm als Rechengeräte. Die Automatik wählt daraus **das Gerät mit dem größten freien Speicher** und führt **alle** Modellbestandteile dort aus. Reihum verteilt wird **nicht**.
* Zusätzlich entscheidet die Automatik, wo die Modellgewichte gehalten werden (Rechengerät → Arbeitsspeicher des Masters → anderes Gerät → Festplatte). Das passiert ebenfalls ohne Zutun.
* Gibt es weder RPC-Worker noch eine GPU mit freiem Speicher, fällt das Programm auf die lokale CPU des Masters zurück.

> **Wichtig:** Die Automatik entscheidet nach **Speichergröße, nicht nach CPU-Leistung**. Bei ungleichen Servern kann sie also den falschen (z. B. speicherreichen, aber langsamen) Worker wählen. Außerdem nutzt sie immer nur **einen** Worker gleichzeitig. Wer die Leistung gezielt verteilen will, verwendet Variante B oder C.

> **Tipp:** Mit `--max-vram rpc0=16,rpc1=8` lassen sich der Automatik Obergrenzen pro Worker (in GiB) vorgeben. Sie wählt dann anhand dieser Budgets. Achtung: Der Wert ist eine echte Obergrenze – zu kleine Werte führen dazu, dass Gewichte in den RAM oder auf die Festplatte ausgelagert werden.

#### Variante B – Fest auf einen bestimmten Worker

Mit `--backend` wird der Worker explizit vorgegeben:

```bash
docker run -d \
  --name sd-master \
  --restart unless-stopped \
  -e SD_ROLE=MASTER \
  -e SD_MODEL_PATH=/models/sd_model.gguf \
  -e SD_ARGS="--rpc-servers 192.168.41.20:50052,192.168.41.42:50052,192.168.40.10:50052 --backend RPC0" \
  -v /srv/models:/models \
  -p 8080:8080 \
  sd-cluster
```

Die Namen `RPC0`, `RPC1`, `RPC2` entsprechen der Reihenfolge in `--rpc-servers` (siehe Abschnitt 2.5). Diese Variante ist bei unterschiedlich starker Hardware der Automatik vorzuziehen.

#### Variante C – Arbeit auf mehrere Worker verteilen

Die Modellbestandteile lassen sich getrennt zuweisen:

```bash
docker run -d \
  --name sd-master \
  --restart unless-stopped \
  -e SD_ROLE=MASTER \
  -e SD_MODEL_PATH=/models/sd_model.gguf \
  -e SD_ARGS="--rpc-servers 192.168.41.20:50052,192.168.41.42:50052,192.168.40.10:50052 --backend clip=RPC0,diffusion=RPC1,vae=RPC2" \
  -v /srv/models:/models \
  -p 8080:8080 \
  sd-cluster
```

Die Modulnamen im Überblick:

| Modul | Bedeutung | Akzeptierte Namen |
|---|---|---|
| `diffusion` | Das eigentliche Bildmodell (UNet/DiT) | `diffusion`, `model`, `unet`, `dit` |
| `te` | Text-Encoder (wandelt den Prompt in Zahlen) | `te`, `clip`, `text`, `textencoder`, `t5`, … |
| `vae` | Bild-Decoder (macht aus den Latents ein Bild) | `vae`, `firststage`, `autoencoder` |

Zusätzlich kann ein einzelnes Modul über mehrere Worker verteilt werden (Layer-Split, `&`):

```bash
-e SD_ARGS="--rpc-servers 192.168.41.20:50052,192.168.41.42:50052,192.168.40.10:50052 --backend diffusion=RPC0&RPC1,te=cpu,vae=cpu"
```

Das ist nur für `diffusion` und `te` möglich. Achtung: Dabei werden die Zwischenergebnisse bei jedem Schritt über den Master zwischen den Workern weitergereicht. Das ist über das Netzwerk meist deutlich langsamer als ein einzelner starker Worker.

#### Welche Komponente auf welche CPU?

| Komponente | Rechenaufwand | Empfehlung |
|---|---|---|
| `diffusion` | **am höchsten** – läuft einmal pro Sampling-Schritt, also z. B. 20–30-mal pro Bild | **stärkste CPU** |
| `te` / `clip` | mittel – läuft einmal pro Prompt; bei SD3/Flux mit T5-Encoder auch recht groß | mittlere CPU |
| `vae` | gering – läuft einmal pro Bild; bei hohen Auflösungen aber **speicherhungrig** | **schwächste CPU** (genug RAM!) |

Faustregeln:

* **Im Zweifel alles auf den stärksten Worker** (Variante B). Jede Aufteilung erzeugt Netzwerkverkehr und kann langsamer sein als ein einzelner schneller Rechner.
* Bei der Frage „stark/schwach" zählen **Kerne, Takt und AVX-Unterstützung** der CPU. Die Automatik berücksichtigt das nicht.
* Zwischen den Modulen werden nur kleine Datenmengen übertragen (Latents und Conditioning). Der eigentliche Netzwerkaufwand entsteht beim **einmaligen Laden der Modellgewichte** und – bei Aufteilung eines Moduls – durch die **Latenz pro Schritt**.
* Der `vae`-Decoder braucht bei hohen Auflösungen viel RAM. Eine schwache, aber speicherreiche CPU ist dafür besser geeignet als eine schnelle mit wenig RAM.
* Die Steuerung und der gesamte Datenaustausch laufen über den Master. Die Verbindung sollte stabil und latenzarm sein (mindestens 1 Gbit/s).

#### Ohne RPC (Master rechnet komplett selbst)

```bash
docker run -d \
  --name sd-master \
  --restart unless-stopped \
  -e SD_ROLE=MASTER \
  -e SD_MODEL_PATH=/models/sd_model.gguf \
  -v /srv/models:/models \
  -p 8080:8080 \
  sd-cluster
```

**Funktionstest** (auf dem Master oder von einem Client im Netz):

```bash
curl -s http://192.168.41.57:8080/v1/images/generations \
  -H "Content-Type: application/json" \
  -d '{"prompt":"a cat sitting on a windowsill, watercolor","size":"512x512","n":1}' \
  | jq -r '.data[0].b64_json' | base64 -d > katze.png
```

Der Bild-Server bietet zusätzlich eine zu Automatic1111 kompatible API unter `/sdapi/v1/...` sowie eine eigene API unter `/sdcpp/v1/...`.

**Web-Oberfläche:** Im Browser `http://192.168.41.57:8080/` öffnen. Die Oberfläche ist fest in `sd-server` eingebettet und benötigt keinen zusätzlichen Webserver. Sie kann Bilder erzeugen und den Fortschritt anzeigen. Damit sie zusätzlich die Modelldateien aus dem eingebundenen Verzeichnis zur Auswahl anbietet, im `docker run`-Befehl ergänzen:

```bash
-e SD_ARGS="--model-dir /models --rpc-servers 192.168.41.20:50052,192.168.41.42:50052,192.168.40.10:50052 --backend RPC0"
```

**Mit GPU (Vulkan):** Die Gerätenamen aus `--list-devices` (z. B. `Vulkan0`) werden genauso verwendet wie `RPC0`. Beispiele für `SD_ARGS`:

```bash
# alles auf der lokalen GPU des Masters
-e SD_ARGS="--backend Vulkan0"

# oder gemischt: Diffusion auf der GPU, Text-Encoder und VAE auf der CPU
-e SD_ARGS="--backend diffusion=Vulkan0,te=cpu,vae=cpu"
```

> **Hinweis:** Die Automatik (`--auto-fit`) bevorzugt Geräte mit viel gemeldetem Speicher. Ein CPU-Worker mit 64 GB RAM kann dadurch vor einer GPU mit 8 GB VRAM gewählt werden. Bei gemischter Hardware die Zuweisung deshalb explizit setzen.

### 2.7 Schritt 4: Sprach-Server starten (optional)

```bash
docker run -d \
  --name llama-server \
  --restart unless-stopped \
  -e SD_ROLE=LLAMA \
  -e SD_MODEL_PATH=/models/llama_model.gguf \
  -e SD_ARGS="--ctx-size 4096" \
  -v /srv/models:/models \
  -p 8081:8081 \
  sd-cluster
```

Mit RPC-Unterstützung (beachte: `llama-server` verwendet **andere Optionsnamen** als `sd-server`):

```bash
docker run -d \
  --name llama-server \
  --restart unless-stopped \
  -e SD_ROLE=LLAMA \
  -e SD_MODEL_PATH=/models/llama_model.gguf \
  -e SD_ARGS="--rpc 192.168.41.20:50052,192.168.41.42:50052,192.168.40.10:50052 --device RPC0 -ngl 99 --ctx-size 4096" \
  -v /srv/models:/models \
  -p 8081:8081 \
  sd-cluster
```

Anders als beim Bild-Master gibt es hier keine Aufteilung nach Modellbestandteilen: `llama.cpp` lagert **Schichten** (Layer) des Modells aus. `--device` wählt die Geräte, `-ngl` (bzw. `--n-gpu-layers`) legt fest, wie viele Schichten ausgelagert werden. Mehrere Worker lassen sich als Liste angeben, z. B. `--device RPC0,RPC1`.

**Mit GPU (Vulkan):** `--device Vulkan0 -ngl 99` legt alle Schichten auf die lokale GPU des Sprach-Servers. Die Gerätenamen zeigt `llama-server --list-devices` (Container mit `--entrypoint ./llama-server` starten).

**Funktionstest:**

```bash
curl -s http://192.168.41.57:8081/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Sag Hallo in einem Satz."}]}' \
  | jq -r '.choices[0].message.content'
```

### 2.8 Umgebungsvariablen

| Variable | Bedeutung | Standard |
|---|---|---|
| `SD_ROLE` | Rolle des Containers: `MASTER`, `LLAMA` oder `RPC` | – (Pflicht) |
| `SD_MODEL_PATH` | Pfad zur Modelldatei **im Container** | `/models/model.gguf` |
| `SD_ARGS` | Zusätzliche Kommandozeilenargumente für das jeweilige Programm | leer |

`SD_ARGS` wird absichtlich in Einzelworte zerlegt (Shell-Worttrennung). Argumente mit Leerzeichen daher in Anführungszeichen setzen, z. B. `SD_ARGS="--prompt 'ein roter Apfel'"`.

**Ohne vorab geladenes Modell starten (reine Web-UI-Auswahl):** `SD_MODEL_PATH` ausdrücklich leer setzen und `--model-dir /models` mitgeben:

```bash
docker run -d --name sd-master --restart unless-stopped \
  -e SD_ROLE=MASTER \
  -e SD_MODEL_PATH="" \
  -e SD_ARGS="--model-dir /models" \
  -v /srv/models:/models \
  -p 8080:8080 \
  sd-cluster
```

Der Server startet dann ohne `--model`; im Browser wird das Modell aus `/models` ausgewählt. Wichtig: Der Unterschied ist `SD_MODEL_PATH=""` (leer, kein Modell) gegenüber gar nicht gesetzt (Standard `/models/model.gguf`).

### 2.9 Ports

| Port | Rolle | Zweck |
|---|---|---|
| `8080/tcp` | MASTER | Web-Oberfläche (`/`) und REST-API für Bildgenerierung |
| `8081/tcp` | LLAMA | REST-API für Sprachmodell (OpenAI-kompatibel) |
| `50052/tcp` | RPC | RPC-Protokoll zwischen Master und Workern |

### 2.10 Betrieb

```bash
# Logs verfolgen
docker logs -f sd-master
docker logs -f sd-rpc

# Container stoppen/starten
docker stop sd-rpc && docker start sd-rpc

# Container entfernen und neu erstellen (z. B. nach Image-Update)
docker rm -f sd-rpc
```

**Worker skalieren:** Einfach auf weiteren Hosts denselben `docker run`-Befehl ausführen und die neue Adresse in `--rpc-servers` des Masters ergänzen. Achtung: Der Master muss dafür neu erstellt werden.

**Reihenfolge:** Zuerst die Worker starten, dann den Master. Der Master verbindet sich beim Start mit den Workern; sind sie nicht erreichbar, bricht er ab.

**Update:** Neues Image bauen/verteilen, dann **alle** Container neu erstellen. Niemals nur einzelne Knoten aktualisieren, da das RPC-Protokoll an die Build-Version gebunden ist.

### 2.11 Alternative: docker compose (nur Einzelhost)

Für einen Testaufbau auf **einem** Rechner liegt eine `docker-compose.yml` bei:

```bash
docker compose up --build -d
docker compose logs -f
docker compose down
```

Die Datei definiert drei Dienste (`master`, `llama-server`, `rpc-worker`). Der Master erreicht den Worker über den Compose-internen DNS-Namen `rpc-worker`. Für den Betrieb über mehrere Hosts ist Compose **nicht** geeignet – dort die `docker run`-Befehle aus den Abschnitten 2.4–2.7 verwenden.

### 2.12 GPU-Beschleunigung mit Vulkan

Das Image wird standardmäßig mit Vulkan-Backend gebaut. Eine GPU wird nur genutzt, wenn der Host sie in den Container sichtbar macht; sonst rechnet die Software auf der CPU weiter (Fallback).

| Host | Voraussetzung | Start des Containers |
|---|---|---|
| NVIDIA | `nvidia-container-toolkit` und passender Host-Treiber | `--gpus all` (das Image setzt `NVIDIA_DRIVER_CAPABILITIES=all`) |
| AMD/Intel | Mesa-Vulkan-Treiber im Image (`--build-arg INSTALL_MESA_VULKAN=true`) | `--device /dev/dri` |
| keine GPU | – | nichts weiter; CPU-Betrieb |

Geräte prüfen:

```bash
docker run --rm --entrypoint ./sd-server sd-cluster --list-devices
```

Beispielausgabe:

```
Vulkan0 AMD Radeon RX 7600 (RADV NAVI33)
CPU     AMD Ryzen 9 5900X 12-Core Processor
```

Die Verwendung ist in Abschnitt 2.6 (Bild) und 2.7 (Sprache) beschrieben.

Wichtige Punkte:

* **Vulkan ist optional.** Fehlt ein Treiber oder eine ICD-Datei, bleibt es beim CPU-Betrieb; der Container startet trotzdem.
* **Reines CPU-Image:** `docker build --build-arg WITH_VULKAN=OFF -t sd-cluster .`
* **Software-Vulkan (lavapipe)** wird bewusst nicht standardmäßig installiert. Er erscheint als „GPU" mit dem Arbeitsspeicher des Hosts und kann die automatische Platzierung in die Irre führen.
* **NVIDIA:** Das Toolkit reicht die Treiberbibliotheken in den Container. Das Image setzt dafür `NVIDIA_DRIVER_CAPABILITIES=all`; `INSTALL_MESA_VULKAN` ist nicht nötig.
* **RPC-Worker mit GPU:** Der Worker meldet dem Master den freien **Grafikspeicher** (statt Arbeitsspeicher). Die Automatik bewertet ihn dadurch anders. Bei gemischten Workern die Zuweisung explizit setzen (Abschnitt 2.6).

---

## 3. Umsetzung im Detail (für Docker-Erfahrene)

### 3.1 `Dockerfile`

**Zweistufiger Build (Multi-Stage):**

* **Stage `builder`** (`debian:trixie-slim`): Compiler und Build-Werkzeuge (`build-essential`, `cmake`, `git`, `libwebp-dev`), die Vulkan-Toolchain (`libvulkan-dev`, `glslc`, `glslang-tools`, `spirv-headers`) sowie `nodejs` und `npm`, um `pnpm@10.15.1` zu installieren.
* **Stage final** (`debian:trixie-slim`): nur die fertigen Binaries und die Laufzeitbibliotheken `libwebp7` (WebP-Ausgabe), `libgomp1` (OpenMP) und `libvulkan1` (Vulkan-Loader). Optional kommen über `INSTALL_MESA_VULKAN=true` die Mesa-Treiber hinzu.

Zwei Build-Argumente steuern den Umfang:

| Argument | Standard | Zweck |
|---|---|---|
| `WITH_VULKAN` | `ON` | reicht `-DSD_VULKAN` bzw. `-DGGML_VULKAN` an CMake weiter; `OFF` ergibt ein reines CPU-Image |
| `INSTALL_MESA_VULKAN` | `false` | installiert im Laufzeit-Image die Mesa-Treiber (AMD/Intel und Software-Vulkan) |

**Build von `stable-diffusion.cpp`:**

```dockerfile
RUN mkdir build && cd build && \
    cmake .. -DSD_BUILD_SERVER=ON -DSD_RPC=ON -DSD_VULKAN=${WITH_VULKAN} && \
    cmake --build . --config Release -j $(nproc) && ...
```

* `-DSD_BUILD_SERVER=ON` erzeugt `sd-server` (HTTP-API **und Web-UI**).
* `-DSD_RPC=ON` aktiviert den RPC-Client, sonst wäre `--rpc-servers` unbekannt.
* `-DSD_VULKAN=ON` aktiviert das Vulkan-Backend. CMake setzt dabei intern `GGML_VULKAN=ON` und übersetzt die Shader mit `glslc`.
* Vor dem Build wird per `sed` eine `static_assert`-Prüfung aus `ggml/include/ggml-rpc.h` entfernt. Diese Prüfung vergleicht die Anzahl der GGML-Operationen mit einem fest verdrahteten Wert und bricht den Build ab, sobald die Submodul-Version abweicht. Das Muster ist bewusst generisch (`GGML_OP_COUNT ==`), damit es auch bei künftigen Werten greift.

**Web-UI im Build:** CMake sucht beim Konfigurieren nach `pnpm`. Ist es vorhanden, laufen `pnpm install`, `pnpm run build` und `pnpm run build:header` als Custom-Targets; das erzeugte `gen_index_html.h` wird fest in `sd-server` eingebettet (`HAVE_INDEX_HTML`). Fehlt `pnpm`, wird die UI ohne Fehler weggelassen und `/` liefert nur einen Statustext. Deshalb installiert der Builder `nodejs`/`npm` und danach global `pnpm@10.15.1` – exakt die Version aus dem `packageManager`-Feld des Frontends. Dieser Schritt benötigt Netzwerkzugriff auf die npm-Registry.

**Build von `llama.cpp` (RPC-Server + LLM-Server):**

Die zu `stable-diffusion.cpp` passende `llama.cpp`-Version wird nicht geraten, sondern aus der Submodul-Datei gelesen:

```dockerfile
RUN HASH=$(cat scripts/sync-llama.last) && \
    git clone https://github.com/ggml-org/llama.cpp.git && \
    cd llama.cpp && git checkout $HASH && ...
```

Das ist entscheidend: Client und RPC-Server müssen dasselbe GGML-RPC-Protokoll sprechen.

Wichtige CMake-Flags:

| Flag | Zweck |
|---|---|
| `-DGGML_RPC=ON` | aktiviert den RPC-Server |
| `-DGGML_VULKAN=${WITH_VULKAN}` | Vulkan-Backend für `llama-server` und `rpc-server` |
| `-DBUILD_SHARED_LIBS=OFF` | statische Libraries; `ggml` wird fest einkompiliert, es gibt keine `libggml*.so` im Laufzeit-Image (der frühere Schalter `GGML_BUILD_SHARED_LIBS` existiert in `llama.cpp`/`ggml` **nicht** und wurde ignoriert) |
| `-DLLAMA_CURL=OFF` | entfernt die unnötige libcurl-Abhängigkeit |
| `-DCMAKE_C_FLAGS=-DGGML_MAX_NAME=160` / `-DCMAKE_CXX_FLAGS=...` | **Pflicht:** `stable-diffusion.cpp` erwartet `GGML_MAX_NAME=160`; der Standardwert `64` würde Datenübertragungen zwischen Client und Server scheitern lassen |

**Binary-Ermittlung:** Die Ziel- und Dateinamen unterscheiden sich je nach `llama.cpp`-Version (das RPC-Programm heißt dort z. B. `ggml-rpc-server`, die Dokumentation spricht von `rpc-server`). Deshalb werden die Binaries nach dem Build gesucht, geprüft und an feste Pfade kopiert:

```dockerfile
RPC_BIN=$(find . -type f \( -name "ggml-rpc-server" -o -name "rpc-server" \) -executable | head -n1) && \
LLAMA_BIN=$(find . -type f -name "llama-server" -executable | head -n1) && \
test -n "$RPC_BIN" && test -n "$LLAMA_BIN" && \
cp "$RPC_BIN" /rpc-server-binary && cp "$LLAMA_BIN" /llama-server-binary
```

Eine abschließende Prüfung stellt sicher, dass alle drei Binaries existieren **und** dass `rpc-server` und `llama-server` keine `libggml*.so` erwarten (`ldd ... | grep libggml`). Das vermeidet sowohl schwer lesbare `COPY`-Fehler als auch den Laufzeitfehler `error while loading shared libraries: libggml.so.0`.

**Laufzeit-Image:** Die Binaries landen unter `/app`, das Modellverzeichnis wird als `VOLUME /models` deklariert, `EXPOSE` dokumentiert die Ports 8080/8081/50052, `ENTRYPOINT` ist das Rollen-Skript. `libvulkan1` ist immer installiert, damit die Vulkan-fähigen Binaries überhaupt starten; die eigentlichen GPU-Treiber (ICD-Dateien) kommen vom Host bzw. aus `mesa-vulkan-drivers`. `ENV NVIDIA_DRIVER_CAPABILITIES=all` sorgt dafür, dass das NVIDIA-Toolkit auch die Grafik-/Vulkan-Bibliotheken einhängt.

### 3.2 `entrypoint.sh`

Das Skript ist bewusst minimal und macht nur eines: anhand von `SD_ROLE` das passende Binary mit `exec` starten.

```bash
SD_MODEL_PATH=${SD_MODEL_PATH-/models/model.gguf}

case "$SD_ROLE" in
    "MASTER")
        MODEL_ARGS=()
        if [ -n "$SD_MODEL_PATH" ]; then MODEL_ARGS=(--model "$SD_MODEL_PATH"); fi
        exec ./sd-server --listen-ip 0.0.0.0 --listen-port 8080 "${MODEL_ARGS[@]}" $SD_ARGS ;;
    "LLAMA")  exec ./llama-server --host 0.0.0.0 --port 8081 --model "$SD_MODEL_PATH" $SD_ARGS ;;
    "RPC")    exec ./rpc-server --host 0.0.0.0 --port 50052 $SD_ARGS ;;
    *) echo "Fehler: SD_ROLE muss MASTER, LLAMA oder RPC sein."; exit 1 ;;
esac
```

Details:

* **`exec`** ersetzt die Shell durch das eigentliche Programm. Dadurch wird es PID 1 im Container und empfängt Signale (`docker stop` funktioniert sauber).
* **`set -e`** bricht bei Fehlern ab.
* **`$SD_ARGS`** steht absichtlich **ohne** Anführungszeichen: Nur so wird die Variable in einzelne Argumente zerlegt. Wer Argumente mit Leerzeichen braucht, muss sie selbst quoten.
* **`${SD_MODEL_PATH-...}`** (ohne Doppelpunkt) setzt den Standard nur bei **nicht gesetzter** Variable. So lässt sich `SD_MODEL_PATH=""` ausdrücklich leer setzen, woraufhin der Master ohne `--model` startet und die Modellauswahl der Web-UI überlässt. Die Argumentliste wird als Bash-Array gebaut, damit Leerzeichen im Pfad erhalten bleiben.
* **Optionsnamen unterscheiden sich** zwischen den Programmen – das ist eine häufige Fehlerquelle:

| Programm | Bind-Adresse | Port | Modell |
|---|---|---|---|
| `sd-server` | `--listen-ip` / `-l` | `--listen-port` | `--model` / `-m` |
| `llama-server` | `--host` | `--port` | `--model` / `-m` |
| `rpc-server` | `--host` / `-H` | `--port` / `-p` | – |

* **RPC-Auswahl** ebenfalls unterschiedlich: `sd-server` nutzt `--rpc-servers` + `--backend`, `llama-server` nutzt `--rpc` + `--device`.

### 3.3 `docker-compose.yml`

Die Datei ist als Komfort für einen Einzelhost-Test gedacht:

* **`build: .`** und **`image: sd-cluster`** sorgen dafür, dass einmal gebaut und dasselbe Image von allen drei Diensten verwendet wird.
* **`environment`** setzt `SD_ROLE` und die rollenspezifischen Parameter.
* **`volumes: ./models:/models`** bindet die Modelldateien ein.
* **`ports`** veröffentlicht 8080 (Bild) und 8081 (Text); der RPC-Port 50052 bleibt intern, weil der Zugriff über den Servicenamen `rpc-worker` erfolgt.
* **`depends_on: rpc-worker`** stellt nur die **Startreihenfolge** sicher. Es garantiert **nicht**, dass der RPC-Server bereits Verbindungen annimmt. Bei sehr langsamen Hosts kann der Master daher einmalig abbrechen; `--restart unless-stopped` fängt das ab.
* **`--backend RPC0`** im Master legt den Worker **fest**. Ohne diese Angabe greift die automatische Platzierung (`--auto-fit`), die den Worker mit dem größten freien Speicher wählt (siehe Abschnitt 2.6).

### 3.4 Bewusste Design-Entscheidungen und Grenzen

| Thema | Entscheidung / Grund |
|---|---|
| **CPU-Fallback** | Das Image funktioniert ohne GPU vollständig. Vulkan wird nur genutzt, wenn der Host ein Gerät sichtbar macht; andernfalls rechnet die Software auf der CPU. |
| **Vulkan standardmäßig an** | `WITH_VULKAN=ON` ist der Standard. Der Builder installiert dafür `libvulkan-dev`, `glslc`, `glslang-tools` und `spirv-headers`; das Laufzeit-Image enthält nur den Loader `libvulkan1`. `--build-arg WITH_VULKAN=OFF` erzeugt ein reines CPU-Image. |
| **Mesa-Treiber optional** | `INSTALL_MESA_VULKAN=false` ist Standard, weil `mesa-vulkan-drivers` über `libllvm19` rund 125 MB plus weitere Treiberbibliotheken nachzieht (zusammen etwa 250 MB). AMD/Intel-Hosts bauen mit `true`; NVIDIA nutzt das `nvidia-container-toolkit`. Software-Vulkan (lavapipe) wird bewusst nicht voreingestellt, weil er als „GPU" mit viel Speicher erkannt wird und die automatische Platzierung verfälschen kann. |
| **Web-UI eingebettet** | Der Builder installiert `nodejs`/`npm` und `pnpm@10.15.1`. CMake baut das Frontend und bettet `gen_index_html.h` fest in `sd-server` ein (`HAVE_INDEX_HTML`). Zur Laufzeit sind weder Node.js noch ein separater Webserver nötig. Fehlt `pnpm` (z. B. bei deaktiviertem Frontend-Build), wird die UI ohne Fehler weggelassen. |
| **Protokoll-Pinning** | `llama.cpp` wird exakt auf den in `sync-llama.last` hinterlegten Commit gebaut. Alle Cluster-Knoten müssen dasselbe Image verwenden. |
| **Statische GGML-Binaries** | `llama.cpp`/`ggml` werden mit `-DBUILD_SHARED_LIBS=OFF` gebaut. `rpc-server` und `llama-server` enthalten `ggml` damit fest und benötigen keine `libggml*.so` im Laufzeit-Image. Der Build prüft das per `ldd`; so kann der Fehler `libggml.so.0: cannot open shared object file` nicht unbemerkt zurückkehren. |
| **Modelle nur auf dem Master** | Laut `stable-diffusion.cpp`-Dokumentation bleiben die Modelldateien beim Client; der RPC-Server erhält Tensordaten und Rechengraphen. Das Volume auf den Workern ist daher nur einheitlicher Komfort. |
| **Keine RPC-Sicherheit** | Der `rpc-server` bietet weder Authentifizierung noch Verschlüsselung. Nur in vertrauenswürdigen Netzen betreiben; Port 50052 nicht nach außen freigeben. |

### 3.5 Dateien im Überblick

| Datei | Zweck |
|---|---|
| `Dockerfile` | zweistufiger Build aller drei Programme inklusive Vulkan-Backend und eingebetteter Web-UI, Laufzeit-Image |
| `entrypoint.sh` | Rollenwahl über `SD_ROLE`, Start des passenden Servers |
| `docker-compose.yml` | Beispiel-Deployment auf einem Einzelhost |
