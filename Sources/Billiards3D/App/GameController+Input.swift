import AppKit
import simd

/// The mouse and the keys: the view hands the events over, the frame acts on them.
extension GameController {
    enum PointerButton {
        case left, right
    }

    // MARK: - Pointer events

    func pointerMoved(x: Float, y: Float) {
        pointer.x = x
        pointer.y = y
        requestFrame()
    }

    func pointerButton(_ button: PointerButton, down: Bool, x: Float, y: Float) {
        pointerMoved(x: x, y: y)
        switch button {
        case .left:
            pointer.leftDown = down
            if down {
                pointer.leftPressed = true
            } else {
                pointer.leftReleased = true
            }
        case .right:
            pointer.rightDown = down
            if down {
                pointer.rightPressed = true
            } else {
                pointer.rightReleased = true
            }
        }
    }

    /// The pointer left the view: nothing stays highlighted under it, unless a button is held.
    func pointerLeft() {
        if !pointer.leftDown && !pointer.rightDown {
            pointer.x = -1
            pointer.y = -1
        }
        requestFrame()
    }

    /// The window lost the keyboard: a button let go of in another window is not heard here.
    func releaseButtons() {
        if pointer.leftDown {
            pointer.leftReleased = true
        }
        if pointer.rightDown {
            pointer.rightReleased = true
        }
        pointer.leftDown = false
        pointer.rightDown = false
        requestFrame()
    }

    /// Scrolling by a wheel or a trackpad, in notches as the content moves; `invertedByDevice` when the system turns
    /// the direction round ("natural" scrolling), which the zoom undoes, so that a push away zooms in either way.
    func scrolled(_ steps: Float, invertedByDevice: Bool) {
        pointer.scroll += steps
        pointer.zoom += invertedByDevice ? -steps : steps
        requestFrame()
    }

    /// A pinch on a trackpad, in notches of the wheel.
    func zoomed(_ steps: Float) {
        pointer.zoom += steps
        requestFrame()
    }

    // MARK: - The table under the pointer

    private func pointerRay() -> (origin: SIMD3<Float>, direction: SIMD3<Float>)? {
        if pointer.x < 0 || pointer.y < 0 {
            return nil
        }
        return camera.ray(x: pointer.x, y: pointer.y, width: Float(width), height: Float(height))
    }

    /// Where the ray through the pointer meets the level `height` above the cloth.
    private func pointerOnPlane(_ height: Float) -> V2? {
        guard let ray = pointerRay(), ray.direction.y <= -1e-4 else { return nil }
        let t = (height - ray.origin.y) / ray.direction.y
        if t < 0 {
            return nil
        }
        let p = ray.origin + ray.direction * t
        return V2(Double(p.x), Double(p.z))
    }

    private func ballUnderPointer() -> Int {
        guard let ray = pointerRay() else { return -1 }
        let R = Float(table.ballRadius) * 1.3
        var nearest: Float = 1e9
        var found = -1
        for i in 0..<sim.count where sim.balls[i].onTable {
            let offset = ray.origin - tableView.position(sim, i)
            let b = dot(offset, ray.direction)
            let c = dot(offset, offset) - R * R
            let discriminant = b * b - c
            if discriminant < 0 {
                continue
            }
            let t = -b - discriminant.squareRoot()
            if t > 0 && t < nearest {
                nearest = t
                found = i
            }
        }
        return found
    }

    private func pocketUnderPointer() -> Int {
        guard let p = pointerOnPlane(0) else { return -1 }
        for (i, pocket) in table.pockets.enumerated() where (p - pocket.hole).length < pocket.cupRadius * 1.35 {
            return i
        }
        return -1
    }

    /// The ball in hand where the pointer wants it, or as near as it may go: on the cloth, clear of the other balls,
    /// and behind the head string when it must be.
    private func placeCueBall(_ wanted: V2) {
        let R = table.ballRadius
        var wanted = wanted
        if match.inHand == .kitchen {
            wanted.x = min(wanted.x, table.headString - 0.002)
        }
        wanted.x = min(max(wanted.x, -table.length / 2 + R), table.length / 2 - R)
        wanted.z = min(max(wanted.z, -table.width / 2 + R), table.width / 2 - R)
        if sim.isFreeSpot(wanted, except: 0) {
            sim.balls[0].p = wanted
        } else if sim.isFreeSpot(sim.balls[0].p, except: 0) {
            var good = sim.balls[0].p
            var bad = wanted
            for _ in 0..<16 {
                let middle = (good + bad) * 0.5
                if sim.isFreeSpot(middle, except: 0) {
                    good = middle
                } else {
                    bad = middle
                }
            }
            sim.balls[0].p = good
        }
        sim.balls[0].v = .zero
        sim.balls[0].w = .zero
        predictionDirty = true
    }

