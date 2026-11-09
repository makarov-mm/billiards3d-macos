import AppKit
import simd

/// The panel at the right: the status, the players, the stroke's power and spin, the shots so far, the buttons and
/// the choices.
extension GameController {
    /// The pool balls' colors, for the icons of the interface.
    private static let poolColors = [RGBA(248, 184, 22), RGBA(30, 72, 196), RGBA(214, 38, 36), RGBA(104, 48, 164), RGBA(246, 114, 26),
                                     RGBA(26, 134, 68), RGBA(136, 36, 32), RGBA(26, 26, 30)]

    var accent: RGBA { RGBA(linear: theme.accent) }

    var panelRect: ScreenRect {
        let width = Self.panelWidth * scale
        let margin = Self.panelMargin * scale
        return ScreenRect(x: Float(self.width) - (width + margin) * panelSlide, y: margin, width: width, height: Float(height) - 2 * margin)
    }

    /// The window left of the panel.
    var freeArea: ScreenRect {
        ScreenRect(x: 0, y: 0, width: min(panelRect.x, Float(width)), height: Float(height))
    }

    /// The rectangles of the interface behind which the scene is blurred.
    var frostedPanels: [FrostedPanel] {
        var panels: [FrostedPanel] = []
        if panelSlide > 0.001 {
            panels.append(FrostedPanel(rect: panelRect, radius: 18 * scale, opacity: 1))
        }
        if bannerFade > 0.001 {
            panels.append(FrostedPanel(rect: bannerCard, radius: 18 * scale, opacity: bannerFade))
        }
        if helpVisible {
            panels.append(FrostedPanel(rect: helpCard, radius: 20 * scale, opacity: 1))
        }
        return panels
    }

    func drawInterface() {
        drawPanel()
        drawBanner()
        drawToasts()
        if helpVisible {
            drawHelp()
        }
    }

    // MARK: - Widgets

    /// A button; true when it is clicked.
    @discardableResult
    func button(_ id: Int, _ rect: ScreenRect, _ label: String, enabled: Bool = true, accented: Bool = false) -> Bool {
        let interactive = enabled && (!helpVisible || id > Widget.modal)
        let hover = interactive && rect.contains(pointer.x, pointer.y) && gesture == .none
        if hover {
            cursorHand = true
        }
        if hover && pointer.leftPressed {
            activeWidget = id
            pointer.consumed = true
        }
        var clicked = false
        if pointer.leftReleased && activeWidget == id {
            clicked = hover
            activeWidget = 0
            pointer.consumed = true
        }
        let pressed = hover && activeWidget == id && pointer.leftDown
        var fill = !enabled ? RGBA(255, 255, 255, 7) : pressed ? RGBA(255, 255, 255, 52) : hover ? RGBA(255, 255, 255, 34) : RGBA(255, 255, 255, 17)
        if accented && enabled {
            fill = fill.mixed(with: RGBA(linear: theme.accent, alpha: Float(fill.a) / 255 * 2.2), 0.6)
        }
        painter.fill(rect, radius: 9 * scale, color: fill)
        painter.textCentered(.body, in: rect, label, color: enabled ? Self.textColor : Self.textColor.faded(0.35))
        if clicked {
            sound.play(.click)
        }
        return clicked
    }

    /// A label with a value stepped by two arrows; -1 or 1 when one is clicked, else 0.
    private func selector(_ id: Int, _ rect: ScreenRect, _ label: String, _ value: String) -> Int {
        painter.text(.body, x: rect.x, y: rect.y + (rect.height - painter.lineHeight(.body)) / 2, label, color: Self.mutedColor)
        let arrow = rect.height
        let right = ScreenRect(x: rect.right - arrow, y: rect.y, width: arrow, height: rect.height)
        let left = ScreenRect(x: rect.x + rect.width * 0.36, y: rect.y, width: arrow, height: rect.height)
        painter.fill(ScreenRect(x: left.right + 2 * scale, y: rect.y, width: right.x - left.right - 4 * scale, height: rect.height), radius: 9 * scale,
                     color: RGBA(255, 255, 255, 9))
        painter.textCentered(.body, in: ScreenRect(x: left.right, y: rect.y, width: right.x - left.right, height: rect.height), value,
                             color: Self.textColor)
        var change = 0
        if button(id, left, "") {
            change = -1
        }
        if button(id + 1, right, "") {
            change = 1
        }
        let size = 5 * scale
        painter.arrow(x: left.x + left.width / 2, y: left.y + left.height / 2, halfWidth: size * 0.8, halfHeight: size, direction: -1,
                      color: Self.textColor)
        painter.arrow(x: right.x + right.width / 2, y: right.y + right.height / 2, halfWidth: size * 0.8, halfHeight: size, direction: 1,
                      color: Self.textColor)
        return change
    }

