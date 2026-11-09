# Stage 1: Build
FROM debian:trixie-slim AS builder

ARG DEBIAN_FRONTEND=noninteractive

# Vulkan kann beim Build abgeschaltet werden (--build-arg WITH_VULKAN=OFF).
# Standard ist ON, damit GPU-Beschleunigung ohne CPU-Zwang verfügbar ist.
ARG WITH_VULKAN=ON

# Quellstand fuer llama-server (LLM-Rolle). Der Pin aus sync-llama.last ist
# fuer viele neuere Architekturen zu alt (z. B. LFM3, aufgenommen am
# 27.10.2026). Leer lassen, um wieder exakt den Pin zu verwenden.
# Siehe ausfuehrliche Begruendung beim llama-server-Build weiter unten.
ARG LLAMA_SERVER_REF=9f0d80cf4aa781878742d1002fac114c18b76974

# Build-Werkzeuge, Vulkan-Toolchain (glslc + SPIRV-Headers) sowie
# Node.js/pnpm fuer die Web-UI des sd-servers.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    git \
    ca-certificates \
    libwebp-dev \
    libvulkan-dev \
    glslc \
    glslang-tools \
    spirv-headers \
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# pnpm exakt in der Version, die das Frontend in seinem packageManager-Feld fordert.
# Ohne pnpm deaktiviert CMake die Web-UI (HAVE_INDEX_HTML bleibt aus).
RUN npm install -g pnpm@10.15.1 && npm cache clean --force && pnpm --version

# Stable Diffusion C++ klonen und builden
RUN git clone --depth 1 https://github.com/leejet/stable-diffusion.cpp.git /sdcpp
WORKDIR /sdcpp
RUN git submodule update --init --recursive
# Hack: static_assert fuer GGML_OP_COUNT entfernen, da dies sonst den Build bricht
RUN sed -i '/static_assert(GGML_OP_COUNT ==/d' ggml/include/ggml-rpc.h

# -DSD_VULKAN=ON aktiviert den Vulkan-Backend; das Frontend wird automatisch
# mitgebaut, weil pnpm im PATH liegt. Die UI landet fest eingebettet im Binary.
RUN mkdir build && cd build && \
    cmake .. -DSD_BUILD_SERVER=ON -DSD_RPC=ON -DSD_VULKAN=${WITH_VULKAN} && \
    cmake --build . --config Release -j $(nproc) && \
    SD_BIN=$(find . -type f -name "sd-server" -executable | head -n1) && \
    echo "SD-Binary: $SD_BIN" && test -n "$SD_BIN" && \
    cp "$SD_BIN" /sd-server-binary

# ---------------------------------------------------------------------------
# RPC-Worker (rpc-server) fuer stable-diffusion.cpp
# ---------------------------------------------------------------------------
# Die Version wird nicht geraten, sondern aus der Submodul-Datei gelesen.
# rpc-server und sd-server muessen dasselbe GGML-RPC-Protokoll sprechen,
# deshalb bleibt dieser Build exakt am Pin von stable-diffusion.cpp.
# Wichtig: Ein Schalter GGML_BUILD_SHARED_LIBS existiert in llama.cpp/ggml
# nicht. Die Bibliotheken werden ueber das Standard-CMake-Schalter
# BUILD_SHARED_LIBS gesteuert (Default: ON). Mit OFF entstehen statisch
# gelinkte Binaries, die keine libggml*.so im Laufzeit-Image benoetigen.
WORKDIR /sdcpp/ggml
RUN HASH=$(cat scripts/sync-llama.last) && \
    git clone https://github.com/ggml-org/llama.cpp.git llama-rpc && \
    cd llama-rpc && git checkout $HASH && \
    mkdir build && cd build && \
    cmake .. -DGGML_RPC=ON -DGGML_VULKAN=${WITH_VULKAN} -DBUILD_SHARED_LIBS=OFF -DLLAMA_CURL=OFF \
             -DCMAKE_C_FLAGS=-DGGML_MAX_NAME=160 -DCMAKE_CXX_FLAGS=-DGGML_MAX_NAME=160 && \
    cmake --build . --config Release -j $(nproc) && \
    RPC_BIN=$(find . -type f \( -name "ggml-rpc-server" -o -name "rpc-server" \) -executable | head -n1) && \
    echo "RPC-Binary: $RPC_BIN" && test -n "$RPC_BIN" && \
    cp "$RPC_BIN" /rpc-server-binary

