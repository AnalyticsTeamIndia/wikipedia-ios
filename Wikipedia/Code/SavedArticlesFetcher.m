
#import "SavedArticlesFetcher_Testing.h"

#import "Wikipedia-Swift.h"
#import "WMFArticleFetcher.h"
#import "MWKImageInfoFetcher.h"

#import "MWKDataStore.h"
#import "MWKSavedPageList.h"
#import "MWKArticle.h"
#import "MWKImage+CanonicalFilenames.h"
#import "WMFURLCache.h"
#import "WMFImageURLParsing.h"
#import "UIScreen+WMFImageWidth.h"

static DDLogLevel const WMFSavedArticlesFetcherLogLevel = DDLogLevelDebug;

#undef LOG_LEVEL_DEF
#define LOG_LEVEL_DEF WMFSavedArticlesFetcherLogLevel

NS_ASSUME_NONNULL_BEGIN

@interface SavedArticlesFetcher ()

@property (nonatomic, strong) MWKSavedPageList* savedPageList;
@property (nonatomic, strong) WMFArticleFetcher* articleFetcher;
@property (nonatomic, strong) WMFImageController* imageController;
@property (nonatomic, strong) MWKImageInfoFetcher* imageInfoFetcher;

@property (nonatomic, strong) NSMutableDictionary<MWKTitle*, AnyPromise*>* fetchOperationsByArticleTitle;
@property (nonatomic, strong) NSMutableDictionary<MWKTitle*, NSError*>* errorsByArticleTitle;

@end

@implementation SavedArticlesFetcher

@dynamic fetchFinishedDelegate;

#pragma mark - Shared Access

static SavedArticlesFetcher* _articleFetcher = nil;

- (instancetype)initWithSavedPageList:(MWKSavedPageList*)savedPageList
                       articleFetcher:(WMFArticleFetcher*)articleFetcher
                      imageController:(WMFImageController*)imageController
                     imageInfoFetcher:(MWKImageInfoFetcher*)imageInfoFetcher {
    NSParameterAssert(savedPageList);
    NSParameterAssert(savedPageList.dataStore);
    NSParameterAssert(articleFetcher);
    NSParameterAssert(imageController);
    NSParameterAssert(imageInfoFetcher);
    self = [super init];
    if (self) {
        _accessQueue                       = dispatch_queue_create("org.wikipedia.savedarticlesarticleFetcher.accessQueue", DISPATCH_QUEUE_SERIAL);
        self.fetchOperationsByArticleTitle = [NSMutableDictionary new];
        self.errorsByArticleTitle          = [NSMutableDictionary new];
        self.articleFetcher                = articleFetcher;
        self.imageController               = imageController;
        self.savedPageList                 = savedPageList;
        self.imageInfoFetcher              = imageInfoFetcher;
    }
    return self;
}

- (instancetype)initWithSavedPageList:(MWKSavedPageList*)savedPageList {
    return [self initWithSavedPageList:savedPageList
                        articleFetcher:[[WMFArticleFetcher alloc] initWithDataStore:savedPageList.dataStore]
                       imageController:[WMFImageController sharedInstance]
                      imageInfoFetcher:[[MWKImageInfoFetcher alloc] init]];
}

#pragma mark - Fetching

- (void)fetchAndObserveSavedPageList {
    // build up initial state of current list
    [self fetchUncachedEntries:self.savedPageList.entries];

    // observe subsequent changes
    [self.KVOControllerNonRetaining observe:self.savedPageList
                                    keyPath:WMF_SAFE_KEYPATH(self.savedPageList, entries)
                                    options:NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew
                                     action:@selector(savedPageListDidChange:)];
}

- (void)cancelFetch {
    [self cancelFetchForEntries:self.savedPageList.entries];
}

#pragma mark Internal Methods

