import UIKit

class CFGViewController: UIViewController {
    
    // MARK: - Properties
    
    private let cfgAnalysis: CFGAnalysisResult
    private var currentCFG: FunctionCFG?
    private var searchText: String = ""
    
    // MARK: - UI Elements
    
    private let searchBar: UISearchBar = {
        let search = UISearchBar()
        search.translatesAutoresizingMaskIntoConstraints = false
        search.placeholder = "Search functions..."
        search.searchBarStyle = .minimal
        return search
    }()
    
    private let statsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()
    
    private let functionTableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = Constants.Colors.primaryBackground
        table.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        return table
    }()
    
    private let graphScrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.backgroundColor = Constants.Colors.primaryBackground
        scroll.minimumZoomScale = 0.5
        scroll.maximumZoomScale = 3.0
        return scroll
    }()
    
    private let graphView: CFGGraphView = {
        let view = CFGGraphView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = Constants.Colors.primaryBackground
        return view
    }()
    
    private var displayedFunctions: [FunctionCFG] = []
    private var isShowingGraph = false
    
    // MARK: - Initialization
    
    init(cfgAnalysis: CFGAnalysisResult) {
        self.cfgAnalysis = cfgAnalysis
        self.displayedFunctions = cfgAnalysis.functionCFGs
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Control Flow Graphs"
        view.backgroundColor = Constants.Colors.primaryBackground
        
        setupUI()
        setupTableView()
        updateStats()
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "List",
            style: .plain,
            target: self,
            action: #selector(toggleView)
        )
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.addSubview(searchBar)
        view.addSubview(statsLabel)
        view.addSubview(functionTableView)
        view.addSubview(graphScrollView)
        
        graphScrollView.addSubview(graphView)
        graphScrollView.delegate = self
        
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            statsLabel.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 8),
            statsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statsLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            functionTableView.topAnchor.constraint(equalTo: statsLabel.bottomAnchor, constant: 8),
            functionTableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            functionTableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            functionTableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            graphScrollView.topAnchor.constraint(equalTo: statsLabel.bottomAnchor, constant: 8),
            graphScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            graphScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            graphScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            graphView.topAnchor.constraint(equalTo: graphScrollView.topAnchor),
            graphView.leadingAnchor.constraint(equalTo: graphScrollView.leadingAnchor),
            graphView.trailingAnchor.constraint(equalTo: graphScrollView.trailingAnchor),
            graphView.bottomAnchor.constraint(equalTo: graphScrollView.bottomAnchor),
            graphView.widthAnchor.constraint(equalToConstant: 2000),
            graphView.heightAnchor.constraint(equalToConstant: 2000)
        ])
        
        graphScrollView.isHidden = true
    }
    
    private func setupTableView() {
        functionTableView.delegate = self
        functionTableView.dataSource = self
        searchBar.delegate = self
    }
    
    // MARK: - Data Management
    
    private func updateStats() {
        statsLabel.text = "\(displayedFunctions.count) functions • \(cfgAnalysis.totalNodes) nodes • \(cfgAnalysis.totalEdges) edges"
    }
    
    private func filterFunctions() {
        displayedFunctions = cfgAnalysis.cfgs(matching: searchText)
        updateStats()
        functionTableView.reloadData()
    }
    
    @objc private func toggleView() {
        isShowingGraph.toggle()
        
        if isShowingGraph {
            navigationItem.rightBarButtonItem?.title = "List"
            graphScrollView.isHidden = false
            functionTableView.isHidden = true
        } else {
            navigationItem.rightBarButtonItem?.title = "Graph"
            graphScrollView.isHidden = true
            functionTableView.isHidden = false
        }
    }
    
    private func showGraph(for cfg: FunctionCFG) {
        currentCFG = cfg
        
        let layoutBounds = CGRect(x: 0, y: 0, width: 800, height: 800)
        let contentSize = CFGLayout.hierarchicalLayout(cfg: cfg, bounds: layoutBounds)
        
        graphView.frame = CGRect(origin: .zero, size: contentSize)
        graphScrollView.contentSize = contentSize
        graphView.configure(with: cfg)
        
        if !isShowingGraph {
            toggleView()
        }
        
        graphScrollView.minimumZoomScale = 0.05
        graphScrollView.maximumZoomScale = 3.0
        
        let viewWidth = max(graphScrollView.bounds.width, 1)
        let viewHeight = max(graphScrollView.bounds.height, 1)
        let scaleToFitWidth = viewWidth / max(contentSize.width, 1)
        let scaleToFitHeight = viewHeight / max(contentSize.height, 1)
        let initialZoom = min(min(scaleToFitWidth, scaleToFitHeight), 1.0)
        let clampedZoom = max(min(initialZoom, graphScrollView.maximumZoomScale), graphScrollView.minimumZoomScale)
        graphScrollView.zoomScale = clampedZoom
        
        let edgeInset: CGFloat = 20
        graphScrollView.contentInset = UIEdgeInsets(top: edgeInset, left: edgeInset, bottom: edgeInset, right: edgeInset)
        
        graphScrollView.scrollIndicatorInsets = graphScrollView.contentInset
        
        let topLeftOffset = CGPoint(x: -edgeInset, y: -edgeInset)
        graphScrollView.setContentOffset(topLeftOffset, animated: false)
    }
}

