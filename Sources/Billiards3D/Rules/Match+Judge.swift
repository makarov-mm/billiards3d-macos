/// The rules applied to a stroke: fouls, groups, balls scored, ball in hand and the end of the game.
extension Match {
    /// Applies the rules to the stroke just played, `sim` holding the balls where they came to rest.
    mutating func judge(_ shot: ShotRecord, sim: inout Simulation) -> Verdict {
        var verdict = Verdict()
        let player = toPlay
        let other = 1 - player
        let wasBreak = breakShot
        breakShot = false
        var objectPocketed = false
        for entry in shot.pocketed {
            objectPocketed = objectPocketed || entry.ball != shot.struck || type == .americanka
        }

        if practice {
            // No fouls: the cue ball comes back in hand, and the table is cleared at leisure.
            if type != .americanka && shot.isPocketed(0) {
                inHand = .anywhere
                sim.placeCueBall()
            } else {
                inHand = .none
            }
            var left = 0
            for i in stride(from: type == .americanka ? 0 : 1, to: sim.count, by: 1) where sim.balls[i].onTable {
                left += 1
            }
            verdict.keepsTurn = true
            if left <= (type == .americanka ? 1 : 0) {
                winner = 0
                verdict.winner = 0
            }
            return verdict
        }

        if type == .americanka {
            // Any ball may be struck; every ball pocketed by a fair stroke counts, the struck one too.
            if shot.firstContact < 0 {
                verdict.foul = .miss
            } else if shot.pocketed.isEmpty && !shot.railAfterContact {
                verdict.foul = .noRail
            }
            if verdict.foul == .none {
                taken[player].append(contentsOf: shot.pocketed.map(\.ball))
                verdict.scored = shot.pocketed.count
                verdict.keepsTurn = verdict.scored > 0
                if score(player) >= Self.target {
                    winner = player
                    verdict.winner = player
                }
            } else {
                // The balls just pocketed go back, and the offender gives up one of his.
                verdict.respot.append(contentsOf: shot.pocketed.map(\.ball))
                if let last = taken[player].popLast() {
                    verdict.forfeited = last
                    verdict.respot.append(last)
                }
            }
            for ball in verdict.respot {
                sim.respot(ball)
            }
            inHand = .none
            // With one ball left there is nothing to strike it at: the higher score wins.
            var left = 0
            for i in 0..<sim.count where sim.balls[i].onTable {
                left += 1
            }
            if winner < 0 && left < 2 {
                winner = score(0) >= score(1) ? 0 : 1
                verdict.winner = winner
            }
            if !verdict.keepsTurn {
                toPlay = other
            }
            return verdict
        }

        let scratch = shot.isPocketed(0)
        if type == .nineBall {
            // The lowest ball on the table before the stroke must be hit first.
            var lowest = 99
            for i in stride(from: 1, to: sim.count, by: 1) where sim.balls[i].onTable || shot.isPocketed(i) {
                lowest = min(lowest, i)
            }
            if scratch {
                verdict.foul = .scratch
            } else if shot.firstContact < 0 {
                verdict.foul = .miss
            } else if shot.firstContact != lowest {
                verdict.foul = .wrongBall
            } else if !wasBreak && !objectPocketed && !shot.railAfterContact {
                verdict.foul = .noRail
            }
            if shot.isPocketed(9) {
                if verdict.foul == .none {
                    winner = player
                    verdict.winner = player
                } else {
                    verdict.respot.append(9)
                }
            }
            verdict.keepsTurn = verdict.foul == .none && objectPocketed
        } else {
            let group = groups[player]
            var groupBefore = 0
            for i in stride(from: 1, to: sim.count, by: 1) where group.contains(i) && (sim.balls[i].onTable || shot.isPocketed(i)) {
                groupBefore += 1
            }
            let onEight = group != .open && groupBefore == 0
            let wrongFirst = onEight ? shot.firstContact != 8
                : group == .open ? shot.firstContact == 8 : !group.contains(shot.firstContact)
            if scratch {
                verdict.foul = .scratch
            } else if shot.firstContact < 0 {
                verdict.foul = .miss
            } else if !wasBreak && wrongFirst {
                verdict.foul = .wrongBall
            } else if !wasBreak && !objectPocketed && !shot.railAfterContact {
                verdict.foul = .noRail
            }

            if shot.isPocketed(8) {
                if wasBreak {
                    verdict.respot.append(8)
                } else {
                    winner = other
                    if !onEight {
                        verdict.foul = .eightEarly
                    } else if verdict.foul != .none {
                        verdict.foul = .eightOnFoul
                    } else if shot.calledPocket >= 0 && shot.pocket(of: 8) != shot.calledPocket {
                        verdict.foul = .eightWrongPocket
                    } else {
                        winner = player
                    }
                    verdict.winner = winner
                }
            }
            if winner < 0 && verdict.foul == .none {
                var mine = group
                if group == .open && !wasBreak {
                    // The first ball pocketed after the break decides the groups.
                    if let first = shot.pocketed.first(where: { $0.ball != 0 && $0.ball != 8 }) {
                        mine = first.ball < 8 ? .solids : .stripes
                        groups[player] = mine
                        groups[other] = mine == .solids ? .stripes : .solids
                        verdict.assigned = mine
                    }
                }
                for entry in shot.pocketed where wasBreak ? entry.ball != 0 : mine.contains(entry.ball) {
                    verdict.keepsTurn = true
                }
            }
        }

        for ball in verdict.respot {
            sim.respot(ball)
        }
        if verdict.foul != .none && winner < 0 {
            inHand = wasBreak && scratch ? .kitchen : .anywhere
            if scratch {
                sim.placeCueBall()
            }
        } else {
            inHand = .none
        }
        if !verdict.keepsTurn {
            toPlay = other
        }
        return verdict
    }
}
