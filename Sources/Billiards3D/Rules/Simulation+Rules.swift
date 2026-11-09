import Foundation

/// The balls set out by the rules: a new rack, a ball taken out of its pocket, and the cue ball back in hand.
extension Simulation {
    /// Racks the balls for a new game; the cue ball waits in the kitchen.
    mutating func rack(_ type: GameType, random: inout RandomSource) {
        let R = table.ballRadius
        let gap = 1.0004
        let foot = table.footSpot
        func spot(_ row: Int, _ across: Double) -> V2 {
            foot + V2(Double(row) * 3.0.squareRoot() * R * gap, across * 2 * R * gap)
        }
        count = type == .nineBall ? 10 : 16
        time = 0
        for i in balls.indices {
            balls[i] = Ball()
        }
        setBall(0, at: V2(table.headString - 2 * R, 0), random: &random)

        if type == .nineBall {
            // A diamond: the one at the front, the nine in the middle.
            var rest = [2, 3, 4, 5, 6, 7, 8]
            random.shuffle(&rest)
            let rows = [1, 2, 3, 2, 1]
            var next = 0
            for row in 0..<5 {
                for k in 0..<rows[row] {
                    let ball: Int
                    if row == 0 {
                        ball = 1
                    } else if row == 2 && k == 1 {
                        ball = 9
                    } else {
                        ball = rest[next]
                        next += 1
                    }
                    setBall(ball, at: spot(row, Double(k) - Double(rows[row] - 1) / 2.0), random: &random)
                }
            }
            loosen(random: &random)
            return
        }

        // A triangle of fifteen. In eight-ball the eight in the middle and a solid and a stripe in the back corners.
        var order = Array(1...15)
        random.shuffle(&order)
        if type == .eightBall {
            var solids = [1, 2, 3, 4, 5, 6, 7]
            var stripes = [9, 10, 11, 12, 13, 14, 15]
            random.shuffle(&solids)
            random.shuffle(&stripes)
            var others: [Int] = []
            for i in 1..<7 {
                others.append(solids[i])
                others.append(stripes[i])
            }
            random.shuffle(&others)
            let solidLeft = random.next() % 2 == 0
            order.removeAll()
            var next = 0
            for row in 0..<5 {
                for k in 0...row {
                    if row == 2 && k == 1 {
                        order.append(8)
                    } else if row == 4 && k == 0 {
                        order.append(solidLeft ? solids[0] : stripes[0])
                    } else if row == 4 && k == 4 {
                        order.append(solidLeft ? stripes[0] : solids[0])
                    } else {
                        order.append(others[next])
                        next += 1
                    }
                }
            }
        }
        var index = 0
        for row in 0..<5 {
            for k in 0...row {
                setBall(order[index], at: spot(row, Double(k) - Double(row) / 2.0), random: &random)
                index += 1
            }
        }
        loosen(random: &random)
    }

    /// Takes a ball out of its pocket and sets it on the foot spot, or the nearest free point behind it on the long
    /// line.
    mutating func respot(_ ball: Int) {
        let R = table.ballRadius
        let q = balls[ball].q
        func place(_ p: V2) {
            balls[ball] = Ball()
            balls[ball].p = p
            balls[ball].q = q
        }
        var x = table.footSpot.x
        while x < table.length / 2 - R {
            if isFreeSpot(V2(x, 0), except: ball) {
                return place(V2(x, 0))
            }
            x += 0.25 * R
        }
        x = table.footSpot.x
        while x > -table.length / 2 + R {
            if isFreeSpot(V2(x, 0), except: ball) {
                return place(V2(x, 0))
            }
            x -= 0.25 * R
        }
        var z = 0.0
        while z < table.width / 2 {
            for side in [1.0, -1.0] where isFreeSpot(V2(table.footSpot.x, side * z), except: ball) {
                return place(V2(table.footSpot.x, side * z))
            }
            z += 0.5 * R
        }
    }

    /// The cue ball back on the table for a ball in hand: on the head spot or near it, to be moved by the player.
    mutating func placeCueBall() {
        let R = table.ballRadius
        for ring in 0..<40 {
            let around = max(1, ring * 6)
            for k in 0..<around {
                let angle = 2 * Double.pi * Double(k) / Double(around)
                let p = V2(table.headString - 2 * R, 0) + V2(cos(angle), sin(angle)) * (Double(ring) * 2.2 * R)
                if p.x < table.headString - R && isFreeSpot(p, except: 0) {
                    balls[0] = Ball()
                    balls[0].p = p
                    return
                }
            }
        }
    }

    private mutating func setBall(_ ball: Int, at p: V2, random: inout RandomSource) {
        balls[ball] = Ball()
        balls[ball].p = p
        let w = random.normal()
        let x = random.normal()
        let y = random.normal()
        let z = random.normal()
        let n = (w * w + x * x + y * y + z * z).squareRoot()
        balls[ball].q = Quat(w: w / n, x: x / n, y: y / n, z: z / n)
    }

    /// No rack is perfect: the balls are a fraction of a millimetre off their places. Without that the break would
    /// pass straight through rows lined up exactly, and leave most of the rack where it stood.
    private mutating func loosen(random: inout RandomSource) {
        let deviation = 0.0003 * table.ballRadius / 0.028575
        for i in 1..<count {
            let dx = random.normal(deviation: deviation)
            let dz = random.normal(deviation: deviation)
            balls[i].p = balls[i].p + V2(dx, dz)
        }
    }
}