# ---------------------------------------------------------------------------
# LLM-Server (llama-server) inklusive aller aktuellen Modell-Architekturen
# ---------------------------------------------------------------------------
# llama.cpp kennt keine Build-Option "Architektur X aktivieren": Alle
# unterstuetzten Architekturen sind fest im Quellcode enthalten. Ein Modell
# laedt nur, wenn der verwendete Commit die Architektur bereits kennt.
# Der Pin aus sync-llama.last (47f5a64, 15.10.2026) ist aelter als LFM3
# (in llama.cpp seit 27.10.2026, Commit 19cce691), daher der separate Build.
#
# Der Commit unten ist der letzte master-Stand mit RPC-Protokoll 8
# (9f0d80cf, 09.11.2026). Damit funktioniert --rpc weiterhin mit dem oben
# gepinnten rpc-server (Protokoll 8.0.0). Spaetere master-Staende sprechen
# Protokoll 9 und koennen den Cluster-Worker nicht mehr nutzen.
#
# Aktualisieren: ARG LLAMA_SERVER_REF auf einen neueren Commit setzen, der
#   a) die gewuenschten Architekturen enthaelt und
#   b) dieselbe RPC-Hauptversion hat (ggml/include/ggml-rpc.h,
#      RPC_PROTO_MAJOR_VERSION).
# Ein leerer Wert baut wieder exakt den Pin aus sync-llama.last.
RUN REF=${LLAMA_SERVER_REF:-$(cat /sdcpp/ggml/scripts/sync-llama.last)} && \
    git clone https://github.com/ggml-org/llama.cpp.git /llama-server-src && \
    cd /llama-server-src && git checkout $REF && \
    mkdir build && cd build && \
    cmake .. -DGGML_RPC=ON -DGGML_VULKAN=${WITH_VULKAN} -DBUILD_SHARED_LIBS=OFF -DLLAMA_CURL=OFF \
             -DCMAKE_C_FLAGS=-DGGML_MAX_NAME=160 -DCMAKE_CXX_FLAGS=-DGGML_MAX_NAME=160 && \
    cmake --build . --config Release -j $(nproc) && \
    LLAMA_BIN=$(find . -type f -name "llama-server" -executable | head -n1) && \
    echo "LLama-Binary: $LLAMA_BIN (Ref: $REF)" && test -n "$LLAMA_BIN" && \
    cp "$LLAMA_BIN" /llama-server-binary

# Sicherstellen, dass Binaries existieren und keine ggml-Shared-Library
# benoetigen. Der Check schlaegt fehl, falls BUILD_SHARED_LIBS versehentlich
# wieder aktiviert wird und die finale Stage die .so-Dateien nicht enthaelt.
RUN test -f /sd-server-binary && test -f /rpc-server-binary && test -f /llama-server-binary && \
    for bin in /rpc-server-binary /llama-server-binary; do \
      if ldd "$bin" | grep -q 'libggml'; then \
        echo "FEHLER: $bin benoetigt eine ggml-Shared-Library:"; \
        ldd "$bin" | grep 'libggml'; \
        exit 1; \
      fi; \
    done

# Stage 2: Final
FROM debian:trixie-slim

ARG DEBIAN_FRONTEND=noninteractive
# Optionale Mesa-Vulkan-Treiber (AMD/Intel sowie Software-lavapipe).
# Standardmaessig aus, weil mesa-vulkan-drivers libllvm19 (~125 MB) und weitere
# Treiberbibliotheken mitzieht (zusammen rund 250 MB).
# Fuer AMD/Intel-GPUs: --build-arg INSTALL_MESA_VULKAN=true
# NVIDIA nutzt stattdessen das nvidia-container-toolkit (siehe README).
ARG INSTALL_MESA_VULKAN=false

RUN apt-get update && apt-get install -y --no-install-recommends \
      libwebp7 \
      libgomp1 \
      libvulkan1 \
    && if [ "$INSTALL_MESA_VULKAN" = "true" ]; then \
         apt-get install -y --no-install-recommends mesa-vulkan-drivers; \
       fi \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

WORKDIR /app
COPY --from=builder /sd-server-binary ./sd-server
COPY --from=builder /rpc-server-binary ./rpc-server
COPY --from=builder /llama-server-binary ./llama-server
COPY entrypoint.sh .
RUN chmod +x entrypoint.sh

# Nur fuer NVIDIA-Hosts relevant: Das nvidia-container-toolkit soll neben
# compute/utility auch die Grafik-Bibliotheken (Vulkan-ICD) einhaengen.
# Auf allen anderen Hosts bleibt die Variable wirkungslos.
ENV NVIDIA_DRIVER_CAPABILITIES=all

VOLUME /models
EXPOSE 8080 8081 50052
ENTRYPOINT ["./entrypoint.sh"]