- (void)fetchUncachedEntries:(NSArray<MWKSavedPageEntry*>*)insertedEntries {
    if (!insertedEntries.count) {
        return;
    }
    [self fetchUncachedTitles:[insertedEntries valueForKey:WMF_SAFE_KEYPATH([MWKSavedPageEntry new], title)]];
}

- (void)cancelFetchForEntries:(NSArray<MWKSavedPageEntry*>*)deletedEntries {
    if (!deletedEntries.count) {
        return;
    }
    @weakify(self);
    dispatch_async(self.accessQueue, ^{
        @strongify(self);
        BOOL wasFetching = self.fetchOperationsByArticleTitle.count > 0;
        [deletedEntries bk_each:^(MWKSavedPageEntry* entry) {
            [self cancelFetchForTitle:entry.title];
        }];
        if (wasFetching) {
            /*
               only notify delegate if deletion occurs during a download session. if deletion occurs
               after the fact, we don't need to inform delegate of completion
             */
            [self notifyDelegateIfFinished];
        }
    });
}

- (void)fetchUncachedTitles:(NSArray<MWKTitle*>*)titles {
    dispatch_block_t didFinishLegacyMigration = ^{
        [[NSUserDefaults standardUserDefaults] wmf_setDidFinishLegacySavedArticleImageMigration:YES];
    };
    if (!titles.count) {
        didFinishLegacyMigration();
        return;
    }
    dispatch_group_t group = dispatch_group_create();
    NSMutableSet *titlesToLeave = [NSMutableSet setWithArray:titles];
    for (MWKTitle* title in titles) {
        dispatch_group_enter(group);
        dispatch_async(self.accessQueue, ^{
            [self fetchTitle:title failure:^(NSError *error) {
                 dispatch_async(self.accessQueue, ^{
                    if ([titlesToLeave containsObject:title]) {
                        [titlesToLeave removeObject:title];
                        dispatch_group_leave(group);
                    } else {
                        DDLogError(@"Extraneous callback for title: %@", title);
                    }
                 });

            } success:^{
                dispatch_async(self.accessQueue, ^{
                    if ([titlesToLeave containsObject:title]) {
                        [titlesToLeave removeObject:title];
                        dispatch_group_leave(group);
                    } else {
                        DDLogError(@"Extraneous callback for title: %@", title);
                    }
                });
            }];
        });
    }
    dispatch_group_notify(group, dispatch_get_main_queue(), didFinishLegacyMigration);

}

- (void)fetchTitle:(MWKTitle*)title failure:(WMFErrorHandler)failure success:(WMFSuccessHandler)success {
    // NOTE: must check isCached to determine that all article data has been downloaded
    MWKArticle* articleFromDisk = [self.savedPageList.dataStore articleFromDiskWithTitle:title];
    @weakify(self);
    if (articleFromDisk.isCached) {
        // only fetch images if article was cached
        [self downloadImageDataForArticle:articleFromDisk failure:failure success:success];
    } else {
        /*
           don't use "finallyOn" to remove the promise from our tracking dictionary since it has to be removed
           immediately in order to ensure accurate progress & error reporting.
         */
        self.fetchOperationsByArticleTitle[title] =
            [self.articleFetcher fetchArticleForPageTitle:title progress:NULL].thenOn(self.accessQueue, ^(MWKArticle* article){
            @strongify(self);
            [self downloadImageDataForArticle:article failure:^(NSError *error) {
                dispatch_async(self.accessQueue, ^{
                    [self didFetchArticle:article title:title error:error];
                    failure(error);
                });
            } success:^{
                dispatch_async(self.accessQueue, ^{
                    [self didFetchArticle:article title:title error:nil];
                    success();
                });
            }];
        }).catch(^(NSError* error){
            if (!self) {
                return;
            }
            dispatch_async(self.accessQueue, ^{
                [self didFetchArticle:nil title:title error:error];
            });
        });
    }
}

