# 3D Billiards for macOS: Swift and Metal

[![GitHub Sponsors](https://img.shields.io/github/sponsors/makarov-mm?style=flat&logo=github)](https://github.com/sponsors/makarov-mm)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![Metal](https://img.shields.io/badge/Metal-8E8E93?logo=apple&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-0A66C2?logo=linkedin&logoColor=white)](https://www.linkedin.com/in/makarov-mm/)
[![Threads](https://img.shields.io/badge/Threads-000000?logo=threads&logoColor=white)](https://www.threads.net/@m.m.makarov)
[![Instagram](https://img.shields.io/badge/Instagram-E4405F?logo=instagram&logoColor=white)](https://www.instagram.com/m.m.makarov/)

A 3D billiards game for macOS written in Swift on Metal and AppKit: eight-ball and nine-ball on a pool table, and the Russian game «Американка» (free pyramid) on a pyramid table.

There is no game engine and no model, texture or sound file: the table, the cushions, the pockets, the balls and the cue are built in code at startup, the cloth, wood, stone and leather are procedural, the lighting environment is baked on the GPU, and the sounds are synthesized. The only frameworks are the ones macOS has: AppKit for the window and the input, Metal and MetalKit for the graphics, Core Text for the text and AVFoundation for the sound. There are no package dependencies.

This is a port of the Windows version written in C++23 on Win32 and OpenGL 4.6. The physics, the rules, the computer player, the aim lines, the scene and the animation follow it exactly, and its GLSL shaders are rewritten in the Metal Shading Language.

![Screenshot](screenshot.png)

![Themes](themes.png)

## Features

### Games

- **Eight-ball** on a 9-foot pool table: the first ball potted after the break gives the shooter a group, solids or stripes; with the group cleared the 8 goes into the pocket called; the 8 potted early or on a foul loses
- **Nine-ball**: the lowest ball on the table must be hit first, and the 9 potted on any fair shot wins
- **«Американка»** (free pyramid) on a 12-foot Russian table with sixteen ivory balls and pockets barely wider than a ball: after the break any ball may be struck at any other, every ball potted on a fair shot counts, the struck one too, and eight balls win; a foul gives one of the offender's balls back to the table
- Fouls: the cue ball pocketed, no ball hit, the wrong ball hit first, no ball reaching a cushion after the contact. Ball in hand behind the head string after a scratch on the break, anywhere after the other fouls
- Practice: one player, no fouls, the cue ball back in hand when it drops

### Physics

- The balls slide and roll on the cloth: where the cue strikes gives follow, draw and side spin, sliding turns into rolling by friction, and spin about the vertical dies away
- Collisions between balls with throw from the friction between them, cushions struck above the ball's middle so that spin bends the rebound, rounded jaws, and pockets with real mouths and facings, the Russian ones much tighter
- An event-driven simulation in double precision: every collision is found at its exact time, so fast balls never pass through each other or a cushion

### Play

- A computer opponent with five levels, from Novice to Master. For each ball it may strike, each ball it may pot and each pocket it finds the line through the ghost ball and keeps the clear ones; it plays the best of them out on a copy of the table with several speeds and spins, to see where the balls stop and how easy its next shot will be; it tests its choice against its own unsteadiness, and plays safe, or kicks off a cushion, when nothing is likely to go in. Lower levels look at fewer shots and strike less accurately. It thinks on a thread of its own, then shows its aim before the stroke
- Play against the computer, two players on one Mac, practice, or watch a demo game
- Aim lines worked out by the physics itself: the path of the struck ball to the first ball it meets, the ghost ball, where the ball hit goes and where the cue ball follows. Full, short or off
- Each turn starts aimed at the easiest pot. The aim then follows the mouse; press and pull back to strike, the farther the harder; Shift for fine aim. Or from the keyboard: arrows to turn the aim and set the power, Space to strike
- Spin set by dragging on the ball in the panel, or with `W` `A` `S` `D`; the power with a bar
- Ball in hand by dragging the cue ball; in «Американка» a click picks the ball to strike; the pocket for the 8 is chosen from the aim, or with a click on it
- Undo a shot, the history of the game, and the game in progress and the settings kept between sessions
- Three views: an overview, behind the ball along the aim, and from above. The camera also turns with the right mouse button and zooms with the wheel, two fingers or a pinch
- English and Russian interface and menus, chosen from the system language
- Sounds mixed as they play, so a break is heard ball by ball, each where it happens, from left to right
- Full screen, and sharp on Retina displays: the interface and the text follow the scale of the screen the window is on
- Shortcuts work in any keyboard layout: by their letters in Latin layouts, by their places in others, such as the Russian one
- No work while nothing moves: the view stops drawing until something changes, and while the window is out of sight

### Graphics

- Physically based shading: GGX highlights, a clear coat on the balls and the rails, image-based lighting from a procedural room with a lamp over the table
- Soft shadows (PCSS) and the shade of the balls on the cloth
- HDR rendering with 4x MSAA, bloom, ACES tone mapping and vignette
- Pool balls with stripes and numbered circles, the ivory Russian set with an amber cue ball; the numbers come from an atlas drawn with Core Text at startup
- The pocket holes in the cloth and the rails are cut by the shaders with alpha to coverage, so their edges stay smooth; leather drop pockets on the pool table, nets on the Russian one
- Animation: the stroke of the cue, the balls dropping into the pockets and lying there in a heap, balls set back on the table fading in, the rack set out ball by ball
- Four themes: Classic (green cloth and mahogany), Tournament (blue cloth, black lacquer and chrome), Club (wine-red cloth, walnut and a stone floor) and Night (teal cloth and glowing sights)
- An interface of frosted-glass panels

## Controls

| Action | Control |
|---|---|
| Aim at a point | Move the mouse |
| Fine aim | `Shift` + mouse |
| Strike: the farther, the harder | Press and pull back, release; a right click takes the stroke back |
| Pick the ball to strike («Американка»); call the pocket for the 8 | Click the ball / the pocket |
| Place a ball in hand | Drag the cue ball |
| Turn the view | Drag with the right mouse button (a secondary click and drag on a trackpad) |
| Zoom | Scroll, or pinch on a trackpad |
| Strike with the power set | `Space` |
| Power | `↑` / `↓` (`Shift` finer) |
| Turn the aim | `←` / `→` (`Shift` finer) |
| Spin: where the cue strikes | `W` `A` `S` `D`; `X` the middle |
| Next view | `C` (`⇧C` back); `Home` resets it |
| Aim lines: full, short, off | `G` |
| Undo the shot | `⌘Z`, `Delete` |
| New game | `N`, `⌘N` |
| Next game | `B` (`⇧B` back) |
| Who plays | `M` (`⇧M` back) |
| Computer level | `1` … `5` |
| Next theme | `T` (`⇧T` back) |
| Sound on / off | `V` |
| English / Russian | `L` |
| Show / hide the panel | `Tab` |
| Full screen | `⌃⌘F`, `F11`, `⌥Return` |
| Help | `F1`, `⌘?` |
| Leave full screen | `Esc` |

A new game starts at once when the game is changed, or when practice is turned on or off. The Control key works in place of Command in the shortcuts of the game, as Ctrl does on Windows.

## Requirements

- macOS 13 Ventura or newer, on Apple silicon or Intel
- Xcode 16 or newer, or its Command Line Tools: Swift 6 is needed to build

## Building and running

In the project's folder:

```sh
./build.sh          # builds build/3D Billiards.app
./build.sh run      # builds it and starts it
./build.sh clean    # removes the build output
```

The application is signed ad hoc, for the Mac it was built on; drag it to the Applications folder to keep it.

For a quick start without the application bundle:

```sh
swift run -c release
```

The settings and the game in progress are kept in the user defaults (`defaults read com.makarovmm.billiards3d`).

## Project structure

```text
.
├── Package.swift                the Swift package: one executable, the shaders and the icon as resources
├── build.sh                     builds and signs the application bundle
└── Sources/Billiards3D/
    ├── App/                     the application: the window, the menus, the view, the game flow, input and interface
    ├── Physics/                 the balls on the table: sliding, rolling, spin, collisions, cushions, jaws and pockets
    ├── Rules/                   the racks, fouls, turns and ends of eight-ball, nine-ball and «Американка», saved games
    ├── Computer/                the computer player and the thread it thinks on
    ├── Prediction/              the aim lines, played out by the physics
    ├── Scene/                   meshes of the table, the pockets, the balls and the cue, the balls as drawn, the camera,
    │                            the themes
    ├── Rendering/               the rendering pipeline: render targets, light probes, uniforms and the passes
    ├── Interface/               font atlases and the balls' numbers drawn with Core Text, drawing of the interface
    ├── Support/                 the settings, the texts in English and Russian, synthesized sounds and their mixer,
    │                            the random numbers, the resources
    └── Resources/
        ├── Shaders/             Metal shaders, compiled when the game starts
        └── billiards3d.png      the icon
```

## How a frame is drawn

1. **Shadow map**: the cushions, the rails, the frame, the cue and the balls seen from the lamp's key light, for soft shadows; the balls in one instanced draw.
2. **Main pass**: the floor, the frame, the cushions, the pockets, the rails and the cloth in HDR with 4x MSAA, lit by the key light and the baked environment. The holes of the pockets are cut in the cloth and the rails by their shader; the spots, the head string, the aim lines and the ring round the pocket called are drawn on the cloth by it too, filtered over each pixel. The balls follow in one instanced draw, then the cue, the room behind, and the see-through ghost ball last.
3. **Post-processing**: the samples are resolved, bright parts spread into a six-level bloom, and the composite pass applies tone mapping and vignetting and frosts the glass behind the interface panels.
4. **Interface**: panels, text and icons, drawn on top.

The environment maps are baked with compute kernels when the theme changes, and the BRDF table once at startup.

## License

MIT License

Copyright (c) 2026 Mykhailo Makarov

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Support

If you found this project interesting or useful, you can support my work:

[![GitHub Sponsors](https://img.shields.io/github/sponsors/makarov-mm?style=flat&logo=github)](https://github.com/sponsors/makarov-mm)
