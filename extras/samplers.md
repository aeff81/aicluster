# Sampler-Übersicht für den SD-Cluster (`stable-diffusion.cpp`)

Diese Übersicht dokumentiert alle 22 Sampler, die im `sd-cluster`-Container über den Endpunkt `/sdapi/v1/samplers` verfügbar sind – inklusive **relativem Performance-Index** (0 = langsamster, 100 = schnellster) und **Qualitäts-Ranking** (0 = schwächste, 100 = beste Bildqualität).

---

## Bewertungsgrundlagen

### Performance-Index (0–100)

Der Performance-Index beschreibt die **relative Geschwindigkeit pro fertigem Bild** bei den jeweils empfohlenen Referenz-Steps. Er basiert auf der Anzahl der Modell-Auswertungen (NFE, *Number of Function Evaluations*):

```
Gesamt-NFE = Referenz-Steps × NFE pro Step
Index      = 100 × (NFE_max − NFE) / (NFE_max − NFE_min)
```

* `NFE_min = 6` → schnellster Sampler (`lcm`, `tcd`) → **Index 100**
* `NFE_max = 50` → langsamster Sampler (`dpm++2s_a`) → **Index 0**

Wichtige Hinweise:

* Ein `cfg_scale > 1` verdoppelt die NFE bei **allen** Samplern gleichermaßen (bedingte + unbedingte Auswertung). Das Ranking bleibt dadurch unverändert.
* Die reale Laufzeit hängt zusätzlich von Modell, Auflösung, Hardware und RPC-Latenz ab. Der Index ist ein **theoretischer Relativwert**, kein absoluter Benchmark.
* `lcm` und `tcd` erreichen ihren Spitzenwert nur mit dafür trainierten Modellen (LCM/TCD). Mit normalen Checkpoints sind sie zwar schnell, aber qualitativ unbrauchbar.

### Qualitäts-Score (0–100)

Der Qualitäts-Score bewertet das **erreichbare Bildergebnis** bei den empfohlenen Referenz-Steps. Er ist eine gewichtete Einschätzung aus:

* **Detailtreue** (Feinheiten, Texturen, Kanten)
* **Konvergenz** (Bildstabilität bei steigender Step-Zahl)
* **Artefaktfreiheit** (Farbstiche, Übersättigung, Rauschen)
* **Prompt-Treue** (Befolgung komplexer Anweisungen)
* **Stabilität** (Determinismus bzw. kontrollierbare Varianz)

Der Score ist **modell- und promptabhängig**. Ein niedriger Score bedeutet nicht, dass ein Sampler „schlecht“ ist, sondern dass er für den jeweiligen Zweck spezialisiert oder weniger universell ist.

---

## Performance-Ranking

| Rang | Sampler | NFE/Step | Referenz-Steps | Gesamt-NFE | Performance-Index |
|---:|---|---:|---:|---:|---:|
| 1 | `lcm` | 1 | 6 | 6 | **100** |
| 1 | `tcd` | 1 | 6 | 6 | **100** |
| 3 | `default` | 1 | 20 | 20 | **68** |
| 3 | `euler` | 1 | 20 | 20 | **68** |
| 3 | `dpm++2m` | 1 | 20 | 20 | **68** |
| 3 | `dpm++2mv2` | 1 | 20 | 20 | **68** |
| 3 | `ipndm` | 1 | 20 | 20 | **68** |
| 3 | `ipndm_v` | 1 | 20 | 20 | **68** |
| 3 | `ddim_trailing` | 1 | 20 | 20 | **68** |
| 3 | `res_multistep` | 1 | 20 | 20 | **68** |
| 3 | `er_sde` | 1 | 20 | 20 | **68** |
| 3 | `euler_cfg_pp` | 1 | 20 | 20 | **68** |
| 3 | `euler_ge` | 1 | 20 | 20 | **68** |
| 3 | `dpm++2m_sde` | 1 | 20 | 20 | **68** |
| 15 | `euler_a` | 1 | 25 | 25 | **57** |
| 15 | `euler_a_cfg_pp` | 1 | 25 | 25 | **57** |
| 15 | `dpm++2m_sde_bt` | 1 | 25 | 25 | **57** |
| 18 | `lms` | 1 | 30 | 30 | **45** |
| 19 | `heun` | 2 | 20 | 40 | **23** |
| 19 | `dpm2` | 2 | 20 | 40 | **23** |
| 19 | `res_2s` | 2 | 20 | 40 | **23** |
| 22 | `dpm++2s_a` | 2 | 25 | 50 | **0** |