- (void)downloadImageDataForArticle:(MWKArticle*)article failure:(WMFErrorHandler)failure success:(WMFSuccessHandler)success {
    [self fetchAllImagesInArticle:article failure:^(NSError *error) {
        failure([NSError wmf_savedPageImageDownloadError]);
    } success:^{
        [self fetchGalleryDataForArticle:article failure:failure success:success];
    }];
}

- (void)migrateLegacyImagesInArticle:(MWKArticle *)article {
    //  Removes up old saved article image list folders, copies old cached images to original and article image width locations. This ensures articles saved with 5.0.4 and older will still have images availble offline in 5.0.5. The migration is idempotent - the enumerated folders are removed so they won't be processed the next time around.
    
    //Get the folder that contains legacy saved article images for example - articles/Barack_Obama/Images/
    NSString *imagesFolderPath = [self.savedPageList.dataStore pathForImagesWithTitle:article.title];
    NSURL *imagesFolderURL = [NSURL fileURLWithPath:imagesFolderPath isDirectory:YES];
    NSEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtURL:imagesFolderURL includingPropertiesForKeys:@[NSURLIsDirectoryKey] options:NSDirectoryEnumerationSkipsSubdirectoryDescendants errorHandler:^BOOL(NSURL * _Nonnull url, NSError * _Nonnull error) {
        DDLogError(@"Error enumerating image directory: %@", error);
        return YES;
    }];
    
    WMFImageController *imageController = [WMFImageController sharedInstance];
    NSUInteger articleImageWidth = [[UIScreen mainScreen] wmf_articleImageWidthForScale];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    for (NSURL *imageFolderURL in enumerator) { //Enumerate each subfolder of the image folder. There is one subfolder per saved image.
        NSNumber *isDirectoryNumber = nil;
        NSError *isDirectoryError = nil;
        if (![imageFolderURL getResourceValue:&isDirectoryNumber forKey:NSURLIsDirectoryKey error:&isDirectoryError]) {
            DDLogError(@"Error reading from article image cache: %@", isDirectoryError);
            continue;
        }
        
        if (![isDirectoryNumber boolValue]) {
            continue;
        }
        
        NSURL *imagePlistURL = [imageFolderURL URLByAppendingPathComponent:@"Image.plist"];
        NSDictionary *imageDictionary = [NSDictionary dictionaryWithContentsOfURL:imagePlistURL];
        NSString *imageURLString = imageDictionary[@"sourceURL"];
        
        if (imageURLString == nil) {
            continue;
        }
        
        NSUInteger width = WMFParseSizePrefixFromSourceURL(imageURLString);
        if (width != articleImageWidth && width != NSNotFound) {
            NSURL *imageURL = [NSURL URLWithString:imageURLString];
            if (imageURL != nil && [imageController hasDataOnDiskForImageWithURL:imageURL]) {
                NSURL *cachedFileURL = [NSURL fileURLWithPath:[imageController cachePathForImageWithURL:imageURL] isDirectory:NO];
                if (cachedFileURL != nil) {
                    NSString *articleURLString = WMFChangeImageSourceURLSizePrefix(imageURLString, articleImageWidth);
                    NSURL *articleURL = [NSURL URLWithString:articleURLString];
                    if (articleURL != nil && ![imageController hasDataOnDiskForImageWithURL:articleURL]) {
                        NSString *imageExtension = [imageURL pathExtension];
                        NSString *imageMIMEType = [imageExtension wmf_asMIMEType];
                        [imageController cacheImageFromFileURL:cachedFileURL forURL:articleURL MIMEType:imageMIMEType];
                    }
                    
                    NSError *removalError = nil;
                    if (![fileManager removeItemAtURL:cachedFileURL error:&removalError]) {
                        DDLogError(@"Error removing legacy cached image: %@", removalError);
                    }
                }
            }
        }
        
        //if this is the article image, don't delete it because it should be preserved
        BOOL isArticleImage = [article.imageURL isEqualToString:imageURLString];
        if (!isArticleImage) {
            NSError *removalError = nil;
            if (![fileManager removeItemAtURL:imageFolderURL error:&removalError]) {
                DDLogError(@"Error removing old image list image: %@", removalError);
            }
        }
    }
}

