# sigdb-fixtures

Each `*.json` is a signature database in a shape `anchorcheck` must handle (`EXPECTED`: the exit code it must give). Most are
hostile or broken on purpose and do not depend on Steam.

**Two are cut from the installed Steam client and go stale when Steam updates:**
- `all_deprecated.json`: the recorded addresses of a database that describes the running client, every signature deprecated
  (`anchorcheck` must exit 1). Its `func_addr_this_build` values are the current build's (`steam/signatures/macos.arm64/<build>.json`).
- `vtable_va_real.json`: a `vtable_slot` anchor with the real virtual address of the slot that holds `CCompatManager::Init`
  (`anchorcheck` must exit 0). `aob_hex` and `func_addr_this_build` are the current build's.

When the installed Steam is a new build and `make sigdb-fixtures` reports these two:
1. cut the build's database: `out/sigslice steam/signatures/macos.arm64/<newest>.json <build> steam/signatures/macos.arm64/<build>.json`
   and accept it with `out/anchorcheck steam/signatures/macos.arm64/<build>.json` (exit 0), add it to `steam/signatures/manifest.json`;
2. copy the 8 `func_addr_this_build` values of `all_deprecated.json` from that database, by name;
3. `vtable_va_real.json`: the slot is the one data word (in `__DATA_CONST`) holding the loaded client's address of `CCompatManager::Init`
   (unslid); take `aob_hex` and `func_addr_this_build` from the database.