**Kurzinterpretation:**

* **Schnellste Gruppe (Index 100):** `lcm`, `tcd` – nur mit spezialisierten Modellen sinnvoll.
* **Allrounder (Index 68):** Die große Gruppe der 1-NFE-Sampler bei 20 Steps – der praktische Standard.
* **Stochastisch/detailliert (Index 57):** `euler_a`, `euler_a_cfg_pp`, `dpm++2m_sde_bt`.
* **Rechenintensiv (Index 23–45):** `lms`, `heun`, `dpm2`, `res_2s`.
* **Langsamster (Index 0):** `dpm++2s_a` (2 NFE × 25 Steps).

---

## Qualitäts-Ranking

| Rang | Sampler | Qualitäts-Score | Stärke |
|---:|---|---:|---|
| 1 | `dpm++2m_sde_bt` | **96** | Maximale Detailfeinheit, konsistenteste Rauschstruktur |
| 2 | `dpm++2m_sde` | **94** | Fotorealismus, scharfe Texturen |
| 3 | `dpm++2mv2` | **92** | Sehr saubere Konvergenz, artefaktarm |
| 4 | `dpm++2m` | **90** | Beste Allround-Balance |
| 4 | `dpm++2s_a` | **90** | Sehr detailreich, lebendig (stochastisch) |
| 6 | `er_sde` | **89** | Natürliche Oberflächen, weniger „AI-Look“ |
| 7 | `heun` | **88** | Hohe Präzision, sehr scharfe Kanten |
| 8 | `dpm2` | **87** | Stabile Strukturtreue |
| 9 | `res_multistep` | **86** | Saubere Rauschunterdrückung |
| 10 | `res_2s` | **85** | Präzise Details bei mittleren Steps |
| 10 | `euler_a` | **85** | Kreativ, lebendig, detailreich |
| 12 | `euler_cfg_pp` | **84** | Hohe CFG-Werte ohne Farbstiche |
| 12 | `euler_a_cfg_pp` | **84** | Kreativ + farbstabil bei hohem CFG |
| 14 | `ddim_trailing` | **82** | Deterministisch, reproduzierbar |
| 15 | `ipndm` | **80** | Gute Strukturtreue bei wenigen Steps |
| 15 | `ipndm_v` | **80** | Korrekt für v-Prediction-Modelle |
| 17 | `euler` | **78** | Solide, schnell, vorhersehbar |
| 17 | `default` | **78** | Server-Default, meist identisch mit `euler` |
| 19 | `euler_ge` | **76** | Kantenschärfung, teils überschärft |
| 20 | `lms` | **72** | Klassisch, benötigt viele Steps |
| 21 | `tcd` | **70** | Nur mit TCD-Modellen/LoRAs sinnvoll |
| 22 | `lcm` | **65** | Nur mit LCM-Modellen/LoRAs sinnvoll |

**Kurzinterpretation:**

* **Spitzenklasse (90+):** `dpm++2m_sde_bt`, `dpm++2m_sde`, `dpm++2mv2`, `dpm++2m`, `dpm++2s_a`.
* **Sehr gute Spezialisten (85–89):** `er_sde` (Realismus), `heun`/`dpm2` (Präzision), `res_*` (Stabilität), `euler_a` (Kreativität).
* **Gute Allrounder (78–84):** `euler`, `default`, `ddim_trailing`, `ipndm`, `euler_cfg_pp`.
* **Spezial-/Legacy-Fälle (< 78):** `lms`, `euler_ge`, `tcd`, `lcm`.

---

## Detaillierte Dokumentation der Sampler

### 1. `default`
* **Performance-Index:** 68/100 (20 Steps × 1 NFE = 20 NFE)
* **Qualitäts-Score:** 78/100
* **Beschreibung:** Server-Standard; in `stable-diffusion.cpp` in der Regel identisch mit `euler`.
* **Einsatzgebiete:** Schnelltests, wenn kein expliziter Sampler angegeben ist.
* **Performance:** Sehr schnell (1 Evaluation pro Step).
* **Stärken:** Unkompliziert, stabil, guter Ausgangspunkt.
* **Schwächen:** Keine spezifischen Optimierungen gegenüber `euler`.
* **Empfohlene Parameter:** `steps`: 20–25, `cfg_scale`: 7.0.