- (void)fetchAllImagesInArticle:(MWKArticle*)article failure:(WMFErrorHandler)failure success:(WMFSuccessHandler)success {
    if (![[NSUserDefaults standardUserDefaults] wmf_didFinishLegacySavedArticleImageMigration]) {
        WMF_TECH_DEBT_TODO(This legacy migration can be removed after enough users upgrade to 5.0.5)
        [self migrateLegacyImagesInArticle:article];
    }
    
    WMFURLCache* cache = (WMFURLCache*)[NSURLCache sharedURLCache];
    [cache permanentlyCacheImagesForArticle:article];
    
    NSArray<NSURL*>* URLs = [[article allImageURLs] allObjects];
    
    [self cacheImagesWithURLsInBackground:URLs failure:failure success:success];
}

- (void)fetchGalleryDataForArticle:(MWKArticle*)article failure:(WMFErrorHandler)failure success:(WMFSuccessHandler)success {
    WMF_TECH_DEBT_TODO(check whether on - disk image info matches what we are about to fetch)
    @weakify(self);
    [self fetchImageInfoForImagesInArticle:article failure:^(NSError *error) {
        failure(error);
    } success:^(NSArray *info) {
        @strongify(self);
        if (!self) {
            failure([NSError cancelledError]);
            return;
        }
        if (info.count == 0) {
            DDLogVerbose(@"No gallery images to fetch.");
            success();
            return;
        }
        
        NSArray *URLs = [info valueForKey:@"imageThumbURL"];
        
        [self cacheImagesWithURLsInBackground:URLs failure:failure success:success];
    }];
}

- (void)fetchImageInfoForImagesInArticle:(MWKArticle*)article failure:(WMFErrorHandler)failure success:(WMFSuccessNSArrayHandler)success {
    @weakify(self);
    NSArray<NSString*>* imageFileTitles =
        [[MWKImage mapFilenamesFromImages:[article imagesForGallery]] bk_reject:^BOOL (id obj) {
        return [obj isEqual:[NSNull null]];
    }];

    if (imageFileTitles.count == 0) {
        DDLogVerbose(@"No image info to fetch, returning successful promise with empty array.");
        success(imageFileTitles);
        return;
    }

    for (NSString *canonicalFilename in imageFileTitles) {
        [self.imageInfoFetcher fetchGalleryInfoForImage:canonicalFilename fromSite:article.title.site];
    }
    
    PMKJoin([[imageFileTitles bk_map:^AnyPromise*(NSString* canonicalFilename) {
        return [self.imageInfoFetcher fetchGalleryInfoForImage:canonicalFilename fromSite:article.title.site];
    }] bk_reject:^BOOL (id obj) {
        return [obj isEqual:[NSNull null]];
    }]).thenInBackground(^id (NSArray* infoObjects) {
        @strongify(self);
        if (!self) {
            return [NSError cancelledError];
        }
        [self.savedPageList.dataStore saveImageInfo:infoObjects forTitle:article.title];
        success(infoObjects);
        return infoObjects;
    });
}


- (void)cacheImagesWithURLsInBackground:(NSArray<NSURL*>*)imageURLs failure:(void (^ _Nonnull)(NSError * _Nonnull error))failure success:(void (^ _Nonnull)(void))success{
    
    imageURLs = [imageURLs bk_select:^BOOL(id obj) {
        return [obj isKindOfClass:[NSURL class]];
    }];
    
    if([imageURLs count] == 0){
        success();
        return;
    }
    
    [self.imageController cacheImagesWithURLsInBackground:imageURLs failure:failure success:success];
}


#pragma mark - Cancellation

