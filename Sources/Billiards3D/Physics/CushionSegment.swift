/// A straight piece of cushion: a ball's middle keeps the contact radius away from it. The normal points into the
/// table.
struct CushionSegment: Sendable {
    var a: V2
    var b: V2
    var normal: V2
}