    func handleTablePointer() {
        let blocked = pointer.consumed || helpVisible
        let inside = pointer.x >= 0 && pointer.y >= 0 && pointer.x < Float(width) && pointer.y < Float(height)
        let aiming = isAiming
        let R = Float(table.ballRadius)

        // What is under the pointer: the ball in hand to pick up, a ball to strike with, a pocket to call.
        let lastBall = hoverBall
        let lastPocket = hoverPocket
        let looking = inside && !blocked && aiming && (gesture == .none || gesture == .strike)
        hoverBall = looking ? ballUnderPointer() : -1
        hoverPocket = looking && isOnEight ? pocketUnderPointer() : -1
        if hoverBall >= 0 && hoverPocket >= 0 {
            hoverPocket = -1
        }
        if hoverBall != lastBall || hoverPocket != lastPocket {
            dirty = true
        }
        let grabbable = aiming && match.inHand != .none && hoverBall == 0
        let pickable = aiming && game == .americanka && !match.breakShot && hoverBall >= 0 && hoverBall != struck
        if grabbable || pickable || hoverPocket >= 0 || gesture == .placeBall {
            cursorHand = true
        }

        if !blocked && pointer.leftPressed && gesture == .none {
            pressX = pointer.x
            dragX = pointer.x
            pressY = pointer.y
            dragY = pointer.y
            if grabbable {
                gesture = .placeBall
                grabOffset = pointerOnPlane(R).map { sim.balls[0].p - $0 } ?? .zero
            } else if aiming {
                gesture = .strike
                charge = 0
            } else {
                gesture = .turnCamera
            }
        }
        if !pointer.consumed && !helpVisible && pointer.rightPressed {
            if gesture == .strike {
                // A right click while drawing the cue back takes the stroke back.
                charge = 0
                gesture = .none
            }
            if gesture == .none {
                gesture = .turnCamera
                pressX = pointer.x
                dragX = pointer.x
                pressY = pointer.y
                dragY = pointer.y
            }
        }

        let travel = hypot(pointer.x - pressX, pointer.y - pressY)
        switch gesture {
        case .placeBall:
            if let p = pointerOnPlane(R) {
                placeCueBall(p + grabOffset)
            }
        case .strike:
            charge = min(max((travel - 4 * scale) / (Self.fullPull * scale), 0), 1)
        case .turnCamera:
            camera.rotate(yaw: -(pointer.x - dragX) * 0.0055 / scale, pitch: (pointer.y - dragY) * 0.0045 / scale)
            dragX = pointer.x
            dragY = pointer.y
        case .none:
            break
        }

        if pointer.leftReleased {
            if gesture == .strike {
                if travel < 5 * scale {
                    // A click: a ball to strike with, or the pocket for the eight.
                    if pickable && match.mayStrike(sim, hoverBall) {
                        struck = hoverBall
                        predictionDirty = true
                        followAim()
                        sound.play(.click)
                    } else if hoverPocket >= 0 {
                        calledFixed = !(calledFixed && called == hoverPocket)
                        called = hoverPocket
                        predictionDirty = true
                        sound.play(.click)
                    }
                } else if charge >= 0.03 {
                    power = charge
                    pull = CuePose.pull(for: charge)
                    shoot(makeShot(), backswing: false)
                }
                charge = 0
                if gesture == .strike {
                    gesture = .none
                }
            } else if gesture == .placeBall {
                gesture = .none
                followAim()
            } else if gesture == .turnCamera && !pointer.rightDown {
                gesture = .none
            }
        }
        if pointer.rightReleased && gesture == .turnCamera && !pointer.leftDown {
            gesture = .none
        }

        // With no button held the aim follows the pointer: to the point under it, or with Shift turned finely; but not
        // before the pointer has been moved in this turn.
        if turnX < 0 {
            turnX = pointer.x
            turnY = pointer.y
        }
        if hypot(pointer.x - turnX, pointer.y - turnY) > 3 * scale {
            pointerAims = true
        }
        let moved = pointer.x != aimX || pointer.y != aimY
        if isAiming && gesture == .none && !blocked && inside && moved && pointerAims {
            let ball = sim.balls[struck]
            if NSEvent.modifierFlags.contains(.shift) && aimX >= 0 {
                let center = tableView.position(sim, struck)
                let turned = aim.rotated(0.01)
                let w = Float(width)
                let h = Float(height)
                if let a = camera.toScreen(center + SIMD3(Float(aim.x), 0, Float(aim.z)) * 0.5, width: w, height: h),
                   let b = camera.toScreen(center + SIMD3(Float(turned.x), 0, Float(turned.z)) * 0.5, width: w, height: h) {
                    let tangent = b - a
                    let size = length(tangent)
                    if size > 1e-3 {
                        let along = dot(SIMD2(pointer.x - aimX, pointer.y - aimY), tangent * (1 / size))
                        aim = aim.rotated(Double(along * 0.0004 / scale)).normalized
                        predictionDirty = true
                    }
                }
            } else if let p = pointerOnPlane(R), (p - ball.p).length > 0.6 * Double(R) {
                aim = (p - ball.p).normalized
                predictionDirty = true
            }
        }
        aimX = pointer.x
        aimY = pointer.y

        if !pointer.consumed && !helpVisible && pointer.zoom != 0 {
            camera.zoom(pointer.zoom)
        }
    }

