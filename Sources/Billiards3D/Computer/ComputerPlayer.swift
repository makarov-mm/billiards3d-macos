import Foundation

/// The computer player. For each ball it may strike, each ball it may pot and each pocket it finds the line through
/// the ghost ball, keeps the clear and easy ones, plays them out with a few speeds and spins to see where the balls
/// stop and how easy the next shot is, tests the best against its own unsteadiness, and plays safe when nothing is
/// likely to go in. Lower levels look at fewer shots and strike less accurately.
enum ComputerPlayer {
    private struct Option {
        var shot: Shot
        var quality = 0.0
        var worth = -1e9
    }

    static func choose(_ position: Simulation, match: Match, level: Int, seed: UInt64, stop: StopFlag) -> Shot {
        let spec = LevelSpec.level(level)
        var random = RandomSource(seed: seed)
        let t = position.table
        let R = t.ballRadius
        let me = match.toPlay

        // The break: from the kitchen into the head of the rack, hard.
        if match.breakShot {
            var shot = Shot()
            shot.struck = 0
            shot.place = true
            let pool = t.kind == .pool
            shot.spot = V2(t.headString - 0.04, (pool ? 0.22 : 0.08) * random.uniform(-1, 1) * t.width / 2)
            var apex = t.footSpot
            for i in stride(from: 1, to: position.count, by: 1) where position.balls[i].onTable && position.balls[i].p.x < apex.x + R {
                apex = position.balls[i].p
            }
            shot.direction = (apex + V2(0, random.uniform(-1, 1) * R * 0.15) - shot.spot).normalized
            shot.speed = pool ? 8.0 : 5.5
            shot.vertical = -0.12
            return withNoise(shot, spec, &random, t)
        }

        var options: [Option] = []

        // Where to put a ball in hand: behind each target, in line with each pocket, a little off it.
        var spots: [V2?] = [nil]
        let inHand = match.inHand != .none && position.balls[0].onTable
        if inHand {
            spots.removeAll()
            var ranked: [(ease: Double, spot: V2)] = []
            var probe = position
            for target in match.targets(position, player: me) where target != 0 {
                for pocket in 0..<6 {
                    let u = (t.pockets[pocket].mouth - position.balls[target].p).normalized
                    for distance in [0.15, 0.32, 0.55] {
                        for angle in [0.0, 0.3, -0.3] {
                            let spot = position.balls[target].p - u.rotated(angle) * (2 * R + distance)
                            if (match.inHand == .kitchen && spot.x > t.headString - R) || !position.isFreeSpot(spot, except: 0) {
                                continue
                            }
                            probe.balls[0].p = spot
                            if let pot = line(probe, struck: 0, target: target, pocket: pocket) {
                                ranked.append((pot.ease, spot))
                            }
                        }
                    }
                }
            }
            ranked.sort { $0.ease > $1.ease }
            for entry in ranked.prefix(10) {
                spots.append(entry.spot)
            }
            if spots.isEmpty {
                spots.append(position.balls[0].p)
            }
        }

        // The pots, easiest first.
        for spot in spots {
            var base = position
            if let spot {
                base.balls[0].p = spot
            }
            let targets = match.targets(base, player: me)
            for struck in strikable(base, match) {
                for target in targets where target != struck {
                    for pocket in 0..<6 {
                        guard let pot = line(base, struck: struck, target: target, pocket: pocket) else {
                            continue
                        }
                        let mouth = t.pockets[pocket].mouth
                        let ghost = base.balls[target].p - (mouth - base.balls[target].p).normalized * (2 * R)
                        var shot = Shot()
                        shot.struck = struck
                        shot.direction = pot.direction
                        shot.speed = potSpeed(t, toGhost: (ghost - base.balls[struck].p).length, toPocket: (mouth - base.balls[target].p).length,
                                              cut: pot.direction.dot((mouth - ghost).normalized))
                        shot.calledPocket = match.type == .eightBall && target == 8 ? pocket : -1
                        if let spot {
                            shot.place = true
                            shot.spot = spot
                        }
                        options.append(Option(shot: shot, quality: pot.ease))
                    }
                }
            }
        }
        options.sort { $0.quality > $1.quality }
        if options.count > spec.candidates {
            options.removeSubrange(spec.candidates...)
        }

        // Each played out with a few speeds and spins, for the position after it.
        var tried: [Option] = []
        var events: [Event] = []
        let speedFactors = spec.speeds == 1 ? [1.0, 1.0, 1.0] : spec.speeds == 2 ? [0.85, 1.25, 1.25] : [0.75, 1.0, 1.4]
        let spins = [0.0, 0.35, -0.35]
        for option in options {
            for s in 0..<spec.speeds {
                for k in 0..<spec.spins {
                    if stop.isRaised {
                        return option.shot
                    }
                    var variant = option
                    variant.shot.speed = clamp(option.shot.speed * speedFactors[s], 0.4, t.maxSpeed)
                    variant.shot.vertical = spins[k]
                    events.removeAll(keepingCapacity: true)
                    let after = position.played(variant.shot, events: &events)
                    variant.worth = worth(match, after, variant.shot, events, me)
                    tried.append(variant)
                }
            }
        }

        // Nothing promising: play safe, touching a ball the rules allow and leaving the other side little.
        let bestPot = tried.map(\.worth).max() ?? -1e9
        if bestPot < 60 {
            let struckBalls = inHand ? [0] : strikable(position, match)
            let targets = match.targets(position, player: me)
            var budget = 160
            for struck in struckBalls {
                for target in targets where target != struck {
                    let from = inHand ? position.balls[0].p : position.balls[struck].p
                    let to = position.balls[target].p
                    let across = (to - from).normalized.perpendicular
                    func attempt(_ direction: V2, _ speed: Double) {
                        budget -= 1
                        if budget < 0 || stop.isRaised {
                            return
                        }
                        var option = Option(shot: Shot())
                        option.shot.struck = struck
                        option.shot.direction = direction
                        option.shot.speed = speed
                        events.removeAll(keepingCapacity: true)
                        let after = position.played(option.shot, events: &events)
                        option.worth = worth(match, after, option.shot, events, me)
                        tried.append(option)
                    }
                    for thickness in [-0.8, -0.35, 0.0, 0.35, 0.8] {
                        for speed in [0.9, 1.6, 2.6] {
                            attempt((to + across * (thickness * 2 * R) - from).normalized, speed)
                        }
                    }
                    // Hidden behind other balls: off a cushion, aiming at the target's image in it.
                    if !clear(position, from, to, struck, target, 2 * R - 1e-4) {
                        let x = t.length / 2 - t.contactRadius
                        let z = t.width / 2 - t.contactRadius
                        for image in [V2(2 * x - to.x, to.z), V2(-2 * x - to.x, to.z), V2(to.x, 2 * z - to.z), V2(to.x, -2 * z - to.z)] {
                            for speed in [1.6, 2.8] {
                                attempt((image - from).normalized, speed)
                            }
                        }
                    }
                }
            }
        }
        if tried.isEmpty {
            // Hemmed in: at least hit something.
            var shot = Shot()
            shot.struck = strikable(position, match).first ?? 0
            let target = match.targets(position, player: me).first ?? shot.struck
            shot.direction = (position.balls[target].p - position.balls[shot.struck].p).normalized
            shot.speed = 2.5
            return withNoise(shot, spec, &random, t)
        }

        // The best few tested against the computer's own unsteadiness.
        tried.sort { $0.worth > $1.worth }
        var bestScore = -1e18
        var best = tried[0].shot
        for finalist in tried.prefix(spec.finalists) {
            var total = 0.0
            for _ in 0..<spec.samples {
                if stop.isRaised {
                    return best
                }
                let noisy = withNoise(finalist.shot, spec, &random, t)
                events.removeAll(keepingCapacity: true)
                let after = position.played(noisy, events: &events)
                total += worth(match, after, noisy, events, me)
            }
            let score = 0.35 * finalist.worth + 0.65 * total / Double(spec.samples)
            if score > bestScore {
                bestScore = score
                best = finalist.shot
            }
        }
        return withNoise(best, spec, &random, t)
    }