---

### 2. `euler` (Euler ODE Solver)
* **Performance-Index:** 68/100 (20 Steps × 1 NFE = 20 NFE)
* **Qualitäts-Score:** 78/100
* **Einsatzgebiete:** Schnelle Entwürfe, allgemeine Bildgenerierung, saubere Vektorkunst.
* **Performance:** **Extrem schnell.** Konvergiert bereits ab 15–20 Schritten.
* **Stärken:** Deterministisch, sehr stabil, keine unerwarteten Bildänderungen bei mehr Steps.
* **Schwächen:** Kann bei sehr niedrigen Step-Zahlen etwas glatt/weich wirken.
* **Empfohlene Parameter:** `steps`: 20, `cfg_scale`: 6.0–8.0.

---

### 3. `euler_a` (Euler Ancestral)
* **Performance-Index:** 57/100 (25 Steps × 1 NFE = 25 NFE)
* **Qualitäts-Score:** 85/100
* **Einsatzgebiete:** Anime, Fantasy, kreative Bildkompositionen, detaillierte Landschaften.
* **Performance:** Sehr schnell (1 Evaluation pro Step).
* **Stärken:** **Stochastisch.** Fügt bei jedem Schritt etwas Rauschen hinzu. Erzeugt lebendige Details und eine natürliche Varianz.
* **Schwächen:** Nicht deterministisch über unterschiedliche Step-Zahlen hinweg; konvergiert nie vollständig zu einem festen Bild.
* **Empfohlene Parameter:** `steps`: 20–30, `cfg_scale`: 7.0.

---

### 4. `heun`
* **Performance-Index:** 23/100 (20 Steps × 2 NFE = 40 NFE)
* **Qualitäts-Score:** 88/100
* **Einsatzgebiete:** Hochpräzise Generierung, fotorealistische Details.
* **Performance:** **Langsam.** Benötigt 2 Evaluationen pro Schritt (doppelte Rechenzeit im Vergleich zu Euler).
* **Stärken:** Sehr präzises Verfahren 2. Ordnung. Erreicht bereits mit wenigen Schritten (15–20) hervorragende Schärfe.
* **Schwächen:** Bei gleicher Step-Zahl doppelt so lange Laufzeit.
* **Empfohlene Parameter:** `steps`: 15–25, `cfg_scale`: 7.0.

---

### 5. `dpm2` (Diffusion Probabilistic Model Solver 2)
* **Performance-Index:** 23/100 (20 Steps × 2 NFE = 40 NFE)
* **Qualitäts-Score:** 87/100
* **Einsatzgebiete:** Präzise Bilder mit hohem Detailgrad.
* **Performance:** Moderat bis langsam (2 Evaluationen pro Schritt).
* **Stärken:** Sehr stabile Konvergenz, hohe strukturelle Treue.
* **Schwächen:** Rechenintensiver pro Schritt.
* **Empfohlene Parameter:** `steps`: 15–25, `cfg_scale`: 7.0–8.0.

---

### 6. `dpm++2s_a` (DPM++ 2S Ancestral)
* **Performance-Index:** 0/100 (25 Steps × 2 NFE = 50 NFE)
* **Qualitäts-Score:** 90/100
* **Einsatzgebiete:** Detaillierte Porträts, komplexe Texturen, künstlerische Motive.
* **Performance:** **Langsamster Sampler** im Set (2-Step-Ancestral-Verfahren).
* **Stärken:** Hervorragendes Rauschverhalten und exzellente Detailschärfe durch die Ancestral-Komponente.
* **Schwächen:** Benötigt mehr Steps als `dpm++2m`, um völlig rauschfrei zu werden; höchster Rechenaufwand.
* **Empfohlene Parameter:** `steps`: 20–30, `cfg_scale`: 6.5–8.0.

---

### 7. `dpm++2m` (DPM++ 2M)
* **Performance-Index:** 68/100 (20 Steps × 1 NFE = 20 NFE)
* **Qualitäts-Score:** 90/100
* **Einsatzgebiete:** **Der Allround-Standard** für SD 1.5, SDXL und moderne Checkpoints.
* **Performance:** **Exzellent.** Multistep-Verfahren 2. Ordnung ohne zusätzliche Auswertungen (1 Evaluation pro Step).
* **Stärken:** Hervorragende Balance aus Geschwindigkeit und Bildqualität. Konvergiert schnell und sauber.
* **Schwächen:** Bei sehr hohen CFG-Werten manchmal Neigung zu Übersättigung (hier hilft `dpm++2mv2`).
* **Empfohlene Parameter:** `steps`: 20–25, `cfg_scale`: 7.0.

