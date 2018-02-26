public struct Tag {
    let readingList: ReadingList
    let index: Int
    let indexPath: IndexPath
    
    var isLast: Bool {
        return index == 2
    }
}

class TagCollectionViewCell: CollectionViewCell {
    static let reuseIdentifier = "TagCollectionViewCell"
    fileprivate let label = UILabel()
    internal var width: CGFloat = 0
    
    override func setup() {
        contentView.addSubview(label)
        layer.cornerRadius = 3
        clipsToBounds = true
        super.setup()
    }
    
    func configure(with tag: Tag, for count: Int, theme: Theme) {
        guard tag.index <= 2, let name = tag.readingList.name else {
            return
        }
        label.text = (tag.isLast ? "+\(count - 2)" : name).uppercased()
        width = min(100, label.intrinsicContentSize.width)
        apply(theme: theme)
        updateFonts(with: traitCollection)
        setNeedsLayout()
    }
    
    var semanticContentAttributeOverride: UISemanticContentAttribute = .unspecified {
        didSet {
            label.semanticContentAttribute = semanticContentAttributeOverride
        }
    }
    
    override func updateFonts(with traitCollection: UITraitCollection) {
        super.updateFonts(with: traitCollection)
        label.setFont(with: .system, style: .footnote, traitCollection: traitCollection)
    }
    
    override func sizeThatFits(_ size: CGSize, apply: Bool) -> CGSize {
        var origin = CGPoint.zero
        
        if label.wmf_hasText {
            origin.y += label.wmf_preferredHeight(at: origin, fitting: width, alignedBy: semanticContentAttributeOverride, spacing: 0, apply: apply)
        }
        
        return CGSize(width: size.width, height: origin.y)
    }
    
    override func updateBackgroundColorOfLabels() {
        super.updateBackgroundColorOfLabels()
        label.backgroundColor = labelBackgroundColor
    }
}

extension TagCollectionViewCell: Themeable {
    func apply(theme: Theme) {
        label.textColor = theme.colors.secondaryText
        setBackgroundColors(theme.colors.midBackground, selected: theme.colors.baseBackground)
        updateSelectedOrHighlighted()
    }
}
