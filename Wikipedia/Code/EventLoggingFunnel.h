@import Foundation;

typedef NS_ENUM(NSUInteger, WMFEventLoggingMaxStringLength) {
    WMFEventLoggingMaxStringLength_General = 99, ///< Recommended by analytics
    WMFEventLoggingMaxStringLength_Snippet = 191 ///< MySQL length in practice
};

NS_ASSUME_NONNULL_BEGIN

/**
 * Base class for EventLogging multi-stage funnels.
 *
 * Instantiate one of the subclasses at the beginning of the
 * activity to be logged, and if necessary pass the funnel object
 * down into further stages of your pipeline (eg from one View
 * Controller to the next), then call the log* methods.
 *
 * Derived classes will contain specific log* methods for each
 * potential logging action variant for readability in calling
 * code.
 */
@interface EventLoggingFunnel : NSObject

@property (nonatomic, strong) NSString *schema;
@property (nonatomic, assign) int revision;
@property (nonatomic, assign) BOOL requiresAppInstallID;

/**
 *  Sampling rate used to calculate sampling ratio.
 *     Rate:        Ratio:      Percent:
 *      1           1/1         100%
 *      2           1/2         50%
 *      3           1/3         33%
 *      ...
 *      100         1/100       1%
 */
@property (nonatomic, assign) NSInteger rate;

/**
 * This constructor should be called internally by derived classes
 * to encapsulate the schema name and version.
 */
- (id)initWithSchema:(NSString *)schema version:(int)revision;

/**
 * An optional preprocessing step before recording data passed
 * to the 'log:' method(s).
 *
 * This can be convenient when many steps of a funnel require
 * a common set of parameters, so they don't have to be repeated.
 *
 * Leave un-overridden if no preprocessing is needed.
 */
- (NSDictionary *)preprocessData:(NSDictionary *)eventData;

/**
 * The basic log: method takes a bare dictionary, which will
 * get run through preprocessData: and then sent off to the
 * background logging operation queue.
 *
 * Primary language as recorded in MWKLanguageLinkController will
 * be used as the target of the logging request.
 *
 * For convenience, derived classes should contain specific
 * log* methods for each potential logging action variant for
 * readibility in calling code (and type safety on params!)
 */
- (void)log:(NSDictionary *)eventData;

/**
 * The basic log: method takes a bare dictionary, which will
 * get run through preprocessData: and then sent off to the
 * background logging operation queue.
 *
 * language will be used to determine the target wiki.
 * If language is nil, primary language as recorded in
 * MWKLanguageLinkController will be used instead.
 *
 * For convenience, derived classes should contain specific
 * log* methods for each potential logging action variant for
 * readibility in calling code (and type safety on params!)
 */
- (void)log:(NSDictionary *)eventData language:(nullable NSString *)language;

/**
 * In some cases logging should go to a specific wiki
 * other than the one in the session. Call this as necessary.
 *
 * Wiki parameter is a dbname, not a domain or hostname!
 */
- (void)log:(NSDictionary *)eventData wiki:(NSString *)wiki;

/**
 * Called after eventData was logged through log:.
 */
- (void)logged:(NSDictionary *)eventData;

/**
 * Helper function to get the app's primary language.
 * Falls back on English if primary language was not set.
 */
- (NSString *)primaryLanguage;

/**
 * Helper function to generate a per-use UUID.
 */
- (NSString *)singleUseUUID;

/**
 * Helper function that returns a persistent appInstallID.
 * appInstallID is generated once per install.
 */
- (NSString *)wmf_appInstallID;

/**
 * Helper function that returns a sessionID.
 * SessionID is reset when app is launched for the first time or resumed.
 */
- (NSString *)wmf_sessionID;

NS_ASSUME_NONNULL_END

@end
