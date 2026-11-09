import AppKit
import simd

/// The play: new games and turns, the strokes of the players and of the computer, and the choices of the game.
extension GameController {
    var isAiming: Bool { stage == .ready && humanToShoot && match.mayStrike(sim, struck) }

    var isOnEight: Bool { match.isOnEight(sim, player: match.toPlay) }

    func isHuman(_ player: Int) -> Bool {
        switch mode {
        case .vsComputer: player == 0
        case .demo: false
        default: true
        }
    }

    var humanToShoot: Bool { !match.isOver && isHuman(match.toPlay) }

    // MARK: - Games and turns

    func setupTable(_ kind: TableKind) {
        table = TableSpec(kind)
        sim = Simulation(table: table)
        live = Simulation(table: table)
        do {
            try renderer.setTable(table)
        } catch {
            FileHandle.standardError.write(Data("3D Billiards: \(error)\n".utf8))
        }
        tableView.setTable(table)
        camera.setTable(width: Float(table.width), reach: Float(table.length / 2 + table.cushionWidth + table.railWidth))
        tableReady = true
    }

    /// The game kept from the last session, if it is one and fits the mode.
    func loadMatch(_ text: String) -> Bool {
        if text.isEmpty {
            return false
        }
        for kind in [TableKind.pool, .pyramid] {
            guard let loaded = Match.read(text, table: TableSpec(kind)) else { continue }
            if loaded.match.practice != (mode == .practice) {
                return false
            }
            setupTable(kind)
            guard let (match, sim) = Match.read(text, table: table) else { return false }
            self.match = match
            self.sim = sim
            game = match.type
            return true
        }
        return false
    }

    func newGame() {
        stopComputer()
        if !tableReady || table.kind != game.table {
            setupTable(game.table)
        }
        match = Match()
        match.type = game
        match.practice = mode == .practice
        match.toPlay = match.practice ? 0 : breaker
        if !match.practice {
            breaker = 1 - breaker
        }
        sim.rack(game, random: &random)
        undoStack.removeAll()
        history.removeAll()
        shots = 0
        overClock = 0
        gesture = .none
        tableView.reset(sim, rack: true)
        sound.play(.rack, volume: 0.7)

        let first = match.toPlay + 1
        let detail = match.practice ? text(.practice)
            : mode == .vsComputer ? text(match.toPlay == 0 ? .breakYou : .breakComputer)
            : mode == .twoPlayers ? text(.breakPlayer, first) : text(.breakComputerN, first)
        showBanner(text(Self.gameName(game)), detail, seconds: 2.6)
        startTurn()
        followAim(instant: true)
        save()
    }

    static func gameName(_ game: GameType) -> Str {
        switch game {
        case .eightBall: .gameEight
        case .nineBall: .gameNine
        case .americanka: .gameAmericanka
        }
    }

    func startTurn() {
        // The aim suggested for the turn stays until the pointer is moved.
        pointerAims = false
        turnX = pointer.x
        turnY = pointer.y
        called = -1
        calledFixed = false
        side = 0
        vertical = 0
        pull = 0
        charge = 0
        if gesture == .strike || gesture == .placeBall {
            gesture = .none
        }
        predictionDirty = true
        if match.isOver {
            stage = .over
            return
        }
        defaultAim()
        followAim()
        if isHuman(match.toPlay) {
            stage = .ready
            return
        }
        stage = .thinking
        thinkClock = 0
        computerShot = nil
        computer.start(position: sim, match: match, level: level, seed: random.next())
    }

    /// Points the cue at the easiest pot there is, or else at the nearest ball that may be hit.
    func defaultAim() {
        let player = match.toPlay
        struck = 0
        if power < 0.05 {
            power = 0.4
        }
        if match.breakShot {
            aim = (table.footSpot - sim.balls[0].p).normalized
            power = 0.92
            return
        }
        let strikers = game == .americanka ? (0..<sim.count).filter { match.mayStrike(sim, $0) } : [0]
        // With the first ball gone into a pocket, another strikes: without one the turn could not be played.
        if !match.mayStrike(sim, struck), let first = strikers.first(where: { match.mayStrike(sim, $0) }) {
            struck = first
        }
        // In practice any ball may go, the eight too.
        let targets = match.practice ? (0..<sim.count).filter { sim.balls[$0].onTable } : match.targets(sim, player: player)
        var best = -1.0
        for striker in strikers where match.mayStrike(sim, striker) {
            for target in targets where target != striker {
                for pocket in 0..<6 {
                    if let line = ComputerPlayer.line(sim, struck: striker, target: target, pocket: pocket), line.ease > best {
                        best = line.ease
                        struck = striker
                        aim = line.direction
                    }
                }
            }
        }
        if best >= 0 {
            return
        }
        var nearest = 1e9
        for target in targets where target != struck {
            let to = sim.balls[target].p - sim.balls[struck].p
            if to.length < nearest {
                nearest = to.length
                aim = to.normalized
            }
        }
    }

