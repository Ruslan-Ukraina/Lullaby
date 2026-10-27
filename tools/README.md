# tools
Developer tools: `perf/` benchmark stand, data importers, local builders. Personal or machine-specific scripts do not belong here.

- `build-kosmickrisp-local.sh`: builds Mesa's KosmicKrisp (Vulkan on Metal 4) for x86_64, the architecture of Dormison's Wine (the LunarG SDK's own build is arm64 only). Stock Mesa at a pinned tag, nothing installed; needs the Homebrew packages and the Python environment named at the top of the script. Result: `libvulkan_kosmickrisp.dylib` and `kosmickrisp_icd.json`. Run script: `LULLABY_VULKAN=kosmickrisp` uses them from `lullaby/components/kosmickrisp/`.