    /// A ball as a small disc in its colors: stripes with a band, the numbered ones with a white spot.
    private func drawBallIcon(x: Float, y: Float, radius: Float, ball: Int) {
        let russian = table.kind == .pyramid
        let color = russian ? (ball == 0 ? RGBA(232, 176, 84) : RGBA(236, 228, 206))
            : ball == 0 ? RGBA(240, 238, 230) : Self.poolColors[(ball - 1) % 8]
        painter.disc(x: x, y: y + radius * 0.12, radius: radius * 1.08, color: RGBA(0, 0, 0, 70))
        if !russian && ball >= 9 {
            painter.disc(x: x, y: y, radius: radius, color: RGBA(240, 238, 230))
            painter.fill(ScreenRect(x: x - radius * 0.92, y: y - radius * 0.5, width: radius * 1.84, height: radius), radius: radius * 0.45, color: color)
        } else {
            painter.disc(x: x, y: y, radius: radius, color: color)
        }
        if ball > 0 && !russian {
            painter.disc(x: x, y: y, radius: radius * 0.38, color: RGBA(245, 244, 238))
        } else if ball > 0 {
            painter.disc(x: x, y: y, radius: radius * 0.22, color: RGBA(150, 40, 30))
        }
        painter.disc(x: x - radius * 0.35, y: y - radius * 0.4, radius: radius * 0.22, color: RGBA(255, 255, 255, 90))
    }

    // MARK: - The panel

