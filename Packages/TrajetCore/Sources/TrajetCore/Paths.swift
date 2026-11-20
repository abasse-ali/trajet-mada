import Foundation

/// Suite de lieux reliés par des liaisons (indices dans `FilteredNetwork.connections`).
public struct RoutePath: Sendable, Hashable {
    public let places: [PlaceID]
    public let connections: [Int]

    public var origin: PlaceID { places[0] }
    public var end: PlaceID { places[places.count - 1] }
    public var signature: String { places.map(\.rawValue).joined(separator: ">") }

    public func reversed() -> RoutePath {
        RoutePath(places: Array(places.reversed()), connections: Array(connections.reversed()))
    }
}

/// Réseau limité aux moyens de transport choisis.
public struct FilteredNetwork: Sendable {
    public let connections: [Connection]

    public init(params: SearchParams, all: [Connection] = NetworkData.connections) {
        connections = all.compactMap { connection in
            let options = connection.options.filter { option in
                (option.mode == .local || params.modes.contains(option.mode))
                    && (params.includeUnverified || option.verified)
            }
            guard !options.isEmpty else { return nil }
            return Connection(id: connection.id, a: connection.a, b: connection.b, options: options)
        }
    }

    /// Tous les trajets aller de `start` vers une des `targets`, sans repasser par un lieu
    /// et sans revenir vers Toulouse (niveau d'éloignement croissant ou égal).
    public func outboundPaths(from start: PlaceID, to targets: Set<PlaceID>, maxSteps: Int = 7) -> [RoutePath] {
        var adjacency: [PlaceID: [(Int, PlaceID)]] = [:]
        for (index, connection) in connections.enumerated() {
            adjacency[connection.a, default: []].append((index, connection.b))
            adjacency[connection.b, default: []].append((index, connection.a))
        }
        var results: [RoutePath] = []
        var places: [PlaceID] = [start]
        var used: [Int] = []
        var visited: Set<PlaceID> = [start]

        func walk(_ at: PlaceID) {
            if !used.isEmpty && targets.contains(at) {
                results.append(RoutePath(places: places, connections: used))
                return
            }
            if used.count >= maxSteps { return }
            let tier = NetworkData.place(at).tier
            for (index, next) in adjacency[at] ?? [] {
                if visited.contains(next) { continue }
                if NetworkData.place(next).tier < tier { continue }
                visited.insert(next)
                places.append(next)
                used.append(index)
                walk(next)
                visited.remove(next)
                places.removeLast()
                used.removeLast()
            }
        }
        walk(start)
        return results
    }

    /// Chemin le moins cher (prix courant estimé) entre deux lieux, pour se déplacer pendant le séjour.
    public func cheapestTransfer(from: PlaceID, to: PlaceID, adults: Int) -> (cost: Double, places: [PlaceID], connections: [Int])? {
        if from == to { return (0, [from], []) }
        var best: [PlaceID: Double] = [from: 0]
        var previous: [PlaceID: (PlaceID, Int)] = [:]
        var queue: Set<PlaceID> = [from]
        while let current = queue.min(by: { (best[$0] ?? .infinity) < (best[$1] ?? .infinity) }) {
            queue.remove(current)
            if current == to { break }
            let base = best[current] ?? .infinity
            for (index, connection) in connections.enumerated() {
                guard let next = connection.other(current) else { continue }
                let cost = connection.options.map { option in
                    option.priceTypical * (option.perVehicle ? 1 : Double(adults))
                }.min() ?? .infinity
                if base + cost < (best[next] ?? .infinity) {
                    best[next] = base + cost
                    previous[next] = (current, index)
                    queue.insert(next)
                }
            }
        }
        guard let total = best[to] else { return nil }
        var places: [PlaceID] = [to]
        var used: [Int] = []
        var cursor = to
        while let step = previous[cursor] {
            places.insert(step.0, at: 0)
            used.insert(step.1, at: 0)
            cursor = step.0
            if cursor == from { break }
        }
        return (total, places, used)
    }
}
