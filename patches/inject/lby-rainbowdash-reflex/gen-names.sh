#!/bin/sh
# Regenerates nvapi_names.h from NVIDIA's nvapi_interface.h (https://github.com/NVIDIA/nvapi, MIT).
# Usage: patches/inject/lby-rainbowdash-reflex/gen-names.sh path/to/nvapi_interface.h > patches/inject/lby-rainbowdash-reflex/nvapi_names.h
set -eu
cat <<'HDR'
/* NVAPI function names by interface id, for the log: generated from NVIDIA's
 * nvapi_interface.h (https://github.com/NVIDIA/nvapi, MIT, Copyright (c) 2024
 * NVIDIA CORPORATION & AFFILIATES) by patches/inject/lby-rainbowdash-reflex/gen-names.sh. Do not edit. */
static const struct nvapi_name { unsigned int id; const char *name; } nvapi_names[] = {
HDR
sed -nE 's/^[[:space:]]*\{ *"(NvAPI_[A-Za-z0-9_]+)", *(0x[0-9a-fA-F]+) *\},?.*/    { \2, "\1" },/p' "${1:?nvapi_interface.h}"
echo "};"
