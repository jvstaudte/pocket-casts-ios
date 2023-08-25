import PocketCastsUtils
import UIKit

protocol PlayerTabDelegate: AnyObject {
    func didSwitchToTab(index: Int)
}

enum PlayerTabs: Int {
    case nowPlaying
    case showNotes
    case chapters
    case bookmarks

    var description: String {
        switch self {
        case .nowPlaying:
            return L10n.nowPlaying
        case .showNotes:
            return FeatureFlag.bookmarks.enabled ? L10n.playerShowNotesTitle : L10n.showNotes
        case .chapters:
            return L10n.chapters
        case .bookmarks:
            return L10n.bookmarks
        }
    }
}

class PlayerTabsView: UIScrollView {
    var tabs: [PlayerTabs] = [.nowPlaying] {
        didSet {
            updateTabs()
        }
    }

    var currentTab = 0 {
        didSet {
            animateTabChange(fromIndex: oldValue, toIndex: currentTab)

            guard oldValue != currentTab, let tab = tabs[safe: currentTab] else {
                return
            }

            trackTabChanged(tab: tab)

            switch tab {
            case .nowPlaying:
                break
            case .showNotes:
                AnalyticsHelper.playerShowNotesOpened()
            case .chapters:
                AnalyticsHelper.chaptersOpened()
            case .bookmarks: #warning("TODO: Bookmarks: Analytics")
                break
            }
        }
    }

    weak var tabDelegate: PlayerTabDelegate?

    private let lineLayer = CAShapeLayer()

    private lazy var tabsStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = TabConstants.spacing

        return stackView
    }()

    // Fade Layers
    private lazy var fadeLeading = {
        FadeOutLayer(fadePosition: .leading)
    }()

    private lazy var fadeTrailing = {
        FadeOutLayer(fadePosition: .trailing)
    }()

    func setup() {
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        clipsToBounds = true

        updateTabs()

        addSubview(tabsStackView)
        tabsStackView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            tabsStackView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            tabsStackView.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            tabsStackView.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
            tabsStackView.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            tabsStackView.heightAnchor.constraint(equalTo: frameLayoutGuide.heightAnchor)
        ])

        layer.addSublayer(fadeLeading)
        layer.addSublayer(fadeTrailing)
    }

    func themeDidChange() {
        updateTabs()

        fadeLeading.updateColors()
        fadeTrailing.updateColors()
    }

    var lastLayedOutWidth: CGFloat = 0
    override func layoutSubviews() {
        super.layoutSubviews()

        updateFadeLayers()

        let currentWidth = bounds.width
        if lastLayedOutWidth == currentWidth { return }

        lastLayedOutWidth = currentWidth
        updateTabs()
    }

    private func updateTabs() {
        tabsStackView.removeAllSubviews()

        for (index, tab) in tabs.enumerated() {
            let button = UIButton(type: .custom)
            button.isPointerInteractionEnabled = true
            button.titleLabel?.font = TabConstants.titleFont

            let titleColor = index == currentTab ? ThemeColor.playerContrast01() : ThemeColor.playerContrast02()
            button.setTitleColor(titleColor, for: .normal)

            let title = tab.description
            button.setTitle(title, for: .normal)
            button.tag = index
            button.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)

            tabsStackView.addArrangedSubview(button)
        }

        layoutIfNeeded()
    }

    @objc private func buttonTapped(_ sender: UIButton) {
        let tabIndex = sender.tag

        currentTab = tabIndex
        tabDelegate?.didSwitchToTab(index: currentTab)
    }

    private func animateTabChange(fromIndex: Int, toIndex: Int) {

        // text color animation
        if let fromTab = tabsStackView.arrangedSubviews[safe: fromIndex] as? UIButton {
            UIView.transition(with: fromTab, duration: Constants.Animation.defaultAnimationTime, options: .transitionCrossDissolve, animations: {
                fromTab.setTitleColor(ThemeColor.playerContrast02(), for: .normal)
            }, completion: nil)
        }

        if let toTab = tabsStackView.arrangedSubviews[safe: toIndex] as? UIButton {
            UIView.transition(with: toTab, duration: Constants.Animation.defaultAnimationTime, options: .transitionCrossDissolve, animations: {
                toTab.setTitleColor(ThemeColor.playerContrast01(), for: .normal)
            }, completion: nil)

            // Scroll the button into view, but make sure it clears the fade
            scrollRectToVisible(toTab.frame.insetBy(dx: -TabConstants.fadeSize, dy: 0), animated: true)
        }
    }




    private enum TabConstants {
        static let titleFont = UIFont.systemFont(ofSize: 16, weight: .bold)
        static let spacing: CGFloat = 14

        static let lineHeight: CGFloat = 2
        static let lineOffset: CGFloat = 8

        static let fadeSize: CGFloat = 50
    }
}

// MARK: - Private: Scroll Fading

private extension PlayerTabsView {
    private func updateFadeLayers() {
        let offset = contentOffset.x
        let size = CGSize(width: TabConstants.fadeSize, height: bounds.height)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fadeLeading.frame = .init(origin: .init(x: offset, y: 0), size: size)
        fadeTrailing.frame = .init(origin: .init(x: offset + bounds.width - TabConstants.fadeSize, y: 0), size: size)
        CATransaction.commit()

        fadeLeading.opacity = contentOffset.x > 0 ? 1 : 0
        fadeTrailing.opacity = (contentOffset.x + bounds.width) < contentSize.width ? 1 : 0
    }

    private class FadeOutLayer: CAGradientLayer {
        enum FadePosition {
            case leading, trailing
        }

        var fadePosition: FadePosition = .leading

        init(fadePosition: FadePosition) {
            self.fadePosition = fadePosition

            super.init()

            updateColors()

            switch fadePosition {
            case .leading:
                startPoint = .init(x: 1, y: 0)
                endPoint = .zero

            case .trailing:
                startPoint = .zero
                endPoint = .init(x: 1, y: 0)
            }
        }

        func updateColors() {
            let color = PlayerColorHelper.playerBackgroundColor01()

            colors = [
                color.withAlphaComponent(0).cgColor,
                color.cgColor
            ]
        }

        override init(layer: Any) {
            if let layer = layer as? Self {
                fadePosition = layer.fadePosition
            }

            super.init(layer: layer)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}

// MARK: - Private: Analytics

private extension PlayerTabsView {
    func trackTabChanged(tab: PlayerTabs) {
        let tabName: String
        switch tab {
        case .nowPlaying:
            tabName = "now_playing"
        case .showNotes:
            tabName = "show_notes"
        case .chapters:
            tabName = "chapters"
        case .bookmarks:
            tabName = "bookmarks"
        }

        Analytics.track(.playerTabSelected, properties: ["tab": tabName])
    }
}
