/// The contacts: when the next one comes, and what it does to the balls.
extension Simulation {
    struct Contact {
        var t: Double
        /// 0 a ball, 1 a cushion's segment, 2 a jaw's tip, 3 a pocket; -1 none.
        var kind = -1
        var a = -1
        var b = -1

        mutating func consider(_ time: Double, _ kind: Int, _ a: Int, _ b: Int) {
            if time >= 0 && time < t {
                t = time
                self.kind = kind
                self.a = a
                self.b = b
            }
        }
    }

    /// The time a point moving from `d` (relative) with `w` first comes within `radius`, if it is approaching;
    /// else -1.
    private static func meet(_ d: V2, _ w: V2, _ radius: Double) -> Double {
        let b = d.dot(w)
        if b >= 0 {
            return -1
        }
        let c = d.dot(d) - radius * radius
        if c <= 0 {
            return 0
        }
        let a = w.dot(w)
        let discriminant = b * b - a * c
        if discriminant < 0 {
            return -1
        }
        return (-b - discriminant.squareRoot()) / a
    }

    /// The first contact within `horizon`, each ball taken to move in a straight line meanwhile: over a few
    /// milliseconds the curve of its slowing is far smaller than anything that matters.
    func findContact(within horizon: Double) -> Contact {
        let s = table
        let R = s.ballRadius
        let reach = s.contactRadius
        var best = Contact(t: horizon)
        for i in 0..<count {
            let ball = balls[i]
            if !Self.isMoving(ball, radius: R) {
                continue
            }
            for j in 0..<count {
                let other = balls[j]
                if j == i || !other.onTable || (j < i && Self.isMoving(other, radius: R)) {
                    continue
                }
                best.consider(Self.meet(other.p - ball.p, other.v - ball.v, 2 * R), 0, i, j)
            }
            for (k, segment) in s.segments.enumerated() {
                let approach = ball.v.dot(segment.normal)
                if approach >= 0 {
                    continue
                }
                let distance = (ball.p - segment.a).dot(segment.normal)
                if distance < reach * 0.5 {
                    continue // behind it, or long past
                }
                let t = max(0.0, (reach - distance) / approach)
                if t >= best.t {
                    continue
                }
                let along = segment.b - segment.a
                let position = (ball.p + ball.v * t - segment.a).dot(along) / along.dot(along)
                if position >= 0 && position <= 1 {
                    best.consider(t, 1, i, k)
                }
            }
            for (k, tip) in s.tips.enumerated() {
                best.consider(Self.meet(tip.center - ball.p, -ball.v, reach + tip.radius), 2, i, k)
            }
            for (k, pocket) in s.pockets.enumerated() {
                best.consider(Self.meet(pocket.hole - ball.p, -ball.v, pocket.holeRadius), 3, i, k)
            }
        }
        return best
    }

    /// Two balls meet: the push along the line of their middles, and the friction between their surfaces, which
    /// throws the one struck off that line and passes on some spin.
    mutating func collide(_ i: Int, _ j: Int, events: inout [Event]) {
        let R = table.ballRadius
        var a = balls[i]
        var b = balls[j]
        let n = (b.p - a.p).normalized
        let approach = (a.v - b.v).dot(n)
        if approach <= 0 {
            return
        }
        // Exactly touching, should rounding have let them overlap.
        let overlap = 2 * R - (b.p - a.p).length
        if overlap > 0 {
            a.p = a.p - n * (overlap / 2)
            b.p = b.p + n * (overlap / 2)
        }
        let n3 = V3(flat: n)
        let slip = (V3(flat: a.v) + a.w.cross(n3 * R)) - (V3(flat: b.v) + b.w.cross(n3 * -R))
        let tangential = slip - n3 * slip.dot(n3)
        let impulse = (1 + table.ballRestitution) / 2 * approach
        a.v = a.v - n * impulse
        b.v = b.v + n * impulse
        let slipSpeed = tangential.length
        if slipSpeed > 1e-9 {
            let friction = min(table.ballFriction * impulse, slipSpeed / 7)
            let along = tangential * (friction / slipSpeed)
            a.v = a.v - along.horizontal
            b.v = b.v + along.horizontal
            let turn = 2.5 / (R * R)
            a.w = a.w + (n3 * R).cross(along * -1.0) * turn
            b.w = b.w + (n3 * -R).cross(along) * turn
        }
        balls[i] = a
        balls[j] = b
        events.append(Event(kind: .ballBall, a: i, b: j, speed: approach, time: time))
    }

    /// A ball meets a cushion's nose a little above its middle: the cushion pushes it back toward the cloth, and its
    /// friction acts on the ball's slip there, so that spin changes the angle it comes off at.
    mutating func bounce(_ i: Int, normal: V2, events: inout [Event]) {
        let s = table
        let R = s.ballRadius
        var ball = balls[i]
        let approach = -ball.v.dot(normal)
        if approach <= 0 {
            return
        }
        let lift = (s.cushionHeight - R) / R
        let level = (1 - lift * lift).squareRoot()
        let n3 = V3(flat: normal)
        let toContact = n3 * (-R * level) + V3(0, R * lift, 0)
        let inward = n3 * level + V3(0, -lift, 0) // from the cushion into the ball
        let restitution = min(max(s.cushionRestitution - 0.025 * approach, 0.62), s.cushionRestitution)
        let push = (1 + restitution) * approach / level
        let slip = V3(flat: ball.v) + ball.w.cross(toContact)
        let tangential = slip - inward * slip.dot(inward)
        var impulse = inward * push
        let slipSpeed = tangential.length
        if slipSpeed > 1e-9 {
            let friction = min(s.cushionFriction * push, slipSpeed * 2 / 7)
            let along = tangential * (-friction / slipSpeed)
            impulse = impulse + along
            ball.w = ball.w + toContact.cross(along) * (2.5 / (R * R))
        }
        ball.v = ball.v + impulse.horizontal
        // Never back into the cushion, whatever the friction did.
        let away = ball.v.dot(normal)
        if away < 0 {
            ball.v = ball.v - normal * away
        }
        balls[i] = ball
        events.append(Event(kind: .cushion, a: i, b: -1, speed: approach, time: time))
    }

    mutating func drop(_ i: Int, into pocket: Int, events: inout [Event]) {
        balls[i].state = .pocketed
        balls[i].pocket = pocket
        events.append(Event(kind: .pocket, a: i, b: pocket, speed: balls[i].v.length, time: time))
    }
}
