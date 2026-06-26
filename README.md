PhysicsRoyale
=======================

A Godot 4.6 technical demo: walk on a procedurally generated spherical planet and paint terrain in real time. Terrain is pure GDScript (density field + Flying Edges mesher + chunked rebuilds) with no Voxel Tools dependency.

**Play in browser:** https://jamesfoti.github.io/PhysicsRoyale/

Features
-----------

- Spherical procedural terrain with noise, ravines, and caves
- Chunked mesh generation with threaded rebuilds on desktop
- Hold-to-paint terrain editing (destroy / add modes)
- Godot Plush third-person character with orbit camera
- Debug HUD (FPS, position, edit mode)
- Pause menu with controls reference
- Web export for GitHub Pages and itch.io

Note: This is a demo project. Gameplay is minimal by design; the focus is terrain generation and editing. In-game controls are listed in the pause menu.

Requirements
--------------

- [Godot 4.6](https://godotengine.org/) (standard build; no custom modules)
- Desktop: Forward+ renderer (default)
- Web: GL Compatibility (configured automatically for web export)

Running locally
---------------

1. Open the project in Godot 4.6.
2. Run the main scene: `scenes/terrain_test.tscn`.

Performance
-------------

On desktop, terrain meshing runs on worker threads while you paint; expect ~60 FPS on a mid-range PC.

The web build is heavier: WASM download (~54 MB on first load), main-thread meshing, and lower FPS than native—especially while editing terrain.

Web export
--------------

- `builds/github/` — static site deployed to GitHub Pages
- `builds/itch/PhysicsRoyale-web.zip` — browser build for itch.io upload

**Rebuild (GitHub Pages + itch zip):**

```powershell
powershell -ExecutionPolicy Bypass -File tools/export_web.ps1
```

**Test locally:**

```powershell
powershell -ExecutionPolicy Bypass -File tools/export_web.ps1 -Serve
```

Then open http://127.0.0.1:8060/

**GitHub Pages:** Repo Settings → Pages → Source: **GitHub Actions** (workflow deploys `builds/github/` on push).

**itch.io:** Upload `builds/itch/PhysicsRoyale-web.zip` as an HTML project with “Played in browser” enabled.

To rebuild only the itch zip from an existing `builds/github/` build:

```powershell
powershell -ExecutionPolicy Bypass -File tools/package_itch.ps1
```

Credits
--------------

Textures from https://ambientcg.com/  
Sound effects partly from https://sonniss.com/gameaudiogdc  
Godot Plush character by [Tibo](https://gtibo.itch.io/godot-plush-character) (MIT; assets in `character/godot_plush/`)
