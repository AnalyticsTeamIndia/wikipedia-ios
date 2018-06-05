//
//  SuggestionsFetcher.swift
//  Wikipedia
//
//  Created by Chris Eidhof on 05.06.18.
//  Copyright © 2018 Wikimedia Foundation. All rights reserved.
//

import Foundation

class SuggestionsFetcher {
    
    fileprivate let locationSearchFetcher = WMFLocationSearchFetcher()
    fileprivate let searchFetcher = WMFSearchFetcher()
    private var currentSearch = ""

    
    func fetchSearchSuggestions(searchString: String, filter: PlaceFilterType, userLocation: CLLocationCoordinate2D, completion: @escaping ([PlaceSearch], Bool) -> ())
    {
        let text = searchString.trimmingCharacters(in: NSCharacterSet.whitespacesAndNewlines)
        currentSearch = text
        guard text != "" else {
            completion([], false)
            return
        }
        searchFetcher.fetchArticles(forSearchTerm: text, siteURL: siteURL, resultLimit: 24, failure: { (error) in
            guard text == self.currentSearch else {
                return
            }
            completion([], false)
        }) { (searchResult) in
            guard text == self.currentSearch else {
                return
            }
            
            if let suggestion = searchResult.searchSuggestion {
                DDLogDebug("got suggestion! \(suggestion)")
            }
            
            let completions = self.handleCompletion(searchResults: searchResult.results ?? [], filter: filter, siteURL: siteURL)
            completion(completions, true)
            guard completions.count < 10 else {
                return
            }
            
            let center = userLocation
            let region = CLCircularRegion(center: center, radius: 40075000, identifier: "world")
            self.locationSearchFetcher.fetchArticles(withSiteURL: siteURL, in: region, matchingSearchTerm: text, sortStyle: .links, resultLimit: 24, completion: { (locationSearchResults) in
                guard text == self.currentSearch else {
                    return
                }
                var combinedResults: [MWKSearchResult] = searchResult.results ?? []
                let newResults = locationSearchResults.results as [MWKSearchResult]
                combinedResults.append(contentsOf: newResults)
                let results = self.handleCompletion(searchResults: combinedResults, filter: filter, siteURL: siteURL)
                completion(results, true)
            }) { (error) in
                guard text == self.currentSearch else {
                    return
                }
            }
        }
    }

    func handleCompletion(searchResults: [MWKSearchResult], filter: PlaceFilterType, siteURL: URL) -> [PlaceSearch] {
        var set = Set<String>()
        let completions = searchResults.compactMap { (result) -> PlaceSearch? in
            guard let location = result.location,
                let dimension = result.geoDimension?.doubleValue,
                let url = result.articleURL(forSiteURL: siteURL),
                let key = url.wmf_articleDatabaseKey,
                !set.contains(key) else {
                    return nil
            }
            set.insert(key)
            let region = [location.coordinate].wmf_boundingRegion(with: dimension)
            return PlaceSearch(filter: filter, type: .location, origin: .user, sortStyle: .links, string: nil, region: region, localizedDescription: result.displayTitle, searchResult: result, siteURL: siteURL)
        }
        return completions
    }
}