    /// The line to the ghost ball for potting `target` into `pocket` with `struck`, if clear: the direction and how
    /// easy it is, 0 to 1.
    static func line(_ sim: Simulation, struck: Int, target: Int, pocket: Int) -> (direction: V2, ease: Double)? {
        let t = sim.table
        let R = t.ballRadius
        let s = sim.balls[struck]
        let o = sim.balls[target]
        let p = t.pockets[pocket]
        let aim = p.mouth + p.axis * (0.25 * R)
        var u = aim - o.p
        let toPocket = u.length
        if toPocket < 1e-6 {
            return nil
        }
        u = u * (1 / toPocket)
        // A pocket takes a ball from in front; a middle pocket refuses steep ones.
        let approach = u.dot(p.axis)
        if approach < (p.corner ? 0.4 : 0.62) {
            return nil
        }
        let ghost = o.p - u * (2 * R)
        var direction = ghost - s.p
        let toGhost = direction.length
        if toGhost < 1e-6 {
            return nil
        }
        direction = direction * (1 / toGhost)
        let cut = direction.dot(u)
        if cut < 0.17 {
            return nil
        }
        if abs(ghost.x) > t.length / 2 - R * 0.9 || abs(ghost.z) > t.width / 2 - R * 0.9 {
            return nil
        }
        if !clear(sim, s.p, ghost, struck, target, 2 * R - 1e-4) || !clear(sim, o.p, aim, target, struck, 2 * R - 1e-4) {
            return nil
        }
        let ease = pow(cut, 1.6) * pow(approach, 0.6) / (1 + 0.8 * toGhost + 1.0 * toPocket)
        return (direction, min(1.0, ease * 1.6))
    }

