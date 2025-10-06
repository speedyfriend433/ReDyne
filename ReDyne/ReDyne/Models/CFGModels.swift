import Foundation
import UIKit

// MARK: - CFG Node

@objc class CFGNode: NSObject {
    @objc let id: Int
    @objc let startAddress: UInt64
    @objc let endAddress: UInt64
    @objc let instructions: [String]
    @objc var successors: [Int] = []
    @objc var nodeType: CFGNodeType = .normal
    
    var position: CGPoint = .zero
    var size: CGSize = CGSize(width: 200, height: 80)
    
    init(id: Int, startAddress: UInt64, endAddress: UInt64, instructions: [String]) {
        self.id = id
        self.startAddress = startAddress
        self.endAddress = endAddress
        self.instructions = instructions
        super.init()
    }
    
    @objc var addressRange: String {
        return String(format: "0x%llX - 0x%llX", startAddress, endAddress)
    }
    
    @objc var instructionCount: Int {
        return instructions.count
    }
    
    @objc var displayInstructions: String {
        return instructions.prefix(3).joined(separator: "\n")
    }
}

@objc enum CFGNodeType: Int {
    case normal = 0
    case entry = 1
    case exit = 2
    case conditional = 3
    case loop = 4
}

// MARK: - CFG Edge

@objc class CFGEdge: NSObject {
    @objc let from: Int
    @objc let to: Int
    @objc let edgeType: CFGEdgeType
    
    init(from: Int, to: Int, edgeType: CFGEdgeType) {
        self.from = from
        self.to = to
        self.edgeType = edgeType
        super.init()
    }
    
    @objc var isConditional: Bool {
        return edgeType == .trueBranch || edgeType == .falseBranch
    }
}

@objc enum CFGEdgeType: Int {
    case normal = 0
    case trueBranch = 1
    case falseBranch = 2
    case loopBack = 3
}

// MARK: - Function CFG

@objc class FunctionCFG: NSObject {
    @objc let functionName: String
    @objc let functionAddress: UInt64
    @objc let nodes: [CFGNode]
    @objc let edges: [CFGEdge]
    
    init(functionName: String, functionAddress: UInt64, nodes: [CFGNode], edges: [CFGEdge]) {
        self.functionName = functionName
        self.functionAddress = functionAddress
        self.nodes = nodes
        self.edges = edges
        super.init()
    }
    
    @objc var nodeCount: Int { nodes.count }
    @objc var edgeCount: Int { edges.count }
    
    @objc var entryNode: CFGNode? {
        return nodes.first { $0.nodeType == .entry } ?? nodes.first
    }
    
    @objc var exitNodes: [CFGNode] {
        return nodes.filter { $0.nodeType == .exit }
    }
    
    @objc func node(withID id: Int) -> CFGNode? {
        return nodes.first { $0.id == id }
    }
    
    @objc func edges(from nodeID: Int) -> [CFGEdge] {
        return edges.filter { $0.from == nodeID }
    }
    
    @objc func edges(to nodeID: Int) -> [CFGEdge] {
        return edges.filter { $0.to == nodeID }
    }
}

// MARK: - CFG Analysis Result

@objc class CFGAnalysisResult: NSObject {
    @objc let functionCFGs: [FunctionCFG]
    
    init(functionCFGs: [FunctionCFG]) {
        self.functionCFGs = functionCFGs
        super.init()
    }
    
    @objc var totalFunctions: Int { functionCFGs.count }
    @objc var totalNodes: Int { functionCFGs.reduce(0) { $0 + $1.nodeCount } }
    @objc var totalEdges: Int { functionCFGs.reduce(0) { $0 + $1.edgeCount } }
    
    @objc func cfg(forFunction name: String) -> FunctionCFG? {
        return functionCFGs.first { $0.functionName == name }
    }
    
    @objc func cfgs(matching query: String) -> [FunctionCFG] {
        guard !query.isEmpty else { return functionCFGs }
        let lowercased = query.lowercased()
        return functionCFGs.filter { $0.functionName.lowercased().contains(lowercased) }
    }
}

// MARK: - Graph Layout Algorithm

