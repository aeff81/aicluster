#!/usr/bin/env bash
#
# genimage.sh – ein Bild über den sd-cluster erzeugen
#
# Aufruf:
#   ./genimage.sh                 -> <aktuelle UNIX-Zeit>.png
#   ./genimage.sh katze.png
#   ./genimage.sh /opt/modelle/katze.png
#
# Die Job-ID wird auf stdout ausgegeben, alle Meldungen gehen nach stderr.
# Ergebnis bis 10 Minuten nach Abschluss erneut abholen:
#   curl -s "http://192.168.41.42:8080/sdcpp/v1/jobs/JOB_ID" \
#     | jq -r '.result.images[0].b64_json' | base64 -d > bild.png
#
set -Eeuo pipefail

# ==================== EINSTELLUNGEN ====================
SERVER='http://cluster:8080'

PROMPT='cat playing with ball'
NEGATIV_PROMPT='humans, bad anatomy'
WIDTH=768
HEIGHT=512
STEPS=20
CFG=4.5
SAMPLER='dpm++2m_sde'
SCHEDULER='karras'        # '' = Standard des Servers
SEED=-1                   # -1 = zufällig

SCALING=0                 # 0 = ohne Hires-Fix, 1 = mit Hires-Fix
UPSCALER='Latent (bicubic)'
SCALE=2.0                 # Vergrößerung (nur bei SCALING=1)
HIRES_STEPS=15            # Steps im zweiten Durchlauf (nur bei SCALING=1)
DENOISING=0.35            # 0.0–1.0 (nur bei SCALING=1)

OUTPUT_DIR=''             # '' = aktuelles Verzeichnis, z. B. '/opt/modelle'
# ======================================================

die() {
    printf '\nFehler: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<EOF
Aufruf: $(basename "$0") [OPTION] [AUSGABEDATEI]

Ohne Dateiname wird <aktuelle UNIX-Zeit>.png verwendet.
Die Job-ID erscheint auf stdout, alle Meldungen auf stderr.

Optionen:
  -n, --dry-run   nur den JSON-Payload anzeigen, nichts generieren
  -h, --help      diese Hilfe anzeigen

Beispiele:
  $(basename "$0")
  $(basename "$0") katze.png
  $(basename "$0") /opt/modelle/katze.png
  $(basename "$0") --dry-run

Einstellungen (Prompt, Größe, Steps, Sampler, Hires-Fix usw.) stehen
oben im Skript im Block "EINSTELLUNGEN".
EOF
}

is_int() { [[ "$1" =~ ^-?[0-9]+$ ]]; }
is_num() { [[ "$1" =~ ^-?([0-9]+([.][0-9]*)?|[.][0-9]+)$ ]]; }

# ---------- Argumente und Dateiname ----------
dry_run=0
args=()
for arg in "$@"; do
    case "$arg" in
        -h|--help)    usage; exit 0 ;;
        -n|--dry-run) dry_run=1 ;;
        -*)           die "Unbekannte Option: $arg (siehe --help)." ;;
        *)            args+=("$arg") ;;
    esac
done

