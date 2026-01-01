# Bomberman Zig

A classic Bomberman-style arena game built in the Zig programming language. This project is a demonstration of creating a lightweight, performant, and entirely self-contained game using modern, low-level programming.

![Bomber Man Zig Gameplay Screenshot](resources/bmz.png)

## 🚀 Overview

This project is a single-pc-multiplayer "last-man-standing" game where players navigate a grid, place bombs, and use power-ups to defeat their opponents. The game is built with a focus on performance and simplicity, leveraging the power of Zig for a minimal footprint and direct control over system resources.

## ✨ Features

*   **Local Multiplayer:** Supports 2 to 4 players on a single machine.
*   **Dynamic Arena:** The game map is procedurally generated with destructible barrels.
*   **Power-ups:** Destroy barrels to uncover upgrades for your character.
*   **Rebindable Controls:** A settings menu allows players to customize their keybindings and team colors.
*   **Highly Optimized:** The game is lightweight with low resource consumption.

## 💻 Performance & Technical Details

One of the primary goals of this project was to create a game with a small footprint, showcasing the efficiency of Zig and careful resource management.

*   **Executable Size:** The entire game is a single executable file under **2 MB**.
*   **Resource Consumption:**
    *   **CPU:** ~2% on an AMD Ryzen 5 3600 6-Core processor.
    *   **GPU:** < 2% on an NVIDIA GeForce GTX 1660 Ti.
    *   **RAM:** < 50 MB.
*   **Memory Management:** The project features no dynamic memory allocations (on the Zig side) and avoids global mutable variables, contributing to its stability and predictable performance.
*   **Technology Stack:**
    *   **Language:** [Zig](https://ziglang.org/) (a modern, high-performance systems programming language).
    *   **Graphics:** [raylib](https://www.raylib.com/) (a simple and easy-to-use library for game programming).
    *   **Physics:** [Box2D](https://box2d.org/) (a 2D rigid body simulation library).
    *   **Build System:** Built entirely with Zig's integrated build system.

## 🎮 Gameplay

### Objective

The goal is simple: be the last Bomberman standing. Eliminate your opponents by strategically placing bombs and using the environment to your advantage.

### Rules

1.  **Placing Bombs:** Press your assigned key to drop a dynamite bomb. The bomb will explode after a few seconds.
2.  **Explosions:** Explosions travel in a cross pattern (up, down, left, right) from the bomb's location.
3.  **Destruction:** Explosions will destroy any barrels in their path and eliminate any player they touch.
4.  **Winning:** The last player alive at the end of the round wins.

### Power-ups

Destroying barrels may reveal a random power-up. Walk over an item to collect it and gain an advantage!

| Icon | Power-up | Description |
| :--: | :--- | :--- |
| ❤️ | **Heal** | Restores one point of health. |
| 💣 | **Extra Dynamite**| Increases the number of bombs you can place at one time. |
| 🔥 | **Radius Upgrade**| Increases the explosion radius of your bombs by one tile. |
| 💨 | **Speed Up** | Increases your character's movement speed. |
| 🌀 | **Teleport Upgrade**| Unlocks the ability to teleport. |

## ⌨️ Controls

The game supports up to four players with default keyboard layouts. All keys are rebindable in the **Settings** menu.

### Default Controls

| Player | Up | Down | Left | Right | Place Dynamite |
| :--- | :--: | :--: | :--: | :--: | :---: |
| **Player 1** | `W` | `S` | `A` | `D` | `Space` |
| **Player 2** | `Up` | `Down` | `Left` | `Right`| `Enter` |
| **Player 3** | `T` | `G` | `F` | `H` | `Y` |
| **Player 4** | `I` | `K` | `J` | `L` | `O` |

### Special Moves

*   **Teleport:** Quickly double-tap a movement key to instantly teleport two grid spaces in that direction. This is a great way to escape danger or surprise an opponent. The teleport ability starts with a cooldown of 5 seconds. Each "Teleport Upgrade" power-up collected reduces this cooldown by 0.5 seconds, down to a minimum of 2 seconds.
