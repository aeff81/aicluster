#!/bin/bash
set -e

# SD_ROLE kann 'MASTER', 'LLAMA' oder 'RPC' sein
# SD_MODEL_PATH: Pfad zum Modell innerhalb des Containers (Standard: /models/model.gguf)
#                 Bewusst leer setzen (SD_MODEL_PATH=""), um ohne Modell zu starten
#                 und die Auswahl ueber die Web-UI zu treffen.
# SD_ARGS: Zusätzliche Argumente für sd-server, llama-server oder rpc-server

SD_MODEL_PATH=${SD_MODEL_PATH-/models/model.gguf}

case "$SD_ROLE" in
    "MASTER")
        echo "Starte als Stable Diffusion Master..."
        # sd-server nutzt --listen-ip/--listen-port (nicht --host/--port wie llama-server).
        # Ist SD_MODEL_PATH leer, startet der Server ohne Modell; die Auswahl
        # erfolgt dann ueber die Web-UI (dafuer --model-dir /models in SD_ARGS setzen).
        MODEL_ARGS=()
        if [ -n "$SD_MODEL_PATH" ]; then
            MODEL_ARGS=(--model "$SD_MODEL_PATH")
        fi
        exec ./sd-server --listen-ip 0.0.0.0 --listen-port 8080 "${MODEL_ARGS[@]}" $SD_ARGS
        ;;
    "LLAMA")
        echo "Starte als LLama Server..."
        exec ./llama-server --host 0.0.0.0 --port 8081 --model "$SD_MODEL_PATH" $SD_ARGS
        ;;
    "RPC")
        echo "Starte als RPC-Worker..."
        exec ./rpc-server --host 0.0.0.0 --port 50052 $SD_ARGS
        ;;
    *)
        echo "Fehler: SD_ROLE muss auf MASTER, LLAMA oder RPC gesetzt sein."
        exit 1
        ;;
esac