[[ ${#args[@]} -le 1 ]] || die "Höchstens eine Ausgabedatei angeben (siehe --help)."

OUTFILE="${args[0]:-$(date +%s).png}"
if [[ "${OUTFILE##*/}" != *.* ]]; then
    OUTFILE="${OUTFILE}.png"
fi
if [[ -n "$OUTPUT_DIR" && "$OUTFILE" != */* ]]; then
    OUTFILE="${OUTPUT_DIR%/}/$OUTFILE"
fi

# ---------- Abhängigkeiten ----------
for cmd in curl jq base64 mktemp stat od; do
    command -v "$cmd" >/dev/null 2>&1 || die "Benötigtes Programm fehlt: $cmd"
done

# ---------- Einstellungen prüfen ----------
is_int "$WIDTH"  || die "WIDTH muss eine ganze Zahl sein."
is_int "$HEIGHT" || die "HEIGHT muss eine ganze Zahl sein."
is_int "$STEPS"  || die "STEPS muss eine ganze Zahl sein."
is_int "$SEED"   || die "SEED muss eine ganze Zahl sein (-1 = zufällig)."
is_num "$CFG"    || die "CFG muss eine Zahl sein."

(( WIDTH > 0 && HEIGHT > 0 )) || die "WIDTH und HEIGHT müssen positiv sein."
(( STEPS >= 1 ))              || die "STEPS muss mindestens 1 sein."
(( WIDTH % 8 == 0 ))          || printf 'Warnung: WIDTH ist nicht durch 8 teilbar.\n' >&2
(( HEIGHT % 8 == 0 ))         || printf 'Warnung: HEIGHT ist nicht durch 8 teilbar.\n' >&2

[[ "$SCALING" == 0 || "$SCALING" == 1 ]] || die "SCALING muss 0 oder 1 sein."
[[ -n "$SAMPLER" ]] || die "SAMPLER darf nicht leer sein."
[[ -n "$PROMPT" ]]  || die "PROMPT darf nicht leer sein."

if [[ "$SCALING" == 1 ]]; then
    is_num "$SCALE"     || die "SCALE muss eine Zahl sein."
    is_num "$DENOISING" || die "DENOISING muss eine Zahl sein."
    is_int "$HIRES_STEPS" || die "HIRES_STEPS muss eine ganze Zahl sein."
    awk -v v="$SCALE" 'BEGIN { exit !(v > 0) }' \
        || die "SCALE muss größer als 0 sein."
    awk -v v="$DENOISING" 'BEGIN { exit !(v >= 0 && v <= 1) }' \
        || die "DENOISING muss zwischen 0 und 1 liegen."
    (( HIRES_STEPS >= 0 )) || die "HIRES_STEPS darf nicht negativ sein."
fi

# ---------- Sampler prüfen ----------
samplers="$(curl -sS --connect-timeout 5 --max-time 10 \
    "$SERVER/sdapi/v1/samplers" 2>/dev/null || true)"

if [[ -n "$samplers" ]] && jq -e 'type == "array"' >/dev/null 2>&1 <<<"$samplers"; then
    if ! jq -e --arg s "$SAMPLER" 'any(.[]; .name == $s)' \
            >/dev/null 2>&1 <<<"$samplers"; then
        die "Sampler '$SAMPLER' ist unbekannt. Verfügbar: $(jq -r 'map(.name) | join(", ")' <<<"$samplers")"
    fi
fi

# ---------- Upscaler prüfen (nur bei SCALING=1) ----------
if [[ "$SCALING" == 1 ]]; then
    upscalers="$(curl -sS --connect-timeout 5 --max-time 10 \
        "$SERVER/sdapi/v1/upscalers" 2>/dev/null || true)"
    latent="$(curl -sS --connect-timeout 5 --max-time 10 \
        "$SERVER/sdapi/v1/latent-upscale-modes" 2>/dev/null || true)"

    names="$(
        { jq -r '.[].name' <<<"$upscalers" 2>/dev/null || true
          jq -r '.[].name' <<<"$latent" 2>/dev/null || true; } | sed '/^$/d'
    )"

    if [[ -n "$names" ]] && ! grep -qxF "$UPSCALER" <<<"$names"; then
        die "Upscaler '$UPSCALER' ist unbekannt. Verfügbar: $(paste -sd ',' <<<"$names" | sed 's/,/, /g')"
    fi
fi

# ---------- Payload bauen ----------
payload="$(jq -n \
    --arg prompt "$PROMPT" \
    --arg negative_prompt "$NEGATIV_PROMPT" \
    --arg sampler "$SAMPLER" \
    --arg scheduler "$SCHEDULER" \
    --arg upscaler "$UPSCALER" \
    --argjson width "$WIDTH" \
    --argjson height "$HEIGHT" \
    --argjson steps "$STEPS" \
    --argjson cfg "$CFG" \
    --argjson seed "$SEED" \
    --argjson scaling "$SCALING" \
    --argjson scale "$SCALE" \
    --argjson hires_steps "$HIRES_STEPS" \
    --argjson denoising "$DENOISING" \
    '{
        prompt: $prompt,
        negative_prompt: $negative_prompt,
        width: $width,
        height: $height,
        seed: $seed,
        batch_count: 1,
        output_format: "png",
        sample_params: ({
            sample_method: $sampler,
            sample_steps: $steps,
            guidance: { txt_cfg: $cfg }
        } + (if $scheduler != "" then {scheduler: $scheduler} else {} end)),
        hires: (if $scaling == 1
                then {
                    enabled: true,
                    upscaler: $upscaler,
                    scale: $scale,
                    steps: $hires_steps,
                    denoising_strength: $denoising
                }
                else { enabled: false } end)
    }')" || die "Payload konnte nicht erzeugt werden."

if [[ "$dry_run" == 1 ]]; then
    echo "DRY_RUN: es wird nichts generiert." >&2
    printf '%s\n' "$payload"
    exit 0
fi

# ---------- Ausgabeziel ----------
mkdir -p "$(dirname "$OUTFILE")" || die "Verzeichnis für '$OUTFILE' kann nicht erstellt werden."
if [[ -e "$OUTFILE" ]]; then
    echo "Überschreibe vorhandene Datei: $OUTFILE" >&2
fi
if [[ "$OUTFILE" != *.png ]]; then
    printf 'Warnung: es wird immer PNG geschrieben.\n' >&2
fi

# ---------- Job anlegen ----------
tmp="$(mktemp -d "${TMPDIR:-/tmp}/genimage.XXXXXX")" \
    || die "Temporäres Verzeichnis kann nicht erstellt werden."
trap 'rm -rf "$tmp"' EXIT

printf '%s\n' "$payload" > "$tmp/payload.json"

echo "Generiere ${WIDTH}x${HEIGHT}, ${STEPS} Steps, Sampler $SAMPLER ..." >&2
if [[ "$SCALING" == 1 ]]; then
    echo "Hires-Fix: ${SCALE}x mit '$UPSCALER', ${HIRES_STEPS} Steps, Denoising $DENOISING" >&2
fi
echo "Ziel: $OUTFILE" >&2

http_code="$(curl -sS --connect-timeout 10 \
    -o "$tmp/submit.json" -w '%{http_code}' \
    -X POST "$SERVER/sdcpp/v1/img_gen" \
    -H 'Content-Type: application/json' \
    --data-binary "@$tmp/payload.json")" \
    || die "Verbindung zu $SERVER fehlgeschlagen."

if [[ "$http_code" != 202 ]]; then
    jq . "$tmp/submit.json" >&2 2>/dev/null || cat "$tmp/submit.json" >&2
    die "Server hat den Auftrag abgelehnt (HTTP $http_code)."
fi

JOB_ID="$(jq -r '.id // empty' "$tmp/submit.json")"
[[ -n "$JOB_ID" && "$JOB_ID" != null ]] || die "Server lieferte keine Job-ID."
[[ "$JOB_ID" =~ ^[A-Za-z0-9_-]+$ ]] || die "Ungültige Job-ID: '$JOB_ID'"

printf '%s\n' "$JOB_ID"       # stdout: nur die Job-ID
echo "Warte auf Job $JOB_ID ..." >&2

# ---------- Auf Ergebnis warten ----------
last_line=""
while :; do
    http_code="$(curl -sS --connect-timeout 10 \
        -o "$tmp/job.json" -w '%{http_code}' \
        "$SERVER/sdcpp/v1/jobs/$JOB_ID")" \
        || die "Verbindung zu $SERVER bei der Statusabfrage fehlgeschlagen."

    case "$http_code" in
        200) ;;
        404) die "Job '$JOB_ID' nicht gefunden (Server neu gestartet?)." ;;
        410) die "Job '$JOB_ID' ist abgelaufen (Ergebnisse nur 10 Minuten gültig)." ;;
        *)   jq . "$tmp/job.json" >&2 2>/dev/null || cat "$tmp/job.json" >&2
             die "Statusabfrage fehlgeschlagen (HTTP $http_code)." ;;
    esac

    status="$(jq -r '.status // empty' "$tmp/job.json")"
    stage="$(jq -r '.progress.stage // empty' "$tmp/job.json")"
    done_n="$(jq -r '.progress.completed // empty' "$tmp/job.json")"
    total_n="$(jq -r '.progress.total // empty' "$tmp/job.json")"

    line="Status: $status"
    if [[ -n "$stage" ]]; then
        line+=" – $stage"
    fi
    if [[ -n "$done_n" && "$done_n" != null && -n "$total_n" && "$total_n" != null ]]; then
        line+=" ($done_n/$total_n)"
    fi
    if [[ "$line" != "$last_line" ]]; then
        echo "$line" >&2
        last_line="$line"
    fi

    case "$status" in
        completed) break ;;
        failed|cancelled)
            die "Job $status: $(jq -r '.error.code // "?"' "$tmp/job.json") – $(jq -r '.error.message // "kein Fehlertext"' "$tmp/job.json")"
            ;;
        queued|generating) ;;
        *) die "Unerwarteter Job-Status: '$status'" ;;
    esac

    sleep 2
done

# ---------- Bild speichern ----------
if ! jq -e '.result.images | type == "array" and length > 0' \
        >/dev/null 2>&1 < "$tmp/job.json"; then
    jq . "$tmp/job.json" >&2 2>/dev/null || cat "$tmp/job.json" >&2
    die "Antwort enthält kein Bild."
fi

b64="$(jq -r '.result.images[0].b64_json // empty' "$tmp/job.json")"
[[ -n "$b64" ]] || die "Bilddaten fehlen in der Antwort."

printf '%s' "$b64" | base64 -d > "$tmp/image" \
    || die "Bilddaten konnten nicht dekodiert werden."

size="$(stat -c%s "$tmp/image")"
(( size >= 100 )) || die "Erzeugte Datei ist nur $size Bytes groß – kein gültiges Bild."

magic="$(od -An -tx1 -N4 "$tmp/image" | tr -d ' \n')"
case "$magic" in
    89504e47) ;;   # PNG
    ffd8ff*)  ;;   # JPEG
    *) die "Unbekanntes Bildformat (Magic Bytes: $magic)." ;;
esac

mv -f "$tmp/image" "$OUTFILE" || die "Datei konnte nicht nach '$OUTFILE' geschrieben werden."

# ---------- Kontrolle ----------
actual="$(jq -r '.result.images[0].generation_info
    | if type == "string" then fromjson else . end
    | .sample_params.sample_method // empty' "$tmp/job.json" 2>/dev/null || true)"

if [[ -n "$actual" && "$actual" != "$SAMPLER" ]]; then
    echo "Warnung: Server nutzte '$actual' statt '$SAMPLER'." >&2
fi

echo "Fertig: $OUTFILE ($(stat -c%s "$OUTFILE") Bytes)" >&2
if [[ -n "$actual" ]]; then
    echo "Sampler: $actual" >&2
fi
echo "Job-ID: $JOB_ID (10 Minuten abrufbar)" >&2