    private func drawPanel() {
        guard panelSlide > 0.001 else { return }
        let panel = panelRect
        if panel.contains(pointer.x, pointer.y) && (pointer.leftPressed || pointer.rightPressed) && gesture == .none {
            pointer.consumed = true
        }
        painter.shadow(panel, blur: 22 * scale, color: RGBA(0, 0, 0, 70))
        painter.fill(panel, radius: 18 * scale, color: RGBA(16, 18, 26, 120))
        painter.outline(panel, radius: 18 * scale, color: RGBA(255, 255, 255, 24))

        // In a low window everything is packed closer, and the footer goes.
        let compact = panel.height < 820 * scale
        let pad = (compact ? 16 : 20) * scale
        let x = panel.x + pad
        let width = panel.width - 2 * pad
        var y = panel.y + pad

        painter.text(.heading, x: x, y: y, text(.title), color: Self.textColor)
        if button(Widget.help, ScreenRect(x: panel.right - pad - 30 * scale, y: y - 2 * scale, width: 30 * scale, height: 30 * scale), "?") {
            helpVisible = !helpVisible
        }
        y += (compact ? 38 : 44) * scale

        let statusHeight = (compact ? 54 : 62) * scale
        drawStatus(ScreenRect(x: x, y: y, width: width, height: statusHeight))
        y += statusHeight + (compact ? 8 : 12) * scale

        let players = match.practice ? 1 : 2
        let ballsRow = game == .nineBall || match.practice
        let playersHeight = (Float(players) * 30 + (ballsRow ? 28 : 0)) * scale
        drawPlayers(ScreenRect(x: x + 4 * scale, y: y, width: width - 8 * scale, height: playersHeight))
        y += playersHeight + (compact ? 8 : 12) * scale

        let strokeHeight = (compact ? 72 : 80) * scale
        drawStroke(ScreenRect(x: x, y: y, width: width, height: strokeHeight))
        y += strokeHeight + (compact ? 10 : 14) * scale

        // From the bottom up: the footer, the switches, the settings and the buttons; the shots take the space between.
        var bottom = panel.bottom - pad
        if !compact {
            let footerHeight = painter.lineHeight(.body)
            painter.textCentered(.body, in: ScreenRect(x: x, y: bottom - footerHeight, width: width, height: footerHeight), text(.footer),
                                 color: Self.mutedColor.faded(0.8))
            bottom -= footerHeight + 14 * scale
        }

        let rowHeight = (compact ? 29 : 34) * scale
        let gap = (compact ? 5 : 8) * scale
        let half = (width - gap) / 2
        bottom -= rowHeight
        if button(Widget.sound, ScreenRect(x: x, y: bottom, width: half, height: rowHeight), text(.sound), accented: sound.isEnabled) {
            toggleSound()
        }
        if button(Widget.language, ScreenRect(x: x + half + gap, y: bottom, width: half, height: rowHeight), text(.languageName)) {
            toggleLanguage()
        }
        bottom -= gap

        let modes: [Str] = [.modeComputer, .modeTwoPlayers, .modePractice, .modeDemo]
        let lines: [Str] = [.aimFull, .aimShort, .aimOff]
        let choices: [(id: Int, label: Str, value: String)] = [
            (Widget.theme, .theme, theme.name(language)),
            (Widget.aim, .aim, text(lines[aimLines.rawValue])),
            (Widget.level, .level, "\(level) · \(text(Str.levelName(level)))"),
            (Widget.mode, .mode, text(modes[mode.rawValue])),
            (Widget.game, .game, text(Self.gameName(game))),
        ]
        for choice in choices {
            bottom -= rowHeight
            let change = selector(choice.id, ScreenRect(x: x, y: bottom, width: width, height: rowHeight), text(choice.label), choice.value)
            if change != 0 {
                switch choice.id {
                case Widget.theme: setTheme(themeIndex + change)
                case Widget.aim: setAimLines(aimLines.rawValue + change)
                case Widget.level: setLevel(level + change)
                case Widget.mode: setMode(mode.rawValue + change)
                default: setGame(game.rawValue + change)
                }
            }
            bottom -= (compact ? 3 : 6) * scale
        }
        bottom -= (compact ? 4 : 8) * scale

        let buttonHeight = (compact ? 31 : 38) * scale
        bottom -= buttonHeight
        let cameras: [Str] = [.cameraOverview, .cameraBehind, .cameraTop]
        if button(Widget.camera, ScreenRect(x: x, y: bottom, width: width, height: buttonHeight),
                  "\(text(.camera)): \(text(cameras[camera.mode.rawValue]))") {
            setCamera(camera.mode.rawValue + 1)
        }
        bottom -= gap + buttonHeight
        if button(Widget.newGame, ScreenRect(x: x, y: bottom, width: half, height: buttonHeight), text(.newGame), accented: stage == .over) {
            newGame()
        }
        if button(Widget.undo, ScreenRect(x: x + half + gap, y: bottom, width: half, height: buttonHeight), text(.undoShot),
                  enabled: !undoStack.isEmpty && mode != .demo) {
            undo()
        }
        bottom -= (compact ? 10 : 14) * scale

        // The shots so far, where there is room for them.
        let labelHeight = painter.lineHeight(.body) + 6 * scale
        if bottom - y - labelHeight > 36 * scale {
            painter.text(.body, x: x, y: y, text(.history), color: Self.mutedColor)
            drawHistory(ScreenRect(x: x, y: y + labelHeight, width: width, height: bottom - y - labelHeight))
        }
    }

