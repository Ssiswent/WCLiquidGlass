import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let controller = MirrorViewController()
        let navigationController = UINavigationController(rootViewController: controller)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

private struct MirrorTab {
    let title: String
    let symbol: String
}

private struct MirrorAction {
    let id: String
    let title: String
    let symbol: String
}

private struct MirrorHeader {
    let title: String
    let wechatID: String
    let wxid: String
}

private final class MorphingStore {
    var tabs: [MirrorTab] = [
        MirrorTab(title: "微信", symbol: "bubble.left.fill"),
        MirrorTab(title: "通讯录", symbol: "person.2.fill"),
        MirrorTab(title: "发现", symbol: "safari.fill"),
        MirrorTab(title: "我", symbol: "person.crop.circle.fill")
    ]
    var actions: [MirrorAction] = [
        MirrorAction(id: "moments", title: "朋友圈", symbol: "circle.grid.3x3.fill"),
        MirrorAction(id: "wcglass", title: "WCGlass", symbol: "drop.fill"),
        MirrorAction(id: "liquid", title: "WCLiquidGlass", symbol: "circle.hexagongrid.fill"),
        MirrorAction(id: "plugins", title: "插件列表", symbol: "puzzlepiece.fill"),
        MirrorAction(id: "camera", title: "拍摄", symbol: "camera.fill"),
        MirrorAction(id: "photos", title: "照片", symbol: "photo.fill"),
        MirrorAction(id: "video", title: "视频通话", symbol: "video.fill"),
        MirrorAction(id: "search", title: "搜索记录", symbol: "magnifyingglass"),
        MirrorAction(id: "transcribe", title: "语音转述", symbol: "mic.fill"),
        MirrorAction(id: "emoji", title: "斗图助手", symbol: "face.smiling.fill"),
        MirrorAction(id: "diagnostics", title: "页面层级诊断", symbol: "rectangle.and.text.magnifyingglass")
    ]
    var selectedIndex = 0
    var isExpanded = false
    var menuHeader = MirrorHeader(title: "微信", wechatID: "WeChat", wxid: "wxid_mirror")
    var heightMode = 1
    var showsTitles = true
    var hapticsEnabled = true
    var fontScale: CGFloat = 1
    var searchEnabled = true
    var enabledActionIDs = Set<String>(["moments", "wcglass", "liquid", "plugins", "camera", "photos", "video", "search", "transcribe", "emoji", "diagnostics"])

    var onTabSelected: ((Int) -> Void)?
    var onActionSelected: ((String) -> Void)?
    var onIdentityCopy: ((String) -> Void)?
    var onExpansionChanged: ((Bool) -> Void)?
}

private final class MorphingTabBarView: UIView {
    private let store: MorphingStore
    private let dimmingView = UIButton(type: .custom)
    private let panelView = UIView()
    private let panelGlass = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let collapsedGlass = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let headerButton = UIButton(type: .system)
    private let tabStack = UIStackView()
    private let actionStack = UIStackView()
    private let actionScrollView = UIScrollView()
    private let searchField = UISearchTextField()
    private let plusButton = UIButton(type: .system)
    private let selectedTitleLabel = UILabel()
    private let eventLabel = UILabel()
    private var tabButtons: [UIButton] = []
    private var actionButtons: [UIButton] = []
    private var panelHeight: CGFloat { [238, 300, 350][min(max(store.heightMode, 0), 2)] }

    init(store: MorphingStore) {
        self.store = store
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setupView()
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        selectedTitleLabel.text = store.tabs[store.selectedIndex].title
        selectedTitleLabel.isHidden = !store.showsTitles
        headerButton.setImage(UIImage(systemName: "person.crop.circle"), for: .normal)
        headerButton.setTitle("  \(store.menuHeader.title) · \(store.menuHeader.wxid)", for: .normal)
        searchField.isHidden = !store.searchEnabled
        tabStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        tabButtons.removeAll()
        for (index, tab) in store.tabs.enumerated() {
            let button = makeTabButton(tab: tab, index: index)
            tabStack.addArrangedSubview(button)
            tabButtons.append(button)
        }
        actionStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        actionButtons.removeAll()
        for action in store.actions where store.enabledActionIDs.contains(action.id) {
            let button = makeActionButton(action: action)
            actionStack.addArrangedSubview(button)
            actionButtons.append(button)
        }
        applyFonts()
        if !store.isExpanded {
            setExpanded(false, animated: false)
        }
        setNeedsLayout()
    }

