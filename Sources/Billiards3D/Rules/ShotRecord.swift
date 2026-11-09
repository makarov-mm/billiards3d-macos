/// What a stroke did, from the events of its simulation.
struct ShotRecord: Sendable {
    var struck = 0
    /// The first ball the struck ball touched.
    var firstContact = -1
    /// A ball met a cushion after that.
    var railAfterContact = false
    /// Where the eight is to go, in eight-ball.
    var calledPocket = -1
    /// Ball and pocket, in order.
    var pocketed: [(ball: Int, pocket: Int)] = []

    init(struck: Int, events: [Event], calledPocket: Int) {
        self.struck = struck
        self.calledPocket = calledPocket
        for event in events {
            switch event.kind {
            case .ballBall:
                if firstContact < 0 && (event.a == struck || event.b == struck) {
                    firstContact = event.a == struck ? event.b : event.a
                }
            case .cushion:
                if firstContact >= 0 {
                    railAfterContact = true
                }
            case .pocket:
                pocketed.append((event.a, event.b))
            }
        }
    }

    func isPocketed(_ ball: Int) -> Bool { pocketed.contains { $0.ball == ball } }

    func pocket(of ball: Int) -> Int { pocketed.first { $0.ball == ball }?.pocket ?? -1 }
}
