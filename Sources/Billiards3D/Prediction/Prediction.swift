/// Where a stroke would send the balls, for the lines of the aim: the struck ball's path to the first ball it meets,
/// and how both go on from there. Found by playing the stroke out on a copy of the table.
struct Prediction: Sendable {
    /// The struck ball, up to the first ball it meets, where it stops or where it drops.
    var path: [V2] = []
    /// The first ball it meets.
    var hit = -1
    /// The struck ball's middle as it meets it: the ghost ball.
    var contact = V2.zero
    /// The struck ball after that, as far as `reachAfter`.
    var after: [V2] = []
    /// The ball met, as far as `reachObject` or its first cushion.
    var object: [V2] = []
    /// The pocket the ball met drops into, before it touches anything else.
    var objectPocket = -1
    /// The pocket the struck ball drops into before it meets a ball.
    var struckPocket = -1

    private static let step = 0.005

    static func predict(_ position: Simulation, struck: Int, direction: V2, speed: Double, side: Double, vertical: Double,
                        reachAfter: Double, reachObject: Double) -> Prediction {
        var prediction = Prediction()
        var sim = position
        sim.turnBalls = false
        prediction.path.append(sim.balls[struck].p)
        sim.strike(struck, direction: direction, speed: speed, side: side, vertical: vertical)

        var events: [Event] = []
        // The events after the first contact in the step that had it.
        var rest = 0
        // Up to the first ball met.
        while prediction.hit < 0 && prediction.struckPocket < 0 && sim.isMoving && sim.time < 20 {
            var k = events.count
            sim.advance(step, events: &events)
            while k < events.count && prediction.hit < 0 && prediction.struckPocket < 0 {
                let event = events[k]
                k += 1
                if event.a != struck && !(event.kind == .ballBall && event.b == struck) {
                    continue
                }
                switch event.kind {
                case .ballBall:
                    prediction.hit = event.a == struck ? event.b : event.a
                    prediction.contact = back(sim.balls[struck], sim.time, event.time)
                    prediction.path.append(prediction.contact)
                    prediction.object.append(back(sim.balls[prediction.hit], sim.time, event.time))
                    prediction.after.append(prediction.contact)
                    rest = k
                case .cushion:
                    prediction.path.append(back(sim.balls[struck], sim.time, event.time))
                case .pocket:
                    prediction.struckPocket = event.b
                    prediction.path.append(sim.balls[struck].p)
                }
            }
            if prediction.hit < 0 && prediction.struckPocket < 0 {
                prediction.path.append(sim.balls[struck].p)
            }
        }

        if prediction.hit >= 0 {
            // Both balls on from the contact: the struck one until its next contact, the other until a cushion, a ball
            // or a pocket.
            let hit = prediction.hit
            var afterDone = false
            var objectDone = false
            func take(from first: Int) {
                for event in events[first...] {
                    let struckEvent = event.a == struck || (event.kind == .ballBall && event.b == struck)
                    let hitEvent = event.a == hit || (event.kind == .ballBall && event.b == hit)
                    if struckEvent && !afterDone {
                        prediction.after.append(event.kind == .pocket ? sim.balls[struck].p : back(sim.balls[struck], sim.time, event.time))
                        afterDone = true
                    }
                    if hitEvent && !objectDone {
                        prediction.object.append(event.kind == .pocket ? sim.balls[hit].p : back(sim.balls[hit], sim.time, event.time))
                        if event.kind == .pocket {
                            prediction.objectPocket = event.b
                        }
                        objectDone = true
                    }
                }
            }
            // What followed the contact within its own step: a ball frozen to a cushion meets it at once.
            take(from: rest)
            let end = sim.time + 6
            while !(afterDone && objectDone) && sim.isMoving && sim.time < end {
                let first = events.count
                sim.advance(step, events: &events)
                take(from: first)
                if !afterDone {
                    prediction.after.append(sim.balls[struck].p)
                    afterDone = length(of: prediction.after) > reachAfter || !sim.balls[struck].onTable
                }
                if !objectDone {
                    prediction.object.append(sim.balls[hit].p)
                }
            }
        }

        prediction.path = simplify(prediction.path, 0.0015)
        prediction.after = simplify(prediction.after, 0.0015)
        clip(&prediction.after, reachAfter)
        prediction.object = simplify(prediction.object, 0.0015)
        clip(&prediction.object, reachObject)
        return prediction
    }

    /// The pocket a ball rolling from `from` along `direction` heads for: the one whose mouth lies nearest the line.
    static func pocketAlong(_ table: TableSpec, from: V2, direction: V2) -> Int {
        let d = direction.normalized
        var best = -1
        var bestScore = 1e30
        for (i, pocket) in table.pockets.enumerated() {
            let to = pocket.mouth - from
            let along = to.dot(d)
            if along <= 0 {
                continue
            }
            let score = abs(d.cross(to)) / along
            if score < bestScore {
                bestScore = score
                best = i
            }
        }
        return best
    }

    // MARK: - Helpers

    /// Leaves out the points that lie within `tolerance` of the line through their neighbours.
    private static func simplify(_ points: [V2], _ tolerance: Double) -> [V2] {
        if points.count < 3 {
            return points
        }
        var result = [points[0]]
        var anchor = 0
        for i in 2..<points.count {
            // Does the chord from the anchor to i pass near every point between?
            let a = points[anchor]
            let ab = points[i] - a
            let length = ab.length
            var straight = true
            var k = anchor + 1
            while k < i && straight {
                let off = length > 1e-9 ? abs(ab.cross(points[k] - a)) / length : (points[k] - a).length
                straight = off < tolerance
                k += 1
            }
            if !straight {
                result.append(points[i - 1])
                anchor = i - 1
            }
        }
        result.append(points[points.count - 1])
        return result
    }

    private static func length(of points: [V2]) -> Double {
        var length = 0.0
        for i in stride(from: 1, to: points.count, by: 1) {
            length += (points[i] - points[i - 1]).length
        }
        return length
    }

    /// Cuts a path off once it is `reach` long.
    private static func clip(_ points: inout [V2], _ reach: Double) {
        var length = 0.0
        for i in stride(from: 1, to: points.count, by: 1) {
            let segment = (points[i] - points[i - 1]).length
            if length + segment >= reach {
                let t = segment > 1e-12 ? (reach - length) / segment : 0
                points[i] = points[i - 1] + (points[i] - points[i - 1]) * t
                points.removeSubrange((i + 1)...)
                return
            }
            length += segment
        }
    }

    /// Where a ball was at an event in the step just taken, from where it is now and how it moves since.
    private static func back(_ ball: Ball, _ now: Double, _ time: Double) -> V2 {
        ball.onTable ? ball.p - ball.v * (now - time) : ball.p
    }
}