    func speedFor(_ power: Float) -> Double {
        let p = Double(min(max(power, 0), 1))
        return table.maxSpeed * (0.08 * p + 0.92 * p * p)
    }

    func powerFor(_ speed: Double) -> Float {
        let share = min(max(speed / table.maxSpeed, 0), 1)
        return Float((-0.08 + (0.0064 + 4 * 0.92 * share).squareRoot()) / (2 * 0.92))
    }

    func makeShot() -> Shot {
        var shot = Shot()
        shot.struck = struck
        shot.direction = aim
        shot.speed = speedFor(power)
        shot.side = Double(side)
        shot.vertical = Double(vertical)
        shot.calledPocket = isOnEight ? called : -1
        return shot
    }

    // MARK: - The stroke

    /// Starts the cue's stroke: from where it is drawn back, or first drawing it back.
    func shoot(_ shot: Shot, backswing: Bool) {
        self.shot = shot
        stage = .stroke
        strokeClock = 0
        let strength = powerFor(shot.speed)
        strokeFrom = pull
        strokeTo = backswing ? CuePose.pull(for: strength) : pull
        strokeBack = backswing ? 0.42 : 0
        strokeHold = backswing ? 0.16 : 0
        strokeForward = min(max(0.14 - 0.09 * strength, 0.05), 0.14)
        gesture = .none
    }

    func updateStroke(_ seconds: Float) {
        strokeClock += seconds
        let t = strokeClock
        if t < strokeBack {
            pull = strokeFrom + (strokeTo - strokeFrom) * Easing.smoothStep(0, 1, t / strokeBack)
            return
        }
        if t < strokeBack + strokeHold {
            pull = strokeTo
            return
        }
        let s = (t - strokeBack - strokeHold) / strokeForward
        if s < 1 {
            pull = strokeTo * (1 - s * s)
            return
        }
        pull = 0
        strike()
    }

    /// The cue meets the ball: the balls are played out from here, frame by frame.
    private func strike() {
        undoStack.append(Snapshot(match: match, sim: sim, history: history.count, shots: shots))
        if undoStack.count > 400 {
            undoStack.removeFirst()
        }
        live = sim
        live.turnBalls = true
        live.time = 0
        events.removeAll()
        heard = 0
        let ball = sim.balls[shot.struck]
        strikeSpot = ball.p
        live.strike(shot.struck, direction: shot.direction, speed: shot.speed, side: shot.side, vertical: shot.vertical)
        stage = .rolling
        rollClock = 0
        follow = 0
        let strength = powerFor(shot.speed)
        let R = Float(table.ballRadius)
        sound.play(.cue, volume: 0.3 + 0.7 * strength, pan: pan(at: SIMD3(Float(ball.p.x), R, Float(ball.p.z))), pitch: 0.94 + 0.12 * strength)
        camera.lift()
    }

    /// Where a point of the scene is heard, from -1 on the left to 1 on the right.
    func pan(at point: SIMD3<Float>) -> Float {
        guard let screen = camera.toScreen(point, width: Float(width), height: Float(height)) else { return 0 }
        return min(max((screen.x / max(1, Float(width)) * 2 - 1) * 0.7, -0.8), 0.8)
    }

    func updateRolling(_ seconds: Float) {
        rollClock += seconds
        live.advance(Double(seconds), events: &events)
        let R = Float(table.ballRadius)
        var sounded = 0
        while heard < events.count {
            let event = events[heard]
            heard += 1
            sounded += 1
            if sounded > 8 {
                continue // a crowd at once: the loudest are heard anyway
            }
            let ball = live.balls[event.a]
            let pan = pan(at: SIMD3(Float(ball.p.x), R, Float(ball.p.z)))
            let speed = Float(event.speed)
            let vary = Float(random.uniform(0.94, 1.07))
            switch event.kind {
            case .ballBall:
                sound.play(.ball, volume: min(max(speed / 2.6, 0.03), 1), pan: pan, pitch: vary * (table.kind == .pyramid ? 0.88 : 1))
            case .cushion:
                sound.play(.cushion, volume: min(max(speed / 3, 0.03), 0.9), pan: pan, pitch: vary)
            case .pocket:
                sound.play(table.kind == .pyramid ? .net : .pocket, volume: min(max(0.45 + speed / 4, 0.4), 1), pan: pan, pitch: vary)
            }
        }
        if !live.isMoving || rollClock > 60 {
            finishShot()
        }
    }