    func updateSelectedIndex(_ index: Int) {
        guard store.tabs.indices.contains(index) else { return }
        store.selectedIndex = index
        selectedTitleLabel.text = store.tabs[index].title
        for (buttonIndex, button) in tabButtons.enumerated() {
            button.tintColor = buttonIndex == index ? .label : .secondaryLabel
        }
    }

    func collapseImmediately() {
        setExpanded(false, animated: false)
    }

    private func setupView() {
        backgroundColor = .clear
        clipsToBounds = false

        dimmingView.translatesAutoresizingMaskIntoConstraints = true
        dimmingView.backgroundColor = UIColor.black.withAlphaComponent(0.08)
        dimmingView.alpha = 0
        dimmingView.addTarget(self, action: #selector(dimmingTapped), for: .touchUpInside)
        addSubview(dimmingView)

        panelView.translatesAutoresizingMaskIntoConstraints = true
        panelView.backgroundColor = .clear
        panelView.layer.cornerCurve = .continuous
        panelView.layer.cornerRadius = 28
        panelView.clipsToBounds = true
        addSubview(panelView)
        panelView.addSubview(panelGlass)
        panelGlass.translatesAutoresizingMaskIntoConstraints = false
        panelGlass.alpha = 0.98
        NSLayoutConstraint.activate([
            panelGlass.leadingAnchor.constraint(equalTo: panelView.leadingAnchor),
            panelGlass.trailingAnchor.constraint(equalTo: panelView.trailingAnchor),
            panelGlass.topAnchor.constraint(equalTo: panelView.topAnchor),
            panelGlass.bottomAnchor.constraint(equalTo: panelView.bottomAnchor)
        ])

        headerButton.translatesAutoresizingMaskIntoConstraints = true
        headerButton.contentHorizontalAlignment = .left
        headerButton.addTarget(self, action: #selector(identityTapped), for: .touchUpInside)
        panelView.addSubview(headerButton)

        tabStack.translatesAutoresizingMaskIntoConstraints = true
        tabStack.axis = .horizontal
        tabStack.alignment = .fill
        tabStack.distribution = .fillEqually
        tabStack.spacing = 4
        panelView.addSubview(tabStack)

        searchField.translatesAutoresizingMaskIntoConstraints = true
        searchField.placeholder = "搜索动作"
        searchField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
        panelView.addSubview(searchField)

        actionScrollView.translatesAutoresizingMaskIntoConstraints = true
        actionScrollView.alwaysBounceVertical = true
        panelView.addSubview(actionScrollView)
        actionStack.axis = .vertical
        actionStack.spacing = 8
        actionStack.translatesAutoresizingMaskIntoConstraints = true
        actionScrollView.addSubview(actionStack)

        selectedTitleLabel.translatesAutoresizingMaskIntoConstraints = true
        selectedTitleLabel.textColor = .secondaryLabel
        selectedTitleLabel.font = .preferredFont(forTextStyle: .caption1)
        selectedTitleLabel.textAlignment = .center
        addSubview(selectedTitleLabel)

        plusButton.translatesAutoresizingMaskIntoConstraints = true
        plusButton.setImage(UIImage(systemName: "plus"), for: .normal)
        plusButton.tintColor = .label
        plusButton.backgroundColor = .systemBackground.withAlphaComponent(0.70)
        plusButton.layer.cornerCurve = .continuous
        plusButton.layer.cornerRadius = 24
        plusButton.layer.borderWidth = 1
        plusButton.layer.borderColor = UIColor.separator.withAlphaComponent(0.45).cgColor
        plusButton.addTarget(self, action: #selector(plusTapped), for: .touchUpInside)
        addSubview(plusButton)

        collapsedGlass.translatesAutoresizingMaskIntoConstraints = true
        collapsedGlass.layer.cornerCurve = .continuous
        collapsedGlass.layer.cornerRadius = 28
        collapsedGlass.clipsToBounds = true
        addSubview(collapsedGlass)
        sendSubviewToBack(collapsedGlass)

        eventLabel.translatesAutoresizingMaskIntoConstraints = true
        eventLabel.textColor = .secondaryLabel
        eventLabel.font = .preferredFont(forTextStyle: .caption2)
        eventLabel.textAlignment = .center
        eventLabel.numberOfLines = 2
        addSubview(eventLabel)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
        plusButton.addGestureRecognizer(longPress)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped))
        doubleTap.numberOfTapsRequired = 2
        plusButton.addGestureRecognizer(doubleTap)
        plusButton.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(singleTapped)))
    }

    private func makeTabButton(tab: MirrorTab, index: Int) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: tab.symbol)
        configuration.title = tab.title
        configuration.imagePadding = 6
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4)
        button.configuration = configuration
        button.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
        button.tag = index
        button.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
        button.tintColor = index == store.selectedIndex ? .label : .secondaryLabel
        return button
    }

    private func makeActionButton(action: MirrorAction) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: action.symbol)
        configuration.title = action.title
        configuration.imagePadding = 12
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
        configuration.baseBackgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.72)
        configuration.baseForegroundColor = .label
        button.configuration = configuration
        button.contentHorizontalAlignment = .left
        button.accessibilityIdentifier = action.id
        button.addAction(UIAction { [weak self] _ in
            self?.selectAction(action)
        }, for: .touchUpInside)
        return button
    }

    private func applyFonts() {
        let scale = max(0.85, min(store.fontScale, 1.30))
        for button in tabButtons + actionButtons {
            button.titleLabel?.font = .systemFont(ofSize: 15 * scale, weight: .regular)
        }
        headerButton.titleLabel?.font = .systemFont(ofSize: 16 * scale, weight: .semibold)
    }

    private func selectAction(_ action: MirrorAction) {
        feedback()
        eventLabel.text = "动作：\(action.title)\nID：\(action.id)"
        store.onActionSelected?(action.id)
        setExpanded(false, animated: true)
    }

    private func feedback() {
        guard store.hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func setExpanded(_ expanded: Bool, animated: Bool) {
        store.isExpanded = expanded
        store.onExpansionChanged?(expanded)
        let changes = {
            self.panelView.alpha = expanded ? 1 : 0
            self.panelView.transform = expanded ? .identity : CGAffineTransform(translationX: 0, y: 18).scaledBy(x: 0.96, y: 0.96)
            self.dimmingView.alpha = expanded ? 1 : 0
            self.collapsedGlass.alpha = expanded ? 0 : 1
            self.plusButton.transform = expanded ? CGAffineTransform(rotationAngle: .pi / 4) : .identity
        }
        if animated {
            UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.84, initialSpringVelocity: 0.25, options: [.beginFromCurrentState, .allowUserInteraction], animations: changes)
        } else {
            changes()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let margin: CGFloat = 16
        let collapsedHeight: CGFloat = 56
        let collapsedFrame = CGRect(x: margin, y: bounds.height - collapsedHeight - 18, width: bounds.width - margin * 2, height: collapsedHeight)
        collapsedGlass.frame = collapsedFrame
        selectedTitleLabel.frame = CGRect(x: collapsedFrame.minX + 70, y: collapsedFrame.minY + 18, width: collapsedFrame.width - 140, height: 20)
        plusButton.frame = CGRect(x: collapsedFrame.maxX - 56, y: collapsedFrame.minY + 4, width: 48, height: 48)
        eventLabel.frame = CGRect(x: 18, y: collapsedFrame.maxY + 3, width: bounds.width - 36, height: 32)
        dimmingView.frame = bounds
        let panelFrame = CGRect(x: margin, y: max(12, collapsedFrame.minY - panelHeight - 10), width: bounds.width - margin * 2, height: panelHeight)
        panelView.frame = panelFrame
        headerButton.frame = CGRect(x: 16, y: 12, width: panelFrame.width - 32, height: 38)
        tabStack.frame = CGRect(x: 12, y: 54, width: panelFrame.width - 24, height: 44)
        searchField.frame = store.searchEnabled ? CGRect(x: 16, y: 104, width: panelFrame.width - 32, height: 36) : .zero
        let actionTop: CGFloat = store.searchEnabled ? 148 : 106
        actionScrollView.frame = CGRect(x: 10, y: actionTop, width: panelFrame.width - 20, height: panelFrame.height - actionTop - 10)
        actionStack.frame = CGRect(x: 0, y: 0, width: actionScrollView.bounds.width, height: max(actionScrollView.bounds.height, CGFloat(actionButtons.count) * 52))
        actionScrollView.contentSize = actionStack.bounds.size
    }

    @objc private func tabTapped(_ sender: UIButton) {
        updateSelectedIndex(sender.tag)
        feedback()
        store.onTabSelected?(sender.tag)
        setExpanded(false, animated: true)
    }

    @objc private func plusTapped() {
        setExpanded(!store.isExpanded, animated: true)
    }

    @objc private func singleTapped() {
        if store.isExpanded { return }
        setExpanded(true, animated: true)
    }

    @objc private func doubleTapped() {
        eventLabel.text = "加号：双击动作\n可由宿主映射到自定义操作"
        feedback()
    }

    @objc private func longPressed(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        eventLabel.text = "加号：长按动作\n可由宿主映射到自定义操作"
        feedback()
    }

    @objc private func dimmingTapped() {
        setExpanded(false, animated: true)
    }

    @objc private func identityTapped() {
        UIPasteboard.general.string = store.menuHeader.wxid
        eventLabel.text = "身份复制：\(store.menuHeader.wxid)"
        store.onIdentityCopy?(store.menuHeader.wxid)
        feedback()
    }

    @objc private func searchChanged() {
        let query = searchField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        for button in actionButtons {
            let title = button.configuration?.title ?? ""
            button.isHidden = !query.isEmpty && !title.localizedCaseInsensitiveContains(query)
        }
        setNeedsLayout()
    }
}

