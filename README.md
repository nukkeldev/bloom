# Bloom

An app framework for quickly creating cross-platform applications.
Abstracts much of the creation but you may source many of the components yourself (e.g. windows, devices, etc.) 

Uses [castholm](https://github.com/castholm)'s zig port of [SDL3](https://github.com/libsdl-org/SDL), more specifically it's GPU functionality, as it's windowing and rendering backend.
ImGui (+ friends) are provided by [zgui](https://github.com/zig-gamedev/zgui).
All dependencies are re-exported in `root.zig` for usage.

Built for `zig 0.14.1`, does not currently work on `master` due to dependencies using now finalized deprecations in their build scripts.

## Installation

1. Install via `zig fetch`
2. Import the `bloom` module

## Usage

See `example/` for a simple usage example.