    private func finishShot() {
        for i in 0..<live.count {
            // Anything still creeping after a minute is stopped where it is.
            live.balls[i].v = .zero
            live.balls[i].w = .zero
        }
        let shooter = match.toPlay
        let record = ShotRecord(struck: shot.struck, events: events, calledPocket: shot.calledPocket)
        let verdict = match.judge(record, sim: &live)
        sim = live
        sim.time = 0
        shots += 1
        logShot(shooter, record, verdict)

        if verdict.foul != .none && !match.practice {
            showToast(text(.foul, foulText(verdict.foul)))
            if !match.isOver {
                sound.play(.foul, volume: 0.8)
            }
        } else if verdict.assigned != .open {
            showToast(text(verdict.assigned == .solids ? .logSolids : .logStripes, name(shooter)))
        }

        if match.isOver {
            stage = .over
            overClock = 0
            var detail = ""
            if game == .americanka && !match.practice {
                detail = "\(match.score(0)) : \(match.score(1))"
            } else if verdict.foul != .none {
                detail = text(.foul, foulText(verdict.foul))
            } else if match.practice {
                detail = text(.shots, shots)
            }
            showBanner(winnerTitle, detail, seconds: -1)
            sound.play(.win, volume: 0.9)
            gesture = .none
            save()
            return
        }
        startTurn()
        save()
    }

    func undo() {
        if undoStack.isEmpty || mode == .demo {
            showToast(text(.nothingToUndo))
            return
        }
        stopComputer()
        // Back to the last stroke a person played, past the computer's since.
        while undoStack.count > 1, let last = undoStack.last, !isHuman(last.match.toPlay) {
            undoStack.removeLast()
        }
        let snapshot = undoStack.removeLast()
        match = snapshot.match
        sim = snapshot.sim
        history = Array(history.prefix(snapshot.history))
        shots = snapshot.shots
        tableView.reset(sim, rack: false)
        bannerTime = 0
        gesture = .none
        startTurn()
        save()
    }

    // MARK: - The computer

    func stopComputer() {
        computer.cancel()
        computerShot = nil
        if stage == .presenting && shot.place {
            sim.balls[0].p = presentSpot
        }
        if stage == .thinking || stage == .presenting {
            stage = .ready
        }
    }

    func updateComputer(_ seconds: Float) {
        if stage == .thinking {
            thinkClock += seconds
            if let chosen = computer.take() {
                computerShot = chosen
            }
            guard let chosen = computerShot, thinkClock >= Self.minThink else { return }
            shot = chosen
            computerShot = nil
            stage = .presenting
            presentClock = 0
            presentSpot = sim.balls[0].p
            presentAim = aim
            presentPower = power
            presentSide = side
            presentVertical = vertical
            struck = shot.struck
            called = shot.calledPocket
            predictionDirty = true
            return
        }

        // It puts the ball down, turns the cue to its line and sets the spin and the power, then strikes.
        presentClock += seconds
        let placeTime: Float = shot.place ? 0.7 : 0
        if shot.place {
            let s = Easing.smoothStep(0, 1, presentClock / placeTime)
            sim.balls[0].p = presentSpot + (shot.spot - presentSpot) * Double(s)
            if presentClock < placeTime {
                return
            }
        }
        let from = presentAim.angle
        let turn = remainder(shot.direction.angle - from, 2 * Double.pi)
        let aimTime = 0.3 + 0.5 * Float(min(1, abs(turn) / 1.6))
        let t = Easing.smoothStep(0, 1, (presentClock - placeTime) / aimTime)
        aim = V2(cos(from + turn * Double(t)), sin(from + turn * Double(t)))
        power = presentPower + (powerFor(shot.speed) - presentPower) * t
        side = presentSide + (Float(shot.side) - presentSide) * t
        vertical = presentVertical + (Float(shot.vertical) - presentVertical) * t
        predictionDirty = true
        followAim()
        if presentClock >= placeTime + aimTime + 0.25 {
            aim = shot.direction.normalized
            shoot(shot, backswing: true)
        }
    }

    // MARK: - The aim

    func updatePrediction() {
        let showing = (stage == .ready && !match.isOver) || stage == .presenting
        guard showing, predictionDirty else { return }
        predictionDirty = false
        if !sim.balls[struck].onTable {
            prediction = Prediction()
            return
        }
        let scale = table.length / 2.54
        prediction = Prediction.predict(sim, struck: struck, direction: aim, speed: speedFor(power), side: Double(side), vertical: Double(vertical),
                                        reachAfter: 0.6 * scale, reachObject: 1.6 * scale)
        // The pocket for the eight: where the aim sends it, unless one was chosen.
        if isOnEight && !calledFixed && stage == .ready {
            called = -1
            if prediction.hit == 8 && prediction.object.count >= 2 {
                let start = prediction.object[0]
                let next = prediction.object[1]
                called = prediction.objectPocket >= 0 ? prediction.objectPocket : Prediction.pocketAlong(table, from: start, direction: next - start)
            }
        }
    }