private final class MirrorSettingsViewController: UITableViewController {
    private let store: MorphingStore
    private weak var mirrorView: MorphingTabBarView?

    init(store: MorphingStore, mirrorView: MorphingTabBarView) {
        self.store = store
        self.mirrorView = mirrorView
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "WCGlass 镜像设置"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.rowHeight = 54
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 3 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 4 : section == 1 ? 5 : store.actions.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["WCLGMorphingTabBarView", "布局与交互", "动作回调镜像"][section]
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 { return "对应 3.0.6-3 的标签、动作、身份头和展开状态配置。" }
        if section == 1 { return "这些开关会立即重新配置预览，不修改微信或第三方插件。" }
        return "关闭动作只会从镜像菜单中隐藏，不会删除动作定义。"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.textLabel?.textColor = .label
        cell.textLabel?.text = nil
        if indexPath.section == 0 {
            let titles = ["标签数量：\(store.tabs.count)", "动作数量：\(store.actions.count)", "身份头：\(store.menuHeader.title)", "当前 Tab：\(store.tabs[store.selectedIndex].title)"]
            cell.textLabel?.text = titles[indexPath.row]
            cell.accessoryType = .disclosureIndicator
            return cell
        }
        if indexPath.section == 1 {
        let titles = ["显示标题", "启用触感", "显示搜索入口", "高度模式", "字体缩放"]
        cell.textLabel?.text = titles[indexPath.row]
            if indexPath.row == 3 {
                let mode = UISegmentedControl(items: ["紧凑", "标准", "宽松"])
                mode.selectedSegmentIndex = store.heightMode
                mode.addTarget(self, action: #selector(heightModeChanged(_:)), for: .valueChanged)
                cell.accessoryView = mode
                return cell
            }
            if indexPath.row == 4 {
                let slider = UISlider(frame: CGRect(x: 0, y: 0, width: 140, height: 30))
                slider.minimumValue = 0.85
                slider.maximumValue = 1.30
                slider.value = Float(store.fontScale)
                slider.addTarget(self, action: #selector(fontScaleChanged(_:)), for: .valueChanged)
                cell.accessoryView = slider
                return cell
            }
            let toggle = UISwitch()
            toggle.isOn = [store.showsTitles, store.hapticsEnabled, store.searchEnabled][indexPath.row]
            toggle.tag = indexPath.row
            toggle.addTarget(self, action: #selector(settingChanged(_:)), for: .valueChanged)
            cell.accessoryView = toggle
            return cell
        }
        let action = store.actions[indexPath.row]
        cell.textLabel?.text = action.title
        let toggle = UISwitch()
        toggle.isOn = store.enabledActionIDs.contains(action.id)
        toggle.accessibilityIdentifier = action.id
        toggle.addTarget(self, action: #selector(actionChanged(_:)), for: .valueChanged)
        cell.accessoryView = toggle
        return cell
    }

    @objc private func settingChanged(_ sender: UISwitch) {
        switch sender.tag {
        case 0: store.showsTitles = sender.isOn
        case 1: store.hapticsEnabled = sender.isOn
        default: store.searchEnabled = sender.isOn
        }
        mirrorView?.configure()
    }

    @objc private func heightModeChanged(_ sender: UISegmentedControl) {
        store.heightMode = sender.selectedSegmentIndex
        mirrorView?.configure()
    }

    @objc private func fontScaleChanged(_ sender: UISlider) {
        store.fontScale = CGFloat(sender.value)
        mirrorView?.configure()
    }

    @objc private func actionChanged(_ sender: UISwitch) {
        guard let id = sender.accessibilityIdentifier else { return }
        if sender.isOn { store.enabledActionIDs.insert(id) } else { store.enabledActionIDs.remove(id) }
        mirrorView?.configure()
    }
}

private final class MirrorViewController: UIViewController {
    private let store = MorphingStore()
    private lazy var morphingView = MorphingTabBarView(store: store)
    private let eventLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "WCGlass 3.0.6-3 镜像"
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "gearshape"), style: .plain, target: self, action: #selector(openSettings))
        buildContent()
        store.onTabSelected = { [weak self] index in
            self?.eventLabel.text = "回调 tabSelectionHandler：\(index)"
        }
        store.onActionSelected = { [weak self] id in
            self?.eventLabel.text = "回调 actionSelectionHandler：\(id)"
        }
        store.onIdentityCopy = { [weak self] value in
            self?.eventLabel.text = "回调 identityCopyHandler：\(value)"
        }
        store.onExpansionChanged = { [weak self] expanded in
            self?.eventLabel.text = "回调 expansionChangedHandler：\(expanded ? "expanded" : "collapsed")"
        }
    }

    private func buildContent() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let content = UIStackView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .vertical
        content.spacing = 14
        content.layoutMargins = UIEdgeInsets(top: 20, left: 20, bottom: 24, right: 20)
        content.isLayoutMarginsRelativeArrangement = true
        scrollView.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        let titleLabel = UILabel()
        titleLabel.text = "独立行为镜像"
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        content.addArrangedSubview(titleLabel)

        let description = UILabel()
        description.text = "用原生 UIKit 重现 WCGlass 3.0.6-3 可观测的形态标签栏：标签、动作、身份头、搜索、加号及展开/收起回调。"
        description.numberOfLines = 0
        description.textColor = .secondaryLabel
        content.addArrangedSubview(description)

        let previewCard = UIView()
        previewCard.translatesAutoresizingMaskIntoConstraints = false
        previewCard.backgroundColor = .secondarySystemBackground
        previewCard.layer.cornerCurve = .continuous
        previewCard.layer.cornerRadius = 24
        previewCard.clipsToBounds = true
        previewCard.heightAnchor.constraint(equalToConstant: 390).isActive = true
        content.addArrangedSubview(previewCard)
        previewCard.addSubview(morphingView)
        NSLayoutConstraint.activate([
            morphingView.leadingAnchor.constraint(equalTo: previewCard.leadingAnchor),
            morphingView.trailingAnchor.constraint(equalTo: previewCard.trailingAnchor),
            morphingView.topAnchor.constraint(equalTo: previewCard.topAnchor),
            morphingView.bottomAnchor.constraint(equalTo: previewCard.bottomAnchor)
        ])

        eventLabel.text = "等待交互"
        eventLabel.textColor = .secondaryLabel
        eventLabel.font = .preferredFont(forTextStyle: .footnote)
        eventLabel.numberOfLines = 0
        content.addArrangedSubview(eventLabel)

        let hint = UILabel()
        hint.text = "点击底部加号或标签栏展开；点击身份头复制 wxid；长按/双击加号验证三个入口。"
        hint.textColor = .secondaryLabel
        hint.numberOfLines = 0
        content.addArrangedSubview(hint)
    }

    @objc private func openSettings() {
        navigationController?.pushViewController(MirrorSettingsViewController(store: store, mirrorView: morphingView), animated: true)
    }
}