class CFGLayout {
    static func hierarchicalLayout(cfg: FunctionCFG, bounds: CGRect) -> CGSize {
        guard let entry = cfg.entryNode else { 
            return CGSize(width: bounds.width, height: bounds.height)
        }
        
        let padding: CGFloat = 120
        let levelSpacing: CGFloat = 150
        let nodeSpacing: CGFloat = 40
        
        var levels: [[CFGNode]] = []
        var visited: Set<Int> = []
        var queue: [(CFGNode, Int)] = [(entry, 0)]
        var maxLevel = 0
        
        while !queue.isEmpty {
            let (node, level) = queue.removeFirst()
            if visited.contains(node.id) { continue }
            visited.insert(node.id)
            
            maxLevel = max(maxLevel, level)
            while levels.count <= level {
                levels.append([])
            }
            levels[level].append(node)
            
            for edge in cfg.edges(from: node.id) {
                if let successor = cfg.node(withID: edge.to) {
                    queue.append((successor, level + 1))
                }
            }
        }
        
        var maxWidth: CGFloat = 0
        for nodesInLevel in levels {
            let levelWidth = CGFloat(nodesInLevel.count) * 220 + CGFloat(max(0, nodesInLevel.count - 1)) * nodeSpacing
            maxWidth = max(maxWidth, levelWidth)
        }
        
        for (level, nodesInLevel) in levels.enumerated() {
            let nodeWidth: CGFloat = 220
            let nodeHeight: CGFloat = 100
            
            for node in nodesInLevel {
                let instructionCount = node.instructions.count
                let calculatedHeight = max(100, CGFloat(min(instructionCount, 5)) * 20 + 40)
                node.size = CGSize(width: nodeWidth, height: calculatedHeight)
            }
            
            let levelWidth = CGFloat(nodesInLevel.count) * nodeWidth + CGFloat(max(0, nodesInLevel.count - 1)) * nodeSpacing
            var startX = (maxWidth - levelWidth) / 2 + padding
            
            for node in nodesInLevel {
                let yPosition = padding + node.size.height / 2 + CGFloat(level) * levelSpacing
                
                node.position = CGPoint(
                    x: startX + node.size.width / 2,
                    y: yPosition
                )
                startX += node.size.width + nodeSpacing
            }
        }
        
        var minX: CGFloat = .greatestFiniteMagnitude
        var maxX: CGFloat = 0
        var minY: CGFloat = .greatestFiniteMagnitude
        var maxY: CGFloat = 0
        
        for node in cfg.nodes {
            let nodeLeft = node.position.x - node.size.width / 2
            let nodeRight = node.position.x + node.size.width / 2
            let nodeTop = node.position.y - node.size.height / 2
            let nodeBottom = node.position.y + node.size.height / 2
            
            minX = min(minX, nodeLeft)
            maxX = max(maxX, nodeRight)
            minY = min(minY, nodeTop)
            maxY = max(maxY, nodeBottom)
        }
        
        for edge in cfg.edges {
            guard let fromNode = cfg.node(withID: edge.from),
                  let toNode = cfg.node(withID: edge.to) else { continue }
            
            let startX = fromNode.position.x
            let startY = fromNode.position.y + fromNode.size.height / 2
            let endX = toNode.position.x
            let endY = toNode.position.y - toNode.size.height / 2
            
            minX = min(minX, startX, endX)
            maxX = max(maxX, startX, endX)
            minY = min(minY, startY, endY)
            maxY = max(maxY, startY, endY)
        }
        
        let extraPadding: CGFloat = 80
        let xShift = max(0, padding - minX)
        let yShift = max(0, padding - minY)
        
        if xShift > 0 || yShift > 0 {
            for node in cfg.nodes {
                node.position.x += xShift
                node.position.y += yShift
            }
            minX += xShift
            maxX += xShift
            minY += yShift
            maxY += yShift
        }
        
        let totalWidth = maxX + padding + extraPadding
        let totalHeight = maxY + padding + extraPadding
        
        return CGSize(
            width: max(totalWidth, 400),
            height: max(totalHeight, 400)
        )
    }
}

