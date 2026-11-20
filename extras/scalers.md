# Scaler-Übersicht für den SD-Cluster (`stable-diffusion.cpp`)

Diese Übersicht dokumentiert die Upscaler („Scaler"), die im Hires-Fix des
`sd-cluster` verwendet werden können – inklusive **relativem Performance-Index**
(0 = langsamster, 100 = schnellster) und **Qualitäts-Score** (0 = schwächste,
100 = beste Bildqualität).

Ergänzende Dateien: `samplers.md` (Sampler), `examples.md` (API-Beispiele),
`README.md` (Betrieb des Clusters).

---

## 1. Was ist ein Scaler?

Beim Hires-Fix wird das fertige Bild (bzw. der Latent) vergrößert und danach
mit einem zweiten Sampling-Durchlauf verfeinert. Der Scaler entscheidet, **wie**
vergrößert wird. Dabei gibt es drei Familien:

| Familie | Arbeitet auf | Beispiele | VAE-Kosten |
|---|---|---|---|
| **Latent-Scaler** | Latent-Tensor | `Latent`, `Latent (bicubic)`, … | keine (kein Decode/Encode) |
| **Bild-Scaler (interpoliert)** | Pixeln | `Lanczos`, `Nearest` | 1× Decode + 1× Encode |
| **Modell-Scaler (gelernt)** | Pixeln | ESRGAN, MoSR (z. B. `4x_NMKD-…`) | 1× Decode + 1× Encode + CNN-Inferenz |

> **Kurz gesagt:** Latent-Scaler sind am schnellsten, Modell-Scaler liefern die
> beste Detailqualität, sind aber deutlich langsamer und speicherhungriger.

---

## 2. Wichtig: Stand in diesem Container

Der laufende Master meldet aktuell **nur die eingebauten Scaler**:

```bash
curl -s http://cluster:8080/sdapi/v1/upscalers | jq -r '.[].name'
```

```text
None
Lanczos
Nearest
```

Die **Latent-Modi** werden separat aufgeführt:

```bash
curl -s http://cluster:8080/sdapi/v1/latent-upscale-modes | jq -r '.[].name'
```

```text
Latent
Latent (nearest)
Latent (nearest-exact)
Latent (antialiased)
Latent (bicubic)
Latent (bicubic antialiased)
```

Das bedeutet:

* **`4x_NMKD-Superscale-SP_178000_G` ist derzeit nicht installiert.** Der
  Container bringt keine Modell-Scaler mit. Der Name taucht deshalb weder in
  der API noch in der Web-UI auf.
* Ein Hires-Fix mit einem nicht installierten Modell-Scaler wird von
  `/sdapi/v1/txt2img` mit **HTTP 400 `{"error":"invalid params"}`** abgelehnt.
* Auf dem OpenAI-Endpunkt (`/v1/images/generations`) werden Hires-Parameter
  dagegen **komplett ignoriert** – dort gibt es weder Fehler noch Hires-Effekt.

### Warum dein früherer Versuch nicht wirkte

Drei Ursachen kamen zusammen:

1. **Falscher Endpunkt:** `/v1/images/generations` liest nur `prompt`, `n`,
   `size`, `output_format`, `output_compression`. `enable_hr`, `hr_scale`,
   `hr_upscaler` und `denoising_strength` werden dort nicht ausgewertet.
2. **Falscher Feldname:** `stable-diffusion.cpp` kennt **`hr_steps`**, nicht
   `hr_second_pass_steps`.
3. **Scaler nicht installiert:** `4x_NMKD-Superscale-SP_178000_G` liegt nicht
   im Upscaler-Verzeichnis. Auf `/sdapi/v1/txt2img` hätte das zu einem
   Fehler geführt, nicht zu einem stillen Ignorieren.

---

## 3. Bewertungsgrundlagen

### Performance-Index (0–100)

Der Index beschreibt den **relativen Zusatzaufwand des Scalers** innerhalb
eines Hires-Passes. Er isoliert bewusst nur den Upscaling-Schritt, nicht das
anschließende Sampling:

* **100** = praktisch kostenlos (Latent-Interpolation)
* **85–95** = schnelle Pixel-Interpolation (plus VAE Decode/Encode)
* **10–20** = gelerntes Modell (CNN-Inferenz, modell- und hardwareabhängig)

Die reale Laufzeit hängt zusätzlich von Auflösung, Zielgröße, Modell und
Hardware ab. Der Index ist ein **theoretischer Relativwert**, kein Benchmark.

### Qualitäts-Score (0–100)

Der Score bewertet die **Detail- und Kantenqualität nach dem Hires-Pass**:

* Schärfe und Detailerhalt
* Artefaktfreiheit (Ringing, Blockbildung, Überschärfung)
* Natürlichkeit der Texturen
* Stabilität bei verschiedenen Denoising-Stärken

Der Score ist **modell- und promptabhängig**. Ein niedriger Score heißt nicht
„unbrauchbar", sondern „für diesen Zweck weniger geeignet".

---

## 4. Performance-Ranking

| Rang | Scaler | Typ | Relativer Aufwand | Performance-Index |
|---:|---|---|---|---:|
| 1 | `Latent` | Latent | minimale Interpolation | **100** |
| 2 | `Latent (nearest)` | Latent | minimale Interpolation | **99** |
| 2 | `Latent (nearest-exact)` | Latent | minimale Interpolation | **99** |
| 4 | `Latent (antialiased)` | Latent | leichte Filterung | **97** |
| 4 | `Latent (bicubic)` | Latent | leichte Filterung | **97** |
| 6 | `Latent (bicubic antialiased)` | Latent | leichte Filterung | **96** |
| 7 | `Nearest` | Bild | VAE + Interpolation | **90** |
| 8 | `Lanczos` | Bild | VAE + aufwendigere Filterung | **85** |
| 9 | ESRGAN / MoSR (`4x_…`) | Modell | VAE + CNN-Inferenz | **10–20** |

**Kurzinterpretation:**

* **Latent-Gruppe (96–100):** schnellste Wahl, ideal für Entwürfe und große
  Serien.
* **Bild-Interpolation (85–90):** etwas langsamer, aber oft schärfer als
  Latent.
* **Modell-Scaler (10–20):** langsamste, aber qualitativ beste Wahl.

---

## 5. Qualitäts-Ranking

| Rang | Scaler | Qualitäts-Score | Stärke |
|---:|---|---:|---|
| 1 | ESRGAN / MoSR (`4x_…`) | **95–98** | Beste Detailtreue, natürliche Texturen, echte Rekonstruktion |
| 2 | `Lanczos` | **82** | Scharf, gute Kanten, keine gelernten Artefakte |
| 3 | `Latent (bicubic antialiased)` | **80** | Weiche, artefaktarme Vergrößerung |
| 4 | `Latent (bicubic)` | **79** | Gute Allround-Vergrößerung |
| 5 | `Latent (antialiased)` | **77** | Reduziert Treppeneffekte |
| 6 | `Latent` | **72** | Solider Standard, leicht weich |
| 7 | `Latent (nearest-exact)` | **68** | Exakte Rasterung, weniger glatt |
| 8 | `Latent (nearest)` | **64** | Schnell, aber kantig |
| 9 | `Nearest` | **45** | Blockig; nur für Pixel-Art/Test |
| – | `None` | **0** | Kein Upscaling (Hires wird deaktiviert) |

**Kurzinterpretation:**

* **Spitzenklasse (95+):** gelernte Modell-Scaler – sofern installiert.
* **Guter Standard (77–82):** `Lanczos` und die bikubischen Latent-Modi.
* **Schnelle Entwürfe (64–72):** `Latent` und Nearest-Varianten.
* **Nur für Spezialfälle (< 50):** `Nearest` (Pixel-Art) und `None`.

---

## 6. Detaillierte Profile

### 6.1 `None`

* **Typ:** keiner
* **Performance-Index:** – (kein Upscaling)
* **Qualitäts-Score:** 0/100
* **Verhalten:** Deaktiviert den Hires-Fix (`hires.enabled = false`).
* **Einsatz:** Bewusst ohne zweiten Pass arbeiten.
* **Empfohlene Parameter:** keine.

---

### 6.2 `Latent`

* **Typ:** Latent-Interpolation (Standard)
* **Performance-Index:** 100/100
* **Qualitäts-Score:** 72/100
* **Verhalten:** Vergrößert den Latent-Tensor direkt; kein VAE Decode/Encode
  vor dem zweiten Pass. Wird verwendet, wenn `enable_hr` gesetzt ist und kein
  `hr_upscaler` angegeben wurde.
* **Stärken:** Schnellster Scaler, geringer Speicherbedarf, stabil.
* **Schwächen:** Etwas weicher; feine Texturen werden nicht rekonstruiert.
* **Empfohlene Parameter:** `hr_scale`: 1,5–2,0, `denoising_strength`:
  0,35–0,55, `hr_steps`: 10–20.

---

### 6.3 `Latent (nearest)`

* **Typ:** Latent-Interpolation, Nearest-Neighbor
* **Performance-Index:** 99/100
* **Qualitäts-Score:** 64/100
* **Verhalten:** Nächster-Nachbar-Vergrößerung im Latent-Raum.
* **Stärken:** Extrem schnell, exakte Werteübernahme.
* **Schwächen:** Kantig/blockig; für Fotos ungeeignet.
* **Empfohlene Parameter:** `hr_scale`: 1,5–2,0, `denoising_strength`:
  0,45–0,6, `hr_steps`: 10–20.
* **Einsatz:** Pixel-Art, Tests, sehr niedrige Denoising-Stärke.

---

### 6.4 `Latent (nearest-exact)`

* **Typ:** Latent-Interpolation, Nearest-Exact
* **Performance-Index:** 99/100
* **Qualitäts-Score:** 68/100
* **Verhalten:** Wie `Latent (nearest)`, aber mit exakter Rasterzuordnung.
* **Stärken:** Etwas gleichmäßiger als `Latent (nearest)`.
* **Schwächen:** Weiterhin kantig bei Fotos.
* **Empfohlene Parameter:** `hr_scale`: 1,5–2,0, `denoising_strength`:
  0,45–0,6, `hr_steps`: 10–20.

---

### 6.5 `Latent (antialiased)`

* **Typ:** Latent-Interpolation mit Antialiasing
* **Performance-Index:** 97/100
* **Qualitäts-Score:** 77/100
* **Verhalten:** Glättet beim Vergrößern und reduziert Treppeneffekte.
* **Stärken:** Sauberere Kanten als `Latent`.
* **Schwächen:** Leicht weich; Details bleiben interpoliert.
* **Empfohlene Parameter:** `hr_scale`: 1,5–2,0, `denoising_strength`:
  0,35–0,5, `hr_steps`: 12–20.

---

### 6.6 `Latent (bicubic)`

* **Typ:** Latent-Interpolation, bikubisch
* **Performance-Index:** 97/100
* **Qualitäts-Score:** 79/100
* **Verhalten:** Bikubische Vergrößerung im Latent-Raum.
* **Stärken:** Guter Allround-Kompromiss, schärfer als `Latent`.
* **Schwächen:** Bei sehr starkem Upscaling leicht überschärft.
* **Empfohlene Parameter:** `hr_scale`: 1,5–2,0, `denoising_strength`:
  0,35–0,5, `hr_steps`: 12–20.

---

### 6.7 `Latent (bicubic antialiased)`

* **Typ:** Latent-Interpolation, bikubisch mit Antialiasing
* **Performance-Index:** 96/100
* **Qualitäts-Score:** 80/100
* **Verhalten:** Bikubisch plus Kantenglättung.
* **Stärken:** Sehr artefaktarm, gute Allround-Wahl für Latent.
* **Schwächen:** Etwas weicher als reines Bicubic.
* **Empfohlene Parameter:** `hr_scale`: 1,5–2,0, `denoising_strength`:
  0,35–0,5, `hr_steps`: 12–20.

---

### 6.8 `Lanczos`

* **Typ:** Bild-Interpolation (Pixelebene)
* **Performance-Index:** 85/100
* **Qualitäts-Score:** 82/100
* **Verhalten:** Decodiert den Latent zum Bild, vergrößert mit Lanczos,
  encodiert zurück und startet den zweiten Pass.
* **Stärken:** Scharfe Kanten, gute Detailwiedergabe, kein Trainingsmodell
  nötig.
* **Schwächen:** Kann bei starkem Upscaling zu Ringing neigen; zusätzliche
  VAE-Decode/Encode-Kosten.
* **Empfohlene Parameter:** `hr_scale`: 1,5–2,0, `denoising_strength`:
  0,25–0,45, `hr_steps`: 10–20.

---

### 6.9 `Nearest`

* **Typ:** Bild-Interpolation (Pixelebene)
* **Performance-Index:** 90/100
* **Qualitäts-Score:** 45/100
* **Verhalten:** Nächster-Nachbar-Vergrößerung auf Pixelebene.
* **Stärken:** Sehr schnell, harte Pixelkanten.
* **Schwächen:** Blockig, für Fotos unbrauchbar.
* **Empfohlene Parameter:** `hr_scale`: 1,5–2,0, `denoising_strength`:
  0,4–0,6, `hr_steps`: 10–20.
* **Einsatz:** Pixel-Art, Retro-Look, technische Tests.

---

### 6.10 Modell-Scaler (ESRGAN / MoSR)

* **Typ:** gelerntes CNN (Bild → Bild)
* **Performance-Index:** 10–20/100 (hardwareabhängig)
* **Qualitäts-Score:** 95–98/100
* **Beispiele:** `4x_NMKD-Superscale-SP_178000_G`, `4x-UltraSharp`,
  `4x_foolhardy_Remacri`, `RealESRGAN_x4plus`, `4xNomos2_hq_mosr`
* **Verhalten:** Decodiert den Latent, skaliert mit dem Modell (typisch 4×),
  passt das Ergebnis auf die Zielgröße an und encodiert zurück.
* **Stärken:** Beste Detailtreue und natürliche Texturen; echte
  Rekonstruktion statt Interpolation.
* **Schwächen:** Deutlich langsamer, hoher RAM-/VRAM-Bedarf; Modell muss
  installiert sein.
* **Empfohlene Parameter:** `hr_scale`: 1,5–2,0, `denoising_strength`:
  0,2–0,4, `hr_steps`: 8–15 (der Scaler liefert bereits Details).
* **Unterstützte Formate:** `.gguf`, `.safetensors`, `.pt`, `.pth`
* **Unterstützte Architekturen:** ESRGAN und MoSR (Architektur wird aus den
  Gewichten erkannt).

---

## 7. Modell-Scaler installieren

Der Container bringt **keine** Modell-Scaler mit. So bindet man sie ein:

### Schritt 1: Verzeichnis auf dem Host anlegen

```bash
mkdir -p /opt/modelle/upscalers
```

### Schritt 2: Modell herunterladen

Beispiel `4x_NMKD-Superscale-SP_178000_G` (ESRGAN, 4×):

```bash
# Datei von einer vertrauenswürdigen Quelle (z. B. OpenModelDB/Hugging Face)
# nach /opt/modelle/upscalers/4x_NMKD-Superscale-SP_178000_G.pth legen
```

### Schritt 3: Master mit Upscaler-Verzeichnis starten

Das Verzeichnis wird über `SD_ARGS` an `sd-server` durchgereicht:

```bash
docker rm -f sd-master
docker run -d --name sd-master --restart unless-stopped \
  -e SD_ROLE=MASTER \
  -e SD_MODEL_PATH=/models/epiCRealism-naturalSinVAE.safetensors \
  -e SD_ARGS="--hires-upscalers-dir /models/upscalers" \
  -v /opt/modelle:/models \
  -p 8080:8080 \
  sd-cluster
```

### Schritt 4: Installation prüfen

```bash
curl -s http://cluster:8080/sdapi/v1/upscalers \
  | jq -r '.[] | "\(.name)\t\(.model_name)\t\(.scale)x"'
```

Jetzt sollte der Modellname (ohne Pfad und Endung) in der Liste stehen.

> **Hinweis zum Feld `scale`:** Bei den eingebauten Scalern (`None`, `Lanczos`,
> `Nearest`) ist `scale: 4` nur ein Platzhalter. Die tatsächliche Vergrößerung
> steuert `hr_scale` bzw. `hr_resize_x`/`hr_resize_y`. Bei Modell-Scalern zeigt
> `scale` die native Skalierung des Modells (typisch 4×).

### Schritt 5: Verwendung

`hr_upscaler` erwartet den **Modellnamen ohne Pfad und ohne Endung**:

```json
{ "hr_upscaler": "4x_NMKD-Superscale-SP_178000_G" }
```

Nicht `.../4x_NMKD-Superscale-SP_178000_G.pth` und nicht mit `.pth`.

---

## 8. Wo kann man die verfügbaren Scaler nachschlagen?

| Quelle | Inhalt |
|---|---|
| `GET /sdapi/v1/upscalers` | eingebaute Bild-/Modell-Scaler (`None`, `Lanczos`, `Nearest`, installierte Modelle) |
| `GET /sdapi/v1/latent-upscale-modes` | alle Latent-Modi |
| `GET /sdcpp/v1/capabilities` → `.upscalers` | vollständige Liste inkl. `model`/`image_upscale`-Flags |
| Web-UI | Dropdown „Hires upscaler" im Hires-Fix-Bereich |
| Server-Log | `Upscaler architecture: …` beim Laden eines Modell-Scalers |
| Server-Argument | `--hires-upscalers-dir` (Standard: leer) |

Beispiel für die kombinierte Abfrage:

```bash
{
  curl -s http://cluster:8080/sdapi/v1/upscalers        | jq -r '.[].name'
  curl -s http://cluster:8080/sdapi/v1/latent-upscale-modes | jq -r '.[].name'
} | sort -u
```

---

## 9. API-Beispiel (korrekt)

Hires-Fix über `/sdapi/v1/txt2img` – mit **`hr_steps`** statt
`hr_second_pass_steps`:

```bash
curl -s -X POST http://cluster:8080/sdapi/v1/txt2img \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "a cozy cabin in the mountains, golden hour, detailed landscape",
    "negative_prompt": "blurry, low quality",
    "width": 512,
    "height": 768,
    "steps": 20,
    "cfg_scale": 6.0,
    "sampler_name": "dpm++2m",
    "enable_hr": true,
    "hr_scale": 2.0,
    "hr_upscaler": "Latent (bicubic)",
    "denoising_strength": 0.35,
    "hr_steps": 15,
    "seed": -1
  }' | jq -r '.images[0]' | base64 -d > /opt/modelle/huette.png
```

Mit installiertem Modell-Scaler:

```json
{
  "enable_hr": true,
  "hr_scale": 2.0,
  "hr_upscaler": "4x_NMKD-Superscale-SP_178000_G",
  "denoising_strength": 0.3,
  "hr_steps": 12
}
```

> **Nicht verwenden:** `hr_second_pass_steps` (A1111-Name) – wird von
> `stable-diffusion.cpp` nicht gelesen. Ebenso wirkungslos ist der komplette
> Hires-Block auf `/v1/images/generations`.

---

## 10. Empfohlene Parameter nach Ziel

| Ziel | Scaler | `hr_scale` | `denoising_strength` | `hr_steps` |
|---|---|---|---|---|
| Schneller Entwurf | `Latent` | 1,5–2,0 | 0,4–0,55 | 10–15 |
| Ausgewogen | `Latent (bicubic antialiased)` | 1,5–2,0 | 0,35–0,5 | 12–20 |
| Schärfere Kanten | `Lanczos` | 1,5–2,0 | 0,25–0,45 | 10–20 |
| Maximale Details | ESRGAN/MoSR | 1,5–2,0 | 0,2–0,4 | 8–15 |
| Pixel-Art | `Nearest` / `Latent (nearest)` | 2,0–4,0 | 0,45–0,6 | 8–15 |
| Kein Hires | `None` | – | – | – |

**Faustregeln:**

* Je stärker der Upscale-Faktor, desto niedriger die Denoising-Stärke.
* Modell-Scaler brauchen weniger Denoising, weil sie bereits Details erzeugen.
* Bei OOM (Speicherfehler): `hr_scale` reduzieren oder auf einen Latent-Scaler
  wechseln.

---

## 11. Häufige Fehler

| Symptom | Ursache | Lösung |
|---|---|---|
| Hires-Fix ohne Wirkung | Aufruf an `/v1/images/generations` | `/sdapi/v1/txt2img` verwenden |
| `hr_second_pass_steps` ohne Wirkung | Feldname existiert nicht | `hr_steps` verwenden |
| HTTP 400 `invalid params` | `hr_upscaler` unbekannt/nicht installiert | Namen aus `/sdapi/v1/upscalers` verwenden, Modell installieren |
| Modell-Scaler fehlt in der Liste | kein `--hires-upscalers-dir` gesetzt | `SD_ARGS` ergänzen und Container neu starten |
| „invalid lora/upscaler path" | Pfad oder Endung im Namen | nur den Modell-Stammnamen angeben |
| `Latent` fehlt in `/sdapi/v1/upscalers` | Latent-Modi sind separat | `/sdapi/v1/latent-upscale-modes` abfragen |
| Bild wird trotz Hires nicht größer | `hr_scale` ≤ 1 oder Zielmaße 0 | `hr_scale` > 1 setzen |
| Speicherfehler beim Hires-Pass | Modell-Scaler + große Auflösung | `hr_scale` senken oder Latent-Scaler nutzen |

---

## 12. Weiterführende Dokumentation

* `samplers.md` – Sampler mit Performance-Index und Qualitäts-Ranking
* `README.md` – Betrieb, Vulkan, Modell-Volume
* Projekt `stable-diffusion.cpp`, `docs/esrgan.md` – ESRGAN/MoSR-Unterstützung
