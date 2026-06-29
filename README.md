PhysicsRoyale
=======================

A Godot 4.6 technical demo: walk on a procedurally generated spherical planet and paint terrain in real time. Terrain is pure GDScript (density field + Flying Edges mesher + chunked rebuilds) with no Voxel Tools dependency.

**Target platforms:** Desktop and console-style builds. This is the supported experience.

## Table of contents

- [Features](#features)
- [Requirements](#requirements)
- [Running locally](#running-locally)
- [Performance](#performance)
- [Web export (experimental)](#web-export-experimental)
- [Credits](#credits)

Features
-----------

- Spherical procedural terrain with noise, ravines, and caves
- Procedural grass, dirt, rock, and polar snow coloring (shader-based)
- Chunked mesh generation with threaded rebuilds on desktop
- Hold-to-paint terrain editing (destroy / add modes)
- Procedural asteroids that impact planets and carve craters
- Godot Plush third-person character with orbit camera, torch, and pickaxe
- Debug HUD (FPS, position, edit mode)
- Pause menu with controls reference

Note: This is a demo project. Gameplay is minimal by design; the focus is terrain generation and editing. In-game controls are listed in the pause menu.

Requirements
--------------

- [Godot 4.6](https://godotengine.org/) (standard build; no custom modules)
- Desktop: Forward+ renderer (default)

Running locally
---------------

1. Open the project in Godot 4.6.
2. Run the main scene: `scenes/terrain_test.tscn`.

Performance
-------------

On desktop, terrain meshing runs on worker threads while you paint; expect ~60 FPS on a mid-range PC.

Web export (experimental)
---------------------------

Web and GitHub Pages builds are **not** maintained to the same standard as desktop. Shaders, threading, input, and rendering may differ or break in the browser. The game is intended for desktop and console distribution only.

If you still want to try a browser build:

- `builds/github/` — static site for GitHub Pages (may be outdated or broken)
- `builds/itch/PhysicsRoyale-web.zip` — browser build for itch.io upload

```powershell
powershell -ExecutionPolicy Bypass -File tools/export_web.ps1
```

GitHub Pages workflow (`.github/workflows/deploy-pages.yml`) may still run on push, but there is no guarantee the result matches the desktop game.

Credits
--------------

Textures from https://ambientcg.com/  
Sound effects partly from https://sonniss.com/gameaudiogdc  
Godot Plush character by [Tibo](https://gtibo.itch.io/godot-plush-character) (MIT; assets in `character/godot_plush/`)