    /// The easiest pot the player could try from this position, 0 to 1.
    static func bestChance(_ sim: Simulation, match: Match, player: Int) -> Double {
        if match.isOver {
            return 0
        }
        if match.inHand != .none {
            return 0.9
        }
        var best = 0.0
        let targets = match.targets(sim, player: player)
        for struck in strikable(sim, match) {
            for target in targets where target != struck {
                for pocket in 0..<6 {
                    if let pot = line(sim, struck: struck, target: target, pocket: pocket) {
                        best = max(best, pot.ease)
                    }
                }
            }
        }
        return best
    }

    // MARK: - Helpers

    private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        value < low ? low : high < value ? high : value
    }

    private static func distanceToSegment(_ p: V2, _ a: V2, _ b: V2) -> Double {
        let ab = b - a
        let length = ab.dot(ab)
        let t = length > 1e-12 ? clamp((p - a).dot(ab) / length, 0, 1) : 0
        return (p - (a + ab * t)).length
    }

    /// No ball but the two named comes within `clearance` of the line from a to b.
    private static func clear(_ sim: Simulation, _ a: V2, _ b: V2, _ skip1: Int, _ skip2: Int, _ clearance: Double) -> Bool {
        for i in 0..<sim.count where i != skip1 && i != skip2 && sim.balls[i].onTable {
            if distanceToSegment(sim.balls[i].p, a, b) < clearance {
                return false
            }
        }
        return true
    }

    /// Enough speed for the struck ball to send the other `toPocket` metres, still rolling at the pocket, after a cut
    /// whose cosine is `cut`.
    private static func potSpeed(_ t: TableSpec, toGhost: Double, toPocket: Double, cut: Double) -> Double {
        let g = 9.81
        let objectSpeed = (2 * t.rollFriction * g * (toPocket + 0.35)).squareRoot() * 1.3 + 0.15
        let atContact = objectSpeed / max(0.2, cut * (1 + t.ballRestitution) / 2)
        let start = (atContact * atContact + 2 * t.rollFriction * g * toGhost * 1.5).squareRoot()
        return clamp(start, 0.5, t.maxSpeed * 0.85)
    }

    private static func strikable(_ sim: Simulation, _ match: Match) -> [Int] {
        (0..<sim.count).filter { match.mayStrike(sim, $0) }
    }

    /// What a stroke is worth to `me`, from where the balls stopped: winning or losing, fouls, balls scored, and the
    /// next shot, mine or the other side's.
    private static func worth(_ match: Match, _ after: Simulation, _ shot: Shot, _ events: [Event], _ me: Int) -> Double {
        var m = match
        var s = after
        let verdict = m.judge(ShotRecord(struck: shot.struck, events: events, calledPocket: shot.calledPocket), sim: &s)
        if m.winner >= 0 {
            return m.winner == me ? 1000 : -1000
        }
        var worth = 0.0
        if verdict.foul != .none {
            worth -= match.type == .americanka ? 110 : 170
        }
        if match.type == .americanka {
            worth += Double(110 * verdict.scored - (verdict.forfeited >= 0 ? 60 : 0) + 25 * (m.score(me) - m.score(1 - me)))
        }
        if verdict.keepsTurn {
            worth += 100 + 80 * bestChance(s, match: m, player: me)
        } else {
            worth -= 75 * bestChance(s, match: m, player: 1 - me)
        }
        return worth
    }

    private static func withNoise(_ shot: Shot, _ level: LevelSpec, _ random: inout RandomSource, _ table: TableSpec) -> Shot {
        var shot = shot
        shot.direction = shot.direction.rotated(random.normal() * level.aim * Double.pi / 180)
        shot.speed = clamp(shot.speed * (1 + random.normal() * level.speed), 0.2, table.maxSpeed)
        shot.side += random.normal() * level.spin
        shot.vertical += random.normal() * level.spin
        let offset = hypot(shot.side, shot.vertical)
        if offset > 0.5 {
            shot.side *= 0.5 / offset
            shot.vertical *= 0.5 / offset
        }
        return shot
    }
}