- (void)cancelFetchForTitle:(MWKTitle*)title {
    DDLogVerbose(@"Canceling saved page download for title: %@", title);
    [self.articleFetcher cancelFetchForPageTitle:title];
    [[[self.savedPageList.dataStore existingArticleWithTitle:title] allImageURLs] bk_each:^(NSURL* imageURL) {
        [self.imageController cancelFetchForURL:imageURL];
    }];
    WMF_TECH_DEBT_TODO(cancel image info & high - res image requests)
    [self.fetchOperationsByArticleTitle removeObjectForKey : title];
}

#pragma mark - KVO

- (void)savedPageListDidChange:(NSDictionary*)change {
    switch ([change[NSKeyValueChangeKindKey] integerValue]) {
        case NSKeyValueChangeInsertion: {
            [self fetchUncachedEntries:change[NSKeyValueChangeNewKey]];
            break;
        }
        case NSKeyValueChangeRemoval: {
            [self cancelFetchForEntries:change[NSKeyValueChangeOldKey]];
            break;
        }
        default:
            NSAssert(NO, @"Unsupported KVO operation %@ on saved page list %@", change, self.savedPageList);
            break;
    }
}

#pragma mark - Progress

- (void)getProgress:(WMFProgressHandler)progressBlock {
    dispatch_async(self.accessQueue, ^{
        CGFloat progress = [self progress];

        dispatch_async(dispatch_get_main_queue(), ^{
            progressBlock(progress);
        });
    });
}

/// Only invoke within accessQueue
- (CGFloat)progress {
    /*
       FIXME: Handle progress when only downloading a subset of saved pages (e.g. if some were already downloaded in
       a previous session)?
     */
    if ([self.savedPageList countOfEntries] == 0) {
        return 0.0;
    }

    return (CGFloat)([self.savedPageList countOfEntries] - [self.fetchOperationsByArticleTitle count])
           / (CGFloat)[self.savedPageList countOfEntries];
}

#pragma mark - Delegate Notification

/// Only invoke within accessQueue
- (void)didFetchArticle:(MWKArticle* __nullable)fetchedArticle
                  title:(MWKTitle*)title
                  error:(NSError* __nullable)error {
    if (error) {
        // store errors for later reporting
        DDLogError(@"Failed to download saved page %@ due to error: %@", title, error);
        self.errorsByArticleTitle[title] = error;
    } else {
        DDLogInfo(@"Downloaded saved page: %@", title);
    }

    // stop tracking operation, effectively advancing the progress
    [self.fetchOperationsByArticleTitle removeObjectForKey:title];

    CGFloat progress = [self progress];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.fetchFinishedDelegate savedArticlesFetcher:self
                                           didFetchTitle:title
                                                 article:fetchedArticle
                                                progress:progress
                                                   error:error];
    });

    [self notifyDelegateIfFinished];
}

/// Only invoke within accessQueue
- (void)notifyDelegateIfFinished {
    if ([self.fetchOperationsByArticleTitle count] == 0) {
        NSError* reportedError;
        if ([self.errorsByArticleTitle count] > 0) {
            reportedError = [[self.errorsByArticleTitle allValues] firstObject];
        }

        [self.errorsByArticleTitle removeAllObjects];

        DDLogInfo(@"Finished downloading all saved pages!");

        [self finishWithError:reportedError
                  fetchedData:nil];
    }
}

@end

static NSString* const WMFSavedPageErrorDomain = @"WMFSavedPageErrorDomain";

@implementation NSError (SavedArticlesFetcherErrors)

+ (instancetype)wmf_savedPageImageDownloadError {
    return [NSError errorWithDomain:WMFSavedPageErrorDomain code:1 userInfo:@{
                NSLocalizedDescriptionKey: MWLocalizedString(@"saved-pages-image-download-error", nil)
            }];
}

@end

NS_ASSUME_NONNULL_END
