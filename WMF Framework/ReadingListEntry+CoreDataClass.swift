import Foundation
import CoreData

public class ReadingListEntry: NSManagedObject {
    var articleURL: URL? {
        guard let key = articleKey else {
            return nil
        }
        return URL(string: key)
    }
    
    public var APIError: APIReadingListError? {
        guard let errorCode = errorCode else {
            return nil
        }
        return APIReadingListError(rawValue: errorCode)
    }
}