    private func drawStatus(_ area: ScreenRect) {
        painter.fill(area, radius: 12 * scale, color: RGBA(255, 255, 255, 14))

        // The ball the player is on.
        var icon = 0
        if game == .nineBall {
            icon = max(0, match.lowest(sim))
        } else if game == .eightBall {
            let group = match.groups[match.toPlay]
            icon = isOnEight || stage == .over ? 8 : group == .solids ? 1 : group == .stripes ? 9 : 0
        } else {
            icon = struck
        }
        drawBallIcon(x: area.x + 24 * scale, y: area.y + area.height / 2, radius: 11 * scale, ball: icon)

        let textX = area.x + 46 * scale
        let lineHeight = painter.lineHeight(.heading)
        painter.text(.heading, x: textX, y: area.y + area.height / 2 - lineHeight + 3 * scale, statusTitle,
                     color: stage == .over ? accent : Self.textColor)
        var detail = statusDetail
        let room = area.right - textX - (stage == .thinking ? 34 : 8) * scale
        if painter.measure(.body, detail) > room {
            // Cut to fit, at a whole character, with an ellipsis.
            while detail.count > 1 && painter.measure(.body, detail + "…") > room {
                detail.removeLast()
            }
            detail += "…"
        }
        painter.text(.body, x: textX, y: area.y + area.height / 2 + 2 * scale, detail, color: Self.mutedColor)
        if stage == .thinking {
            painter.spinner(x: area.right - 22 * scale, y: area.y + area.height / 2, radius: 8 * scale, thickness: 2.2 * scale, angle: time * 5,
                            color: accent)
        }
    }

    /// The players: who is to shoot, their group or score, and the balls they have left.
    private func drawPlayers(_ area: ScreenRect) {
        let rowHeight = 30 * scale
        let players = match.practice ? 1 : 2
        let russian = table.kind == .pyramid
        for player in 0..<players {
            let y = area.y + Float(player) * rowHeight
            let toShoot = !match.isOver && match.toPlay == player
            let winner = match.isOver && match.winner == player
            if toShoot || winner {
                painter.fill(ScreenRect(x: area.x - 6 * scale, y: y + 2 * scale, width: area.width + 12 * scale, height: rowHeight - 4 * scale),
                             radius: 8 * scale, color: accent.faded(winner ? 0.3 : 0.16))
            }
            painter.disc(x: area.x + 5 * scale, y: y + rowHeight / 2, radius: 3.5 * scale, color: toShoot || winner ? accent : RGBA(255, 255, 255, 40))
            var label = name(player)
            if !isHuman(player) {
                label += "  ·  \(text(Str.levelName(level)))"
            }
            let textY = y + (rowHeight - painter.lineHeight(.body)) / 2
            painter.text(.body, x: area.x + 16 * scale, y: textY, label, color: toShoot || winner ? Self.textColor : Self.textColor.faded(0.75))

            // On the right: the balls of the group, the score, or the strokes taken.
            var right = area.right
            if match.practice {
                let count = text(.shots, shots)
                painter.text(.body, x: right - painter.measure(.body, count), y: textY, count, color: Self.mutedColor)
            } else if game == .americanka {
                let of = text(.toWin, Match.target)
                let score = String(match.score(player))
                painter.text(.body, x: right - painter.measure(.body, of), y: textY, of, color: Self.mutedColor)
                right -= painter.measure(.body, of) + 6 * scale
                painter.text(.heading, x: right - painter.measure(.heading, score), y: y + (rowHeight - painter.lineHeight(.heading)) / 2, score,
                             color: Self.textColor)
            } else if game == .eightBall {
                let group = match.groups[player]
                if group == .open {
                    let open = text(.openTable)
                    painter.text(.body, x: right - painter.measure(.body, open), y: textY, open, color: Self.mutedColor)
                } else {
                    let radius = 6.5 * scale
                    let step = 15.5 * scale
                    var x = right - radius
                    var balls = (1..<max(sim.count, 1)).filter { group.contains($0) && sim.balls[$0].onTable }
                    if balls.isEmpty {
                        balls = [8]
                    }
                    for ball in balls.reversed() {
                        drawBallIcon(x: x, y: y + rowHeight / 2, radius: radius, ball: ball)
                        x -= step
                    }
                }
            }
        }

        // Below: the balls still on the table, the one to hit first ringed.
        if game == .nineBall || match.practice {
            let y = area.y + Float(players) * rowHeight + 13 * scale
            let radius = 6.5 * scale
            let step = 15.5 * scale
            let lowest = game == .nineBall ? match.lowest(sim) : -1
            var x = area.x + radius + 2 * scale
            var shownBalls = 0
            for ball in 1..<max(sim.count, 1) where x < area.right && sim.balls[ball].onTable {
                if ball == lowest {
                    painter.disc(x: x, y: y, radius: radius + 2.5 * scale, color: accent.faded(0.8))
                }
                drawBallIcon(x: x, y: y, radius: radius, ball: ball)
                x += step
                shownBalls += 1
            }
            if shownBalls == 0 && russian {
                drawBallIcon(x: x, y: y, radius: radius, ball: 0)
            }
        }
    }