    func turnAim(_ radians: Float) {
        aim = aim.rotated(Double(radians)).normalized
        predictionDirty = true
        followAim()
    }

    func followAim(instant: Bool = false) {
        let ball = tableView.position(sim, struck)
        camera.follow(ball: ball, aim: SIMD2(Float(aim.x), Float(aim.z)), instant: instant)
    }

    func setSpin(side: Float, vertical: Float) {
        var side = side
        var vertical = vertical
        let size = (side * side + vertical * vertical).squareRoot()
        if size > Self.maxSpin {
            side *= Self.maxSpin / size
            vertical *= Self.maxSpin / size
        }
        self.side = abs(side) < 1e-3 ? 0 : side
        self.vertical = abs(vertical) < 1e-3 ? 0 : vertical
        predictionDirty = true
    }

    func setPower(_ power: Float) {
        self.power = min(max(power, 0.02), 1)
        predictionDirty = true
    }

    // MARK: - The choices

    func setGame(_ index: Int) {
        let count = GameType.allCases.count
        game = GameType(rawValue: (index % count + count) % count) ?? .eightBall
        newGame()
    }

    func setMode(_ index: Int) {
        let count = Mode.allCases.count
        let newMode = Mode(rawValue: (index % count + count) % count) ?? .vsComputer
        let practiceChanges = (newMode == .practice) != (mode == .practice)
        mode = newMode
        if practiceChanges {
            newGame()
            return
        }
        if (stage == .thinking || stage == .presenting) && isHuman(match.toPlay) {
            stopComputer()
            startTurn()
        } else if stage == .ready && !isHuman(match.toPlay) {
            startTurn()
        }
        save()
    }

    func setLevel(_ level: Int) {
        self.level = min(max(level, 1), 5)
        save()
    }

    func setTheme(_ index: Int) {
        let count = Themes.all.count
        themeIndex = (index % count + count) % count
        do {
            try renderer.setTheme(theme)
        } catch {
            FileHandle.standardError.write(Data("3D Billiards: \(error)\n".utf8))
        }
        save()
    }

    func setAimLines(_ index: Int) {
        let count = AimLines.allCases.count
        aimLines = AimLines(rawValue: (index % count + count) % count) ?? .full
        predictionDirty = true
        save()
    }

    func setCamera(_ index: Int) {
        let count = CameraMode.allCases.count
        camera.setMode(CameraMode(rawValue: (index % count + count) % count) ?? .overview)
        followAim()
        save()
    }

    func toggleSound() {
        sound.isEnabled = !sound.isEnabled
        save()
    }

    func toggleLanguage() {
        language = language.other
        languageChanged?(language)
        save()
    }

    func toggleFullScreen() {
        view?.window?.toggleFullScreen(nil)
    }

    func save() {
        settings.theme = themeIndex
        settings.level = level
        settings.mode = mode.rawValue
        settings.game = game.rawValue
        settings.aim = aimLines.rawValue
        settings.camera = camera.mode.rawValue
        settings.breaker = breaker
        settings.sound = sound.isEnabled
        settings.panel = panelVisible
        settings.language = language
        settings.match = sim.count > 0 ? match.text(with: sim) : ""
        settings.history = history.suffix(60).map { "\($0.kind)\($0.text)" }.joined(separator: "|")
        settings.save()
    }

    // MARK: - The history

    func addHistory(_ text: String, kind: Int) {
        history.append(HistoryLine(text: text, kind: kind))
        followHistory = true
    }

    private func logShot(_ shooter: Int, _ record: ShotRecord, _ verdict: Verdict) {
        let who = name(shooter)
        if verdict.foul != .none && !match.practice {
            addHistory(text(.logFoul, who, foulText(verdict.foul)), kind: 1)
        } else {
            let potted = record.pocketed.filter { $0.ball != 0 || game == .americanka }.map { ballName($0.ball) }
            if potted.isEmpty {
                addHistory(text(.logNothing, who), kind: 0)
            } else {
                addHistory(text(potted.count == 1 ? .logPotted : .logPottedMany, who, potted.joined(separator: ", ")), kind: 0)
            }
        }
        if verdict.assigned != .open {
            addHistory(text(verdict.assigned == .solids ? .logSolids : .logStripes, who), kind: 0)
        }
        if !verdict.respot.isEmpty {
            addHistory(text(.logBack, verdict.respot.map { ballName($0) }.joined(separator: ", ")), kind: 1)
        }
        if match.isOver {
            addHistory(text(.logWin, name(match.winner)), kind: 2)
        }
    }
}