---

### 8. `dpm++2mv2` (DPM++ 2M Version 2)
* **Performance-Index:** 68/100 (20 Steps × 1 NFE = 20 NFE)
* **Qualitäts-Score:** 92/100
* **Einsatzgebiete:** Universeller Einsatz, besonders wenn `dpm++2m` bei bestimmten Prompts Artefakte erzeugt.
* **Performance:** Sehr schnell (1 NFE pro Step).
* **Stärken:** Überarbeitetes Koeffizienten-Schema von DPM++ 2M. Verhindert Farbverschiebungen und Artefakte bei höheren Step-Zahlen oder CFG-Werten.
* **Schwächen:** Keine bekannt.
* **Empfohlene Parameter:** `steps`: 20–25, `cfg_scale`: 6.5–8.0.

---

### 9. `ipndm` (Improved Pseudo Numerical Methods)
* **Performance-Index:** 68/100 (20 Steps × 1 NFE = 20 NFE)
* **Qualitäts-Score:** 80/100
* **Einsatzgebiete:** Schnelle Generierung, lineare Differentialgleichungsprozesse.
* **Performance:** Schnell (1 NFE pro Step).
* **Stärken:** Gute Strukturtreue bei niedrigen Step-Zahlen.
* **Schwächen:** Bei komplexen Prompts manchmal weniger detailliert als DPM++-Varianten.
* **Empfohlene Parameter:** `steps`: 15–25, `cfg_scale`: 7.0.

---

### 10. `ipndm_v` (iPNDM Velocity Variant)
* **Performance-Index:** 68/100 (20 Steps × 1 NFE = 20 NFE)
* **Qualitäts-Score:** 80/100
* **Einsatzgebiete:** Speziell für Modelle, die mit **v-parameterization / v-prediction** trainiert wurden (z. B. SD 2.1 768px).
* **Performance:** Schnell (1 NFE pro Step).
* **Stärken:** Vermeidet Farb- und Kontrastfehler bei v-Prediction-Modellen.
* **Schwächen:** Ungeeignet für Standard-epsilon-prediction-Modelle (wie klassisches SD 1.5).
* **Empfohlene Parameter:** `steps`: 20–25, `cfg_scale`: 7.5.

---

### 11. `lcm` (Latent Consistency Model)
* **Performance-Index:** 100/100 (6 Steps × 1 NFE = 6 NFE)
* **Qualitäts-Score:** 65/100
* **Einsatzgebiete:** **Ultra-Fast-Inferenz** (Echtzeit-Generierung, Vorschau-Pipelines).
* **Performance:** **Schnellster Sampler** im Set (4–8 Steps).
* **Stärken:** Erzeugt in nur 4 bis 8 Schritten fertige Bilder.
* **Schwächen:** Erfordert **LCM-Modelle** oder **LCM-LoRAs**. Mit normalen SD-Checkpoints sind die Ergebnisse verschwommen oder unbrauchbar.
* **Empfohlene Parameter:** `steps`: 4–8, `cfg_scale`: 1.0–2.0 (sehr niedriger CFG-Wert Pflicht!).

---

### 12. `ddim_trailing` (DDIM mit Trailing Timesteps)
* **Performance-Index:** 68/100 (20 Steps × 1 NFE = 20 NFE)
* **Qualitäts-Score:** 82/100
* **Einsatzgebiete:** Deterministische Inferenz, konsistente Bildserien, Video-Frames.
* **Performance:** Sehr schnell (1 NFE pro Step).
* **Stärken:** Passt das Timestep-Grid an („trailing“), sodass auch die letzten Entrauschungsschritte optimal genutzt werden. Sehr hohe Reproduzierbarkeit.
* **Schwächen:** Bei niedrigen Steps (unter 15) weichere Konturen.
* **Empfohlene Parameter:** `steps`: 20–30, `cfg_scale`: 7.0.

---