    /// The power of the stroke and where the cue strikes the ball, both set by dragging.
    private func drawStroke(_ area: ScreenRect) {
        painter.fill(area, radius: 12 * scale, color: RGBA(255, 255, 255, 10))
        let inner = area.inset(by: 10 * scale)

        // The spin: the ball's face seen from behind, a red dot where the cue meets it.
        let r = inner.height / 2
        let cx = inner.right - r
        let cy = inner.y + r
        let russian = table.kind == .pyramid
        let face = russian && struck == 0 ? RGBA(226, 172, 86) : russian ? RGBA(232, 224, 200) : RGBA(236, 234, 226)
        painter.disc(x: cx, y: cy + 1.5 * scale, radius: r + 1.5 * scale, color: RGBA(0, 0, 0, 80))
        painter.disc(x: cx, y: cy, radius: r, color: face.mixed(with: RGBA(0, 0, 0), 0.22))
        painter.disc(x: cx - r * 0.06, y: cy - r * 0.08, radius: r * 0.9, color: face)
        painter.disc(x: cx - r * 0.32, y: cy - r * 0.38, radius: r * 0.22, color: RGBA(255, 255, 255, 120))
        let limit = Self.maxSpin * r
        painter.outline(ScreenRect(x: cx - limit, y: cy - limit, width: 2 * limit, height: 2 * limit), radius: limit, color: RGBA(0, 0, 0, 50))
        painter.fill(ScreenRect(x: cx - r * 0.8, y: cy - 0.5 * scale, width: r * 1.6, height: 1 * scale), radius: 0, color: RGBA(0, 0, 0, 36))
        painter.fill(ScreenRect(x: cx - 0.5 * scale, y: cy - r * 0.8, width: 1 * scale, height: r * 1.6), radius: 0, color: RGBA(0, 0, 0, 36))
        let dotX = cx + side * r
        let dotY = cy - vertical * r
        painter.disc(x: dotX, y: dotY, radius: r * 0.16 + 1 * scale, color: RGBA(255, 255, 255, 160))
        painter.disc(x: dotX, y: dotY, radius: r * 0.16, color: RGBA(210, 34, 30))
        let overSpin = !helpVisible && length(SIMD2(pointer.x - cx, pointer.y - cy)) < r && gesture == .none
        if overSpin {
            cursorHand = true
        }
        if overSpin && pointer.leftPressed {
            activeWidget = Widget.spinBall
            pointer.consumed = true
        }
        if activeWidget == Widget.spinBall {
            if pointer.leftDown {
                setSpin(side: (pointer.x - cx) / r, vertical: -(pointer.y - cy) / r)
            }
            if pointer.leftReleased {
                activeWidget = 0
                pointer.consumed = true
            }
        }

        // The power: a bar, its value in words and in speed.
        let left = inner.x
        let right = cx - r - 16 * scale
        let shownPower = gesture == .strike ? charge : power
        let percent = "\(Int((shownPower * 100).rounded()))%"
        let lineY = inner.y + 1 * scale
        painter.text(.body, x: left, y: lineY, text(.power), color: Self.mutedColor)
        painter.text(.body, x: right - painter.measure(.body, percent), y: lineY, percent, color: Self.textColor)
        let bar = ScreenRect(x: left, y: inner.y + inner.height / 2 - 4 * scale, width: right - left, height: 10 * scale)
        painter.fill(bar, radius: 5 * scale, color: RGBA(255, 255, 255, 20))
        let fill = gesture == .strike ? accent.mixed(with: RGBA(255, 255, 255), 0.25) : accent.faded(0.85)
        painter.fill(ScreenRect(x: bar.x, y: bar.y, width: max(bar.height, bar.width * shownPower), height: bar.height), radius: 5 * scale, color: fill)
        for tick in 1..<4 {
            painter.fill(ScreenRect(x: bar.x + bar.width * Float(tick) / 4 - 0.5 * scale, y: bar.y + 2 * scale, width: 1 * scale,
                                    height: bar.height - 4 * scale), radius: 0, color: RGBA(0, 0, 0, 50))
        }
        let speed = String(format: "%.1f", speedFor(shownPower)) + " " + text(.metresPerSecond)
        painter.text(.body, x: left, y: inner.bottom - painter.lineHeight(.body), speed, color: Self.mutedColor.faded(0.85))
        let spin = text(.spin)
        painter.text(.body, x: right - painter.measure(.body, spin), y: inner.bottom - painter.lineHeight(.body), spin,
                     color: Self.mutedColor.faded(0.85))

        let hit = ScreenRect(x: bar.x - 4 * scale, y: bar.y - 8 * scale, width: bar.width + 8 * scale, height: bar.height + 16 * scale)
        let overPower = !helpVisible && hit.contains(pointer.x, pointer.y) && gesture == .none
        if overPower {
            cursorHand = true
        }
        if overPower && pointer.leftPressed {
            activeWidget = Widget.powerBar
            pointer.consumed = true
        }
        if activeWidget == Widget.powerBar {
            if pointer.leftDown {
                setPower((pointer.x - bar.x) / bar.width)
            }
            if pointer.leftReleased {
                activeWidget = 0
                pointer.consumed = true
            }
        }
    }

