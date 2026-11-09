/// A stroke played out on a copy of the table.
extension Simulation {
    /// The events and where the balls stop.
    func played(_ shot: Shot, events: inout [Event]) -> Simulation {
        var sim = self
        sim.turnBalls = false
        sim.time = 0
        if shot.place {
            sim.balls[shot.struck] = Ball()
            sim.balls[shot.struck].p = shot.spot
        }
        sim.strike(shot.struck, direction: shot.direction, speed: shot.speed, side: shot.side, vertical: shot.vertical)
        sim.run(events: &events)
        return sim
    }
}