### 13. `tcd` (Trajectory Consistency Distillation)
* **Performance-Index:** 100/100 (6 Steps × 1 NFE = 6 NFE)
* **Qualitäts-Score:** 70/100
* **Einsatzgebiete:** Ultra-schnelle Generierung mit hoher Detailgenauigkeit.
* **Performance:** **Schnellster Sampler** im Set (4–8 Steps).
* **Stärken:** Bessere Bildqualität und Detailtreue als `lcm` bei extrem niedrigen Schrittzahlen.
* **Schwächen:** Benötigt TCD-LoRAs oder destillierte Checkpoints.
* **Empfohlene Parameter:** `steps`: 4–10, `cfg_scale`: 1.5–3.0.

---

### 14. `res_multistep` (Residual Equilibrium Solver Multistep)
* **Performance-Index:** 68/100 (20 Steps × 1 NFE = 20 NFE)
* **Qualitäts-Score:** 86/100
* **Einsatzgebiete:** Alternative zu DPM++ für saubere Rauschunterdrückung.
* **Performance:** Schnell (1 NFE pro Step).
* **Stärken:** Stabile Rauschreduzierung, verhindert Schärfeverlust an Kanten.
* **Schwächen:** Weniger verbreitet; erfordert gelegentlich feineres Tuning der Step-Zahl.
* **Empfohlene Parameter:** `steps`: 20–25, `cfg_scale`: 7.0.

---

### 15. `res_2s` (RES 2-Step)
* **Performance-Index:** 23/100 (20 Steps × 2 NFE = 40 NFE)
* **Qualitäts-Score:** 85/100
* **Einsatzgebiete:** Präzise Details bei mittleren Schrittzahlen.
* **Performance:** Moderat bis langsam (2 NFE pro Step).
* **Stärken:** Hohe mathematische Präzision beim Entrauschen.
* **Schwächen:** Etwas langsamer als Multistep-Verfahren.
* **Empfohlene Parameter:** `steps`: 20–30, `cfg_scale`: 7.0.

---

### 16. `er_sde` (Euler-Maruyama SDE)
* **Performance-Index:** 68/100 (20 Steps × 1 NFE = 20 NFE)
* **Qualitäts-Score:** 89/100
* **Einsatzgebiete:** Fotorealistische Texturen, Hautdetails, Haare, Naturaufnahmen.
* **Performance:** Schnell bis moderat (1 NFE pro Step).
* **Stärken:** Stochastischer SDE-Solver. Verhindert den plastischen „AI-Look“ durch kontinuierliches Zufallsrauschen.
* **Schwächen:** Kann bei zu vielen Steps körnig wirken.
* **Empfohlene Parameter:** `steps`: 20–30, `cfg_scale`: 6.0–7.5.

---

### 17. `euler_cfg_pp` (Euler mit CFG++)
* **Performance-Index:** 68/100 (20 Steps × 1 NFE = 20 NFE)
* **Qualitäts-Score:** 84/100
* **Einsatzgebiete:** Generierung mit **hohem CFG-Scale** (z. B. striktes Befolgen komplexer Prompts).
* **Performance:** Sehr schnell (1 NFE pro Step).
* **Stärken:** Nutzt die **CFG++ Rescaling-Technik**. Verhindert das typische „Einbrennen“ (Ausfressen von Farben und Ausbleichen von Kontrasten) bei hohem CFG-Wert (> 10).
* **Schwächen:** Keine bei hohen CFG-Werten.
* **Empfohlene Parameter:** `steps`: 20–25, `cfg_scale`: 9.0–15.0.

---

### 18. `euler_a_cfg_pp` (Euler Ancestral mit CFG++)
* **Performance-Index:** 57/100 (25 Steps × 1 NFE = 25 NFE)
* **Qualitäts-Score:** 84/100
* **Einsatzgebiete:** Künstlerische Bilder mit hoher Prompt-Treue und hohen CFG-Werten.
* **Performance:** Sehr schnell (1 NFE pro Step).
* **Stärken:** Vereint die lebendigen Details von `euler_a` mit der Farbstabilität von CFG++.
* **Schwächen:** Stochastisch (nicht deterministisch).
* **Empfohlene Parameter:** `steps`: 20–30, `cfg_scale`: 9.0–14.0.

---

### 19. `euler_ge` (Euler Gradient-Enhanced / Guided)
* **Performance-Index:** 68/100 (20 Steps × 1 NFE = 20 NFE)
* **Qualitäts-Score:** 76/100
* **Einsatzgebiete:** Experimentelle Bildgenerierung, scharfe Konturen.
* **Performance:** Sehr schnell (1 NFE pro Step).
* **Stärken:** Verbesserte Gradientenführung zur Kanten- und Strukturschärfung.
* **Schwächen:** Bei manchen Modellen Neigung zu Überschärfung.
* **Empfohlene Parameter:** `steps`: 20–25, `cfg_scale`: 7.0.