    // MARK: - Keys

    /// Acts on a key; false for the keys the game does not use, which the menus may take.
    @discardableResult
    func keyDown(_ key: KeyPress) -> Bool {
        requestFrame()
        if helpVisible {
            // Over the help only its own keys work, and full screen.
            if key.code == KeyPress.Code.escape || key.code == KeyPress.Code.f1 || key.code == KeyPress.Code.help {
                helpVisible = false
                return true
            }
            if key.code == KeyPress.Code.f11 {
                toggleFullScreen()
                return true
            }
            return !(key.command || key.control)
        }
        if key.command || key.control {
            switch key.letter {
            case "z":
                undo()
            case "n":
                newGame()
            default:
                return false
            }
            return true
        }

        let aiming = isAiming && gesture == .none
        switch key.code {
        case KeyPress.Code.space:
            if aiming {
                shoot(makeShot(), backswing: true)
            }
            return true
        case KeyPress.Code.upArrow:
            setPower(power + (key.shift ? 0.005 : 0.025))
            return true
        case KeyPress.Code.downArrow:
            setPower(power - (key.shift ? 0.005 : 0.025))
            return true
        case KeyPress.Code.leftArrow, KeyPress.Code.rightArrow:
            if aiming {
                turnAim((key.code == KeyPress.Code.rightArrow ? 1 : -1) * (key.shift ? 0.0004 : 0.005))
            }
            return true
        case KeyPress.Code.home:
            camera.reset()
            followAim()
            return true
        case KeyPress.Code.delete:
            undo()
            return true
        case KeyPress.Code.tab:
            panelVisible = !panelVisible
            save()
            return true
        case KeyPress.Code.f1, KeyPress.Code.help:
            helpVisible = !helpVisible
            return true
        case KeyPress.Code.f11:
            toggleFullScreen()
            return true
        case KeyPress.Code.returnKey where key.option:
            toggleFullScreen()
            return true
        case KeyPress.Code.escape:
            if gesture == .strike {
                gesture = .none
                charge = 0
            } else if isFullScreen {
                toggleFullScreen()
            }
            return true
        default:
            break
        }
        if let level = key.level {
            setLevel(level)
            return true
        }
        let step = key.shift ? -1 : 1
        switch key.letter {
        case "w": setSpin(side: side, vertical: vertical + 0.1)
        case "s": setSpin(side: side, vertical: vertical - 0.1)
        case "a": setSpin(side: side - 0.1, vertical: vertical)
        case "d": setSpin(side: side + 0.1, vertical: vertical)
        case "x": setSpin(side: 0, vertical: 0)
        case "c": setCamera(camera.mode.rawValue + step)
        case "g": setAimLines(aimLines.rawValue + step)
        case "n": newGame()
        case "b": setGame(game.rawValue + step)
        case "m": setMode(mode.rawValue + step)
        case "t": setTheme(themeIndex + step)
        case "v": toggleSound()
        case "l": toggleLanguage()
        default: return false
        }
        return true
    }
}
