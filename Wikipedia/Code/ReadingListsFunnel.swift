// https://meta.wikimedia.org/wiki/Schema:MobileWikiAppiOSReadingLists

@objc final class ReadingListsFunnel: EventLoggingFunnel, EventLoggingStandardEventProviding {
    @objc public static let shared = ReadingListsFunnel()
    
    private enum Action: String {
        case save
        case unsave
        case createList = "createlist"
        case deleteList = "deletelist"
        case readStart = "read_start"
    }
    
    private override init() {
        super.init(schema: "MobileWikiAppiOSReadingLists", version: 18064062)
    }
    
    private func event(category: EventLoggingCategory, label: EventLoggingLabel?, action: Action, measure: Int = 1) -> Dictionary<String, Any> {
        let category = category.value
        let action = action.rawValue
        let isAnon = !WMFAuthenticationManager.sharedInstance.isLoggedIn
        
        var event: [String: Any] = ["category": category, "action": action, "measure": measure, "primary_language": primaryLanguage(), "is_anon": isAnon]
        if let labelValue = label?.value {
            event["label"] = labelValue
        }
        return event
    }
    
    override func preprocessData(_ eventData: [AnyHashable: Any]) -> [AnyHashable: Any] {
        return wholeEvent(with: eventData)
    }
    
    // - MARK: Article
    
    @objc public func logArticleSaveInCurrentArticle(_ articleURL: URL) {
        logSave(category: .article, label: .current, articleURL: articleURL)
    }
    
    @objc public func logArticleUnsaveInCurrentArticle(_ articleURL: URL) {
        logUnsave(category: .article, label: .current, articleURL: articleURL)
    }
    
    @objc public func logOutLinkSaveInCurrentArticle(_ articleURL: URL) {
        logSave(category: .article, label: .outLink, articleURL: articleURL)
    }
    
    @objc public func logOutLinkUnsaveInCurrentArticle(_ articleURL: URL) {
        logUnsave(category: .article, label: .outLink, articleURL: articleURL)
    }
    
    // - MARK: Read more
    
    @objc public func logArticleSaveInReadMore(_ articleURL: URL) {
        logSave(category: .article, label: .readMore, articleURL: articleURL)
    }
    
    @objc public func logArticleUnsaveInReadMore(_ articleURL: URL) {
        logUnsave(category: .article, label: .readMore, articleURL: articleURL)
    }
    
    // - MARK: Feed
    
    @objc public func logSaveInFeed(saveButton: SaveButton?, articleURL: URL) {
        logSave(category: .feed, label: saveButton?.eventLoggingLabel ?? .none, articleURL: articleURL)
    }
    
    @objc public func logUnsaveInFeed(saveButton: SaveButton?, articleURL: URL) {
        logUnsave(category: .feed, label: saveButton?.eventLoggingLabel, articleURL: articleURL)
    }
    
    @objc public func logSaveInFeed(contentGroup: WMFContentGroup?, articleURL: URL) {
        logSave(category: .feed, label: contentGroup?.eventLoggingLabel ?? .none, articleURL: articleURL)
    }
    
    @objc public func logUnsaveInFeed(contentGroup: WMFContentGroup?, articleURL: URL) {
        logUnsave(category: .feed, label: contentGroup?.eventLoggingLabel, articleURL: articleURL)
    }
    
    // - MARK: Places
    
    @objc public func logSaveInPlaces(_ articleURL: URL) {
        logSave(category: .places, articleURL: articleURL)
    }
    
    @objc public func logUnsaveInPlaces(_ articleURL: URL) {
        logUnsave(category: .places, articleURL: articleURL)
    }
    
    // - MARK: Generic article save & unsave actions
    
    private func logSave(category: EventLoggingCategory, label: EventLoggingLabel? = nil, measure: Int = 1, language: String?) {
        log(event(category: category, label: label, action: .save, measure: measure), language: language)
    }
    
    public func logSave(category: EventLoggingCategory, label: EventLoggingLabel? = nil, measure: Int = 1, articleURL: URL) {
        log(event(category: category, label: label, action: .save, measure: measure), language: articleURL.wmf_language)
    }
    
    @objc public func logSave(category: EventLoggingCategory, label: EventLoggingLabel, measure: Int = 1, language: String?) {
        log(event(category: category, label: label, action: .save, measure: measure), language: language)
    }
    
    private func logUnsave(category: EventLoggingCategory, label: EventLoggingLabel? = nil, measure: Int = 1, language: String?) {
        log(event(category: category, label: label, action: .unsave, measure: measure), language: language)
    }
    
    public func logUnsave(category: EventLoggingCategory, label: EventLoggingLabel? = nil, measure: Int = 1, articleURL: URL) {
        log(event(category: category, label: label, action: .unsave, measure: measure), language: articleURL.wmf_language)
    }
    
    // - MARK: Saved - default reading list
    
    public func logUnsaveInReadingList(articlesCount: Int = 1, language: String?) {
        logUnsave(category: .saved, label: .items, measure: articlesCount, language: language)
    }
    
    public func logReadStartIReadingList(_ articleURL: URL) {
        log(event(category: .saved, label: .items, action: .readStart), language: articleURL.wmf_language)
    }
    
    // - MARK: Saved - reading lists
    
    public func logDeleteInReadingLists(readingListsCount: Int = 1) {
        log(event(category: .saved, label: .lists, action: .deleteList, measure: readingListsCount))
    }
    
    public func logCreateInReadingLists() {
        log(event(category: .saved, label: .lists, action: .createList))
    }
    
    // - MARK: Add articles to reading list
    
    public func logDeleteInAddToReadingList(readingListsCount: Int = 1) {
        log(event(category: .addToList, label: nil, action: .deleteList, measure: readingListsCount))
    }
    
    public func logCreateInAddToReadingList() {
        log(event(category: .addToList, label: nil, action: .createList))
    }
}
