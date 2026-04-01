# TODO_ModName

> TODO: Short description of what this mod does.

## Features

- TODO: List features

## Installation

Install via [r2modman](https://thunderstore.io/c/hades-ii/) or manually place in your `ReturnOfModding/plugins` folder.

## Configuration

This mod can be configured in-game.
- **With H2 Modpack Core**: Press the designated hotkey (default: `F10`) to open the unified Modpack UI and toggle this mod or adjust its settings.
- **Standalone**: If you do not have the Core installed, this mod will provide its own standalone configuration menu in-game.

## Development

This module is part of the [H2 Modular Modpack](https://github.com/h2-modpack/h2-modular-modpack). Please read the main project documentation for information on architecture and conventions.

- **[Architecture](https://github.com/h2-modpack/h2-modular-modpack/blob/main/ARCHITECTURE.md)**: Framework, Lib, managed special-state model, hash pipeline, module contract.
- **[Framework CONTRIBUTING.md](https://github.com/h2-modpack/adamant-ModpackFramework/blob/main/CONTRIBUTING.md)**: Discovery system, UI rendering, theme contract.
- **[Lib CONTRIBUTING.md](https://github.com/h2-modpack/adamant-ModpackLib/blob/main/CONTRIBUTING.md)**: Public API reference and shared utilities.

### Local Setup

1. Clone this repo
2. Run `Setup/init_repo.bat` (Windows) or `Setup/init_repo.sh` (Linux) to configure git hooks and branch protection
3. Run `Setup/deploy_local.bat` (Windows, as admin) or `Setup/deploy_local.sh` (Linux) to copy assets, generate manifest, and symlink into your r2modman profile

## How this fits into the modpack

This mod is designed to work standalone **or** as part of the [H2 Modpack](https://github.com/h2-modpack/h2-modular-modpack), which provides a unified UI, config hashing, and profile management across all modules via the Framework.

> **Discovery is automatic** - no registration needed. Set `modpack = PACK_ID` in `public.definition` and the Framework will discover this mod at runtime. Add this repo as a submodule under `Submodules/` in the shell repo and run `python Setup/deploy_all.py`.

## Special modules - how managed state works

> This section only applies if you're building a **special module** (`src/main_special.lua`). Simple modules can ignore this.

Special modules have custom state beyond a simple on/off toggle, things like weapon selections, aspect choices, or multi-field configurations. ImGui renders every frame and reads values constantly, but writing to Chalk (the config persistence layer) on every frame is expensive.

The solution is `public.store.specialState`, a managed state object created by Lib:

```lua
public.store = lib.createStore(config, public.definition.stateSchema)
```

`specialState` owns a private staging table and exposes:
- `specialState.view`
- `specialState.get(path)`
- `specialState.set(path, value)`
- `specialState.update(path, fn)`
- `specialState.toggle(path)`
- `specialState.reloadFromConfig()`
- `specialState.flushToConfig()`
- `specialState.isDirty()`

The lifecycle works like this:
- During draw, read schema-backed values from `specialState.view`.
- During draw, mutate schema-backed values only through `specialState.set/update/toggle`.
- In hosted mode, Framework flushes once after `DrawTab` / `DrawQuickContent` if `specialState.isDirty()` is true.
- In standalone mode, your module flushes after draw if `specialState.isDirty()` is true.
- After profile or hash import, Framework calls `specialState.reloadFromConfig()`.

Do not write `config` directly for schema-backed fields inside `DrawTab` or `DrawQuickContent`.

In practice: read from `specialState.view`, mutate through `public.store.specialState`, declare your fields in `stateSchema`, and let Framework or your standalone window own the flush boundary. The template's `FILL` markers show exactly where each piece goes.
