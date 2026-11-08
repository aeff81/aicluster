# Stage 1: Build
FROM debian:trixie-slim AS builder

ARG DEBIAN_FRONTEND=noninteractive

# Vulkan kann beim Build abgeschaltet werden (--build-arg WITH_VULKAN=OFF).
# Standard ist ON, damit GPU-Beschleunigung ohne CPU-Zwang verfügbar ist.
ARG WITH_VULKAN=ON

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

# RPC/LLama Server bauen
WORKDIR /sdcpp/ggml
# Die Hash-Version fuer Kompatibilitaet verwenden.
# Wichtig: Ein Schalter GGML_BUILD_SHARED_LIBS existiert in llama.cpp/ggml
# nicht. Die Bibliotheken werden ueber das Standard-CMake-Schalter
# BUILD_SHARED_LIBS gesteuert (Default: ON). Mit OFF entstehen statisch
# gelinkte Binaries, die keine libggml*.so im Laufzeit-Image benoetigen.
RUN HASH=$(cat scripts/sync-llama.last) && \
    git clone https://github.com/ggml-org/llama.cpp.git && \
    cd llama.cpp && git checkout $HASH && \
    mkdir build && cd build && \
    cmake .. -DGGML_RPC=ON -DGGML_VULKAN=${WITH_VULKAN} -DBUILD_SHARED_LIBS=OFF -DLLAMA_CURL=OFF \
             -DCMAKE_C_FLAGS=-DGGML_MAX_NAME=160 -DCMAKE_CXX_FLAGS=-DGGML_MAX_NAME=160 && \
    cmake --build . --config Release -j $(nproc) && \
    RPC_BIN=$(find . -type f \( -name "ggml-rpc-server" -o -name "rpc-server" \) -executable | head -n1) && \
    LLAMA_BIN=$(find . -type f -name "llama-server" -executable | head -n1) && \
    echo "RPC-Binary: $RPC_BIN" && echo "LLama-Binary: $LLAMA_BIN" && \
    test -n "$RPC_BIN" && test -n "$LLAMA_BIN" && \
    cp "$RPC_BIN" /rpc-server-binary && \
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
