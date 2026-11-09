import Foundation

/// The balls on a table, moved on by an event-driven simulation in double precision: every collision is found at
/// its exact time, so fast balls never pass through each other or a cushion. The balls slide and roll on the cloth
/// with spin, meet each other with throw, and strike the cushions above their middles.
struct Simulation: Sendable {
    static let maxBalls = 16
    static let gravity = 9.81
    /// The longest stretch of motion between looks for contacts.
    static let step = 0.005

    let table: TableSpec
    var balls = [Ball](repeating: Ball(), count: Simulation.maxBalls)
    var count = 0
    var time: Double = 0
    /// Keep the orientations up to date, for drawing.
    var turnBalls = true

    init(table: TableSpec) {
        self.table = table
    }

    var isMoving: Bool {
        let R = table.ballRadius
        for i in 0..<count where Self.isMoving(balls[i], radius: R) {
            return true
        }
        return false
    }

    /// A cue strikes `ball` along `direction` at `speed` (of the ball, m/s), `side` to the right of the middle and
    /// `vertical` above it, both as fractions of the radius.
    mutating func strike(_ ball: Int, direction: V2, speed: Double, side: Double, vertical: Double) {
        let R = table.ballRadius
        let d = direction.normalized
        let d3 = V3(flat: d)
        let right = d3.cross(V3(0, 1, 0))
        balls[ball].v = d * speed
        // The cue's push along d at the point struck, ω = r × J / I with I = 2/5 m R²: above the middle, topspin;
        // to the right of it, spin to the right.
        let struck = right * (side * R) + V3(0, vertical * R, 0)
        balls[ball].w = struck.cross(d3) * (2.5 * speed / (R * R))
    }

    /// Moves the balls on by `seconds`, noting what happens.
    mutating func advance(_ seconds: Double, events: inout [Event]) {
        var remaining = seconds
        var contacts = 0
        while remaining > 1e-12 && isMoving {
            var h = min(remaining, Self.step)
            while h > 1e-12 {
                let contact = findContact(within: h)
                let t = contact.kind < 0 ? h : contact.t
                moveAll(by: t)
                time += t
                remaining -= t
                h -= t
                switch contact.kind {
                case 0:
                    collide(contact.a, contact.b, events: &events)
                case 1:
                    bounce(contact.a, normal: table.segments[contact.b].normal, events: &events)
                case 2:
                    bounce(contact.a, normal: (balls[contact.a].p - table.tips[contact.b].center).normalized, events: &events)
                case 3:
                    drop(contact.a, into: contact.b, events: &events)
                default:
                    break
                }
                // A pile of contacts at one instant is worked through one by one; a runaway is cut short.
                if contact.kind >= 0 {
                    contacts += 1
                    if contacts > 2000 {
                        moveAll(by: h)
                        time += h
                        remaining -= h
                        h = 0
                    }
                }
            }
        }
        if !isMoving {
            for i in 0..<count where balls[i].onTable {
                balls[i].w = .zero
            }
        }
    }

    /// Until every ball lies still, or the limit.
    mutating func run(events: inout [Event], limit: Double = 40) {
        let end = time + limit
        while isMoving && time < end {
            advance(0.5, events: &events)
        }
    }

    /// A ball placed at `p` would touch no other and stay on the cloth.
    func isFreeSpot(_ p: V2, except: Int) -> Bool {
        if !table.onCloth(p) {
            return false
        }
        let R = table.ballRadius
        for i in 0..<count where i != except && balls[i].onTable && (balls[i].p - p).length < 2 * R + 1e-4 {
            return false
        }
        return true
    }

    // MARK: - The motion

    static func isMoving(_ ball: Ball, radius R: Double) -> Bool {
        if !ball.onTable {
            return false
        }
        let slip = V2(ball.v.x + R * ball.w.z, ball.v.z - R * ball.w.x)
        return ball.v.dot(ball.v) > 1e-18 || slip.dot(slip) > 1e-12
    }

    /// Sliding, the friction of the cloth turns the slip of the contact point into rolling; rolling, the ball slows
    /// gently to a stop. Each stage has constant accelerations, so it is followed exactly.
    private static func move(_ ball: inout Ball, by time: Double, table s: TableSpec, turning: Bool) {
        let R = s.ballRadius
        let g = gravity
        var t = time
        while t > 1e-12 {
            let slip = V2(ball.v.x + R * ball.w.z, ball.v.z - R * ball.w.x)
            let slipSpeed = slip.length
            let speed = ball.v.length
            let before = ball.w
            var h = t
            var still = false
            if slipSpeed > 1e-6 {
                let direction = slip * (1 / slipSpeed)
                let toRoll = slipSpeed / (3.5 * s.slideFriction * g)
                h = min(t, toRoll)
                let acceleration = direction * (-s.slideFriction * g)
                let angular = 2.5 * s.slideFriction * g / R
                ball.p = ball.p + ball.v * h + acceleration * (0.5 * h * h)
                ball.v = ball.v + acceleration * h
                ball.w.x += angular * direction.z * h
                ball.w.z -= angular * direction.x * h
                if h >= toRoll {
                    ball.w.x = ball.v.z / R
                    ball.w.z = -ball.v.x / R
                }
            } else if speed > 1e-9 {
                let direction = ball.v * (1 / speed)
                let toStop = speed / (s.rollFriction * g)
                h = min(t, toStop)
                let acceleration = direction * (-s.rollFriction * g)
                ball.p = ball.p + ball.v * h + acceleration * (0.5 * h * h)
                ball.v = h >= toStop ? .zero : ball.v + acceleration * h
                ball.w.x = ball.v.z / R
                ball.w.z = -ball.v.x / R
            } else {
                ball.v = .zero
                ball.w.x = 0
                ball.w.z = 0
                still = true
            }
            // Spin about the vertical wears away on its own.
            let wear = s.spinDeceleration * h
            ball.w.y = abs(ball.w.y) <= wear ? 0 : ball.w.y - Double(signOf: ball.w.y, magnitudeOf: wear)
            if turning {
                let mean = (before + ball.w) * 0.5
                let rate = mean.length
                if rate > 1e-9 {
                    ball.q = ball.q.turned(about: mean * (1 / rate), by: rate * h)
                }
            }
            t -= h
            if still {
                break
            }
        }
    }

    private mutating func moveAll(by t: Double) {
        let table = self.table
        let turning = turnBalls
        for i in 0..<count where balls[i].onTable {
            Self.move(&balls[i], by: t, table: table, turning: turning)
        }
    }
}