---

### 20. `dpm++2m_sde` (DPM++ 2M Stochastic Differential Equation)
* **Performance-Index:** 68/100 (20 Steps × 1 NFE = 20 NFE)
* **Qualitäts-Score:** 94/100
* **Einsatzgebiete:** **Erstklassiger Fotorealismus.**
* **Performance:** Sehr gut (1 NFE pro Step).
* **Stärken:** Verbindet die schnelle Konvergenz von `dpm++2m` mit stochastischem SDE-Rauschen. Erzeugt gestochen scharfe Details und natürliche Oberflächenstrukturen.
* **Schwächen:** Benötigt manchmal 2–5 Steps mehr als reguläres `dpm++2m`.
* **Empfohlene Parameter:** `steps`: 20–30, `cfg_scale`: 6.5–7.5.

---

### 21. `dpm++2m_sde_bt` (DPM++ 2M SDE Brownian Tree)
* **Performance-Index:** 57/100 (25 Steps × 1 NFE = 25 NFE)
* **Qualitäts-Score:** 96/100
* **Einsatzgebiete:** **Höchste Bildqualität & maximale Detailfeinheit.**
* **Performance:** Sehr gut (1 NFE pro Step).
* **Stärken:** Nutzt einen *Brownian Tree* (Brownsche Bewegung) für das Rauschen. Bietet die konsistenteste und am feinsten verteilte Rauschstruktur aller Sampler. Top-Empfehlung für High-End-Outputs.
* **Schwächen:** Keine wesentlichen.
* **Empfohlene Parameter:** `steps`: 25–35, `cfg_scale`: 6.5–8.0.

---

### 22. `lms` (Linear Multistep Scheduler)
* **Performance-Index:** 45/100 (30 Steps × 1 NFE = 30 NFE)
* **Qualitäts-Score:** 72/100
* **Einsatzgebiete:** Klassische Stable-Diffusion-Generierung (Legacy).
* **Performance:** Moderat (1 NFE pro Step, aber hohe Step-Zahl nötig).
* **Stärken:** Deterministisch, historischer Standard-Sampler.
* **Schwächen:** Konvergiert langsamer als neuere DPM++-Sampler. Kann bei niedrigen Steps unvollständig oder unscharf wirken.
* **Empfohlene Parameter:** `steps`: 30–50, `cfg_scale`: 7.0.

---

## Praxistipps zur Auswahl

| Ziel | Empfehlung | Begründung |
|---|---|---|
| **Schneller Allrounder** | `dpm++2m` | Beste Balance aus Index 68 und Score 90 |
| **Maximale Qualität** | `dpm++2m_sde_bt` | Score 96, etwas langsamer (Index 57) |
| **Fotorealismus** | `dpm++2m_sde` oder `er_sde` | Scharfe, natürliche Texturen |
| **Kreativ/Anime** | `euler_a` | Lebendige, variable Details |
| **Hoher CFG-Wert** | `euler_cfg_pp` | Keine Farbstiche bei CFG > 10 |
| **Echtzeit/Vorschau** | `lcm` oder `tcd` | Index 100, aber nur mit passenden Modellen |
| **Reproduzierbarkeit** | `ddim_trailing` oder `euler` | Deterministisch und stabil |
| **v-Prediction-Modelle** | `ipndm_v` | Vermeidet Farb-/Kontrastfehler |

---

## API-Beispiel

```bash
curl -s -X POST http://cluster:8080/sdapi/v1/txt2img \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "a lovely cat in a space suit, high quality",
    "width": 512,
    "height": 512,
    "cfg_scale": 7.0,
    "steps": 20,
    "sampler_name": "dpm++2m"
  }' | jq -r '.images[0]' | base64 -d > /opt/modelle/mein_bild.png
```

> **Hinweis:** Der A1111-kompatible Endpunkt akzeptiert die Sampler-Namen aus der Liste oben. Die genaue Schreibweise (z. B. `dpm++2m` statt `DPM++ 2M`) kann je nach Server-Build variieren; im Zweifel `curl http://cluster:8080/sdapi/v1/samplers` abfragen.