    private func drawHistory(_ area: ScreenRect) {
        painter.fill(area, radius: 12 * scale, color: RGBA(0, 0, 0, 40))
        if history.isEmpty {
            painter.textCentered(.body, in: area, text(.noShotsYet), color: Self.mutedColor)
            return
        }
        let inner = area.inset(by: 9 * scale)
        var lines: [(text: String, kind: Int, first: Bool)] = []
        for entry in history.suffix(80) {
            for (index, line) in wrapText(entry.text, width: inner.width - 14 * scale).enumerated() {
                lines.append((line, entry.kind, index == 0))
            }
        }
        let rowHeight = (22 * scale).rounded()
        let visible = max(1, Int(inner.height / rowHeight))
        let maxScroll = Float(max(0, lines.count - visible))
        if area.contains(pointer.x, pointer.y) && pointer.scroll != 0 && !helpVisible {
            historyScroll = min(max(historyScroll - pointer.scroll * 3, 0), maxScroll)
            followHistory = historyScroll >= maxScroll
            pointer.scroll = 0
            pointer.zoom = 0
        }
        if followHistory {
            historyScroll = maxScroll
        }
        historyScroll = min(max(historyScroll, 0), maxScroll)
        let first = Int(historyScroll)
        for i in first..<min(lines.count, first + visible) {
            let line = lines[i]
            let y = inner.y + Float(i - first) * rowHeight
            let color = line.kind == 1 ? Self.foulColor : line.kind == 2 ? accent : Self.textColor
            if line.first {
                painter.disc(x: inner.x + 3 * scale, y: y + rowHeight / 2, radius: 2.5 * scale, color: color.faded(0.7))
            }
            painter.text(.body, x: inner.x + 14 * scale, y: y + (rowHeight - painter.lineHeight(.body)) / 2, line.text,
                         color: i == lines.count - 1 || line.kind != 0 ? color : color.faded(0.82))
        }
        if maxScroll > 0 {
            let barHeight = inner.height * Float(visible) / Float(lines.count)
            let barY = inner.y + (inner.height - barHeight) * (historyScroll / maxScroll)
            painter.fill(ScreenRect(x: area.right - 5 * scale, y: barY, width: 3 * scale, height: barHeight), radius: 1.5 * scale,
                         color: RGBA(255, 255, 255, 50))
        }
    }
}