// MARK: - UITableViewDataSource

extension CFGViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return displayedFunctions.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let cfg = displayedFunctions[indexPath.row]
        
        cell.textLabel?.text = cfg.functionName
        cell.detailTextLabel?.text = "\(cfg.nodeCount) nodes, \(cfg.edgeCount) edges"
        cell.accessoryType = .disclosureIndicator
        
        return cell
    }
}

// MARK: - UITableViewDelegate

extension CFGViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let cfg = displayedFunctions[indexPath.row]
        showGraph(for: cfg)
    }
}

// MARK: - UISearchBarDelegate

extension CFGViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        self.searchText = searchText
        filterFunctions()
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

// MARK: - UIScrollViewDelegate

extension CFGViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return graphView
    }
}

// MARK: - CFG Graph View

class CFGGraphView: UIView {
    
    private var cfg: FunctionCFG?
    
    func configure(with cfg: FunctionCFG) {
        self.cfg = cfg
        setNeedsDisplay()
    }
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        
        guard let cfg = cfg, let context = UIGraphicsGetCurrentContext() else { return }
        
        context.setLineWidth(2.0)
        for edge in cfg.edges {
            guard let fromNode = cfg.node(withID: edge.from),
                  let toNode = cfg.node(withID: edge.to) else { continue }
            
            let color: UIColor
            switch edge.edgeType {
            case .trueBranch: color = .systemGreen
            case .falseBranch: color = .systemRed
            case .loopBack: color = .systemOrange
            default: color = .systemGray
            }
            
            color.setStroke()
            
            let startPoint = CGPoint(
                x: fromNode.position.x,
                y: fromNode.position.y + fromNode.size.height / 2
            )
            let endPoint = CGPoint(
                x: toNode.position.x,
                y: toNode.position.y - toNode.size.height / 2
            )
            
            context.move(to: startPoint)
            context.addLine(to: endPoint)
            context.strokePath()
            
            drawArrow(context: context, from: startPoint, to: endPoint, color: color)
        }
        
        for node in cfg.nodes {
            let rect = CGRect(
                x: node.position.x - node.size.width / 2,
                y: node.position.y - node.size.height / 2,
                width: node.size.width,
                height: node.size.height
            )
            
            let nodeColor: UIColor
            switch node.nodeType {
            case .entry: nodeColor = Constants.Colors.accentColor
            case .exit: nodeColor = .systemRed
            case .conditional: nodeColor = .systemOrange
            default: nodeColor = Constants.Colors.secondaryBackground
            }
            
            nodeColor.setFill()
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 8)
            path.fill()
            UIColor.label.setStroke()
            path.lineWidth = 2
            path.stroke()
            
            let text = "\(node.addressRange)\n\(node.instructionCount) instructions"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: UIColor.label
            ]
            let textRect = rect.insetBy(dx: 8, dy: 8)
            text.draw(in: textRect, withAttributes: attrs)
        }
    }
    
    private func drawArrow(context: CGContext, from: CGPoint, to: CGPoint, color: UIColor) {
        let arrowSize: CGFloat = 10
        let angle = atan2(to.y - from.y, to.x - from.x)
        
        let arrowPoint1 = CGPoint(
            x: to.x - arrowSize * cos(angle - .pi / 6),
            y: to.y - arrowSize * sin(angle - .pi / 6)
        )
        let arrowPoint2 = CGPoint(
            x: to.x - arrowSize * cos(angle + .pi / 6),
            y: to.y - arrowSize * sin(angle + .pi / 6)
        )
        
        color.setFill()
        context.move(to: to)
        context.addLine(to: arrowPoint1)
        context.addLine(to: arrowPoint2)
        context.closePath()
        context.fillPath()
    }
}

