//
//  TVDBMetadataSearcher.m
//  VideoMonkey
//
//  Created by Chris Marrin on 4/13/09.
//  Copyright 2009 Apple. All rights reserved.
//

#import "TVDBMetadataSearcher.h"
#import "XMLDocument.h"

// Map from TVDB tag name to Dictionary tag name
static NSDictionary* g_tvdbEpisodeMap = nil;
static NSDictionary* g_tvdbSeriesMap = nil;

@implementation TVDBMetadataSearcher

-(id) init
{
    m_loadedShowId = -1;
    
    // init the tag map, if needed
    if (!g_tvdbEpisodeMap) {
        g_tvdbEpisodeMap = [[NSDictionary dictionaryWithObjectsAndKeys:
            @"title",       	@"EpisodeName", 
            //@"TVShowName",  	@"TVShowName", 
            @"TVEpisode",   	@"ProductionCode", 
            //@"TVEpisodeNum",	@"EpisodeNumber", 
            //@"TVSeasonNum", 	@"SeasonNumber", 
            //@"tracknum",    	@"tracknum", 
            @"description", 	@"Overview", 
            @"year",        	@"FirstAired", 
            //@"year_year",      	@"year_year", 
            //@"year_month",     	@"year_month", 
            //@"year_day",       	@"year_day", 
            //@"stik",        	@"stik", 
            nil ] retain];

        g_tvdbSeriesMap = [[NSDictionary dictionaryWithObjectsAndKeys:
            //@"advisory",    	@"advisory",
            //@"rating_annotation",@"rating_annotation",
            //@"comment",     	@"©cmt", 
            //@"album",       	@"©alb", 
            //@"artist",      	@"©ART", 
            //@"albumArtist", 	@"aART", 
            //@"copyright",   	@"cprt", 
            @"TVShowName",  	@"SeriesName", 
            @"TVNetwork",   	@"Network", 
            //@"encodingTool",	@"©too", 
            //@"genre",       	@"gnre", 
            @"contentRating",	@"ContentRating",
            nil ] retain];
    }
    
    return self;
}

-(BOOL) searchForShow:(NSString*) searchString
{
    [m_foundShowNames release];
    m_foundShowNames = nil;
    [m_foundShowIds release];
    m_foundShowIds = nil;
    [m_foundSeasons release];
    m_foundSeasons = nil;
    [m_foundEpisodes release];
    m_foundEpisodes = nil;

    NSString* urlString = [NSString stringWithFormat:@"http://www.thetvdb.com/api/GetSeries.php?seriesname=%@", searchString];
    urlString = [urlString stringByAddingPercentEscapesUsingEncoding:NSASCIIStringEncoding];
    NSURL* url = [NSURL URLWithString:urlString];
    MyXMLDocument* doc = [MyXMLDocument xmlDocumentWithContentsOfURL:url];
    
    if (![[[doc rootElement] name] isEqualToString:@"Data"])
        return NO;
        
    NSArray* series = [[doc rootElement] elementsForName:@"Series"];
    if ([series count] == 0)
        return NO;
        
    NSMutableArray* foundShowNames = [[NSMutableArray alloc] init];
    NSMutableArray* foundShowIds = [[NSMutableArray alloc] init];

    for (MyXMLElement* element in series) {
        NSString* name = [[element lastElementForName:@"SeriesName"] content];
        NSString* seriesidString = [[element lastElementForName:@"seriesid"] content];
        int seriesid = (seriesidString && [seriesidString length] > 0) ? [seriesidString intValue] : -1;
        if (name && [name length] > 0 && seriesid >= 0) {
            [foundShowNames addObject:name];
            [foundShowIds addObject:[NSNumber numberWithInt:seriesid]];
        }
    }
    
    if ([foundShowNames count] == 0) {
        [foundShowNames release];
        [foundShowIds release];
        return NO;
    }
    
    m_foundShowNames = foundShowNames;
    m_foundShowIds = foundShowIds;
    
    return YES;
}

-(void) collectArtwork:(NSArray*) fromArray toArray:(NSMutableArray*) toArray
{
    for (MyXMLElement* element in fromArray) {
        NSString* s = [element content];
        if (s && [s length] > 0)
            [toArray addObject:[NSString stringWithFormat:@"http://www.thetvdb.com/banners/%@", s]];
    }
}

-(NSMutableDictionary*) addSeason:(NSString*) season episode:(NSString*) episode
{
    if (![m_seasons valueForKey:season]) {
        // add season
        [m_seasons setValue:[[NSMutableDictionary alloc] init] forKey: season];
    }
    
    if (![[m_seasons valueForKey:season] valueForKey:episode]) {
        // add episode
        [[m_seasons valueForKey:season] setValue:[[NSMutableDictionary alloc] init] forKey:episode];
    }

    return [[m_seasons valueForKey:season] valueForKey:episode];
}

NSInteger intSort(id num1, id num2, void* context)
{
    int v1 = [num1 intValue];
    int v2 = [num2 intValue];
    if (v1 < v2)
        return NSOrderedAscending;
    else if (v1 > v2)
        return NSOrderedDescending;
    else
        return NSOrderedSame;
}

static NSArray* numericallySortedArray(NSArray* array)
{
    return [array sortedArrayUsingFunction:intSort context:nil];
}

-(void) loadDetailsForShow:(int) showId
{
    [m_seasons release];
    m_seasons = nil;
    m_loadedShowId = -1;
    
    for (NSNumber* show in m_foundShowIds)
    {
        // validate show id
        if ([show intValue] == showId) {
            NSString* urlString = [NSString stringWithFormat:@"http://www.thetvdb.com/data/series/%d/all/", showId];
            NSURL* url = [NSURL URLWithString:urlString];
            MyXMLDocument* doc = [MyXMLDocument xmlDocumentWithContentsOfURL:url];
            
            if (![[[doc rootElement] name] isEqualToString:@"Data"])
                return;
        
            // find the season and episode
            MyXMLElement* series = [[doc rootElement] lastElementForName:@"Series"];
            NSArray* episodes = [[doc rootElement] elementsForName:@"Episode"];
            if (!episodes)
                return;
                
            // We found our show. Fill in the details
            m_loadedShowId = showId;
                
            m_seasons = [[NSMutableDictionary alloc] init];
                
            NSString* value;
            
            for (MyXMLElement* episodeElement in episodes) {
                NSString* s = [[episodeElement lastElementForName:@"SeasonNumber"] content];
                NSString* e = [[episodeElement lastElementForName:@"EpisodeNumber"] content];
                
                // build dictionary with values
                NSMutableDictionary* dictionary = [self addSeason:s episode: e];
            
                // this is a tv show
                [dictionary setValue:@"TV Show" forKey:@"stik"];
                
                // set the track, episode and season
                [dictionary setValue:s forKey:@"TVSeasonNum"];
                [dictionary setValue:e forKey:@"TVEpisodeNum"];
                [dictionary setValue:e forKey:@"tracknum"];
                
                // first get all the series info
                for (NSString* key in g_tvdbSeriesMap) {
                    NSString* dictionaryKey = [g_tvdbSeriesMap valueForKey:key];
                    value = [[series lastElementForName:key] content];
                    if (value)
                        [dictionary setValue:value forKey:dictionaryKey];
                }
                
                // then do all the episode info
                for (NSString* key in g_tvdbEpisodeMap) {
                    NSString* dictionaryKey = [g_tvdbEpisodeMap valueForKey:key];
                    value = [[episodeElement lastElementForName:key] content];
                    if (value)
                        [dictionary setValue:value forKey:dictionaryKey];
                }
                
                // If we have a year, set the y/m/d
                NSString* year = [dictionary valueForKey:@"year"];
                if (year && [year length] > 0) {
                    NSArray* yearArray = [year componentsSeparatedByString:@"-"];
                    if ([yearArray count] > 0)
                        [dictionary setValue:[[NSNumber numberWithInt:[[yearArray objectAtIndex:0] intValue]] stringValue] forKey:@"year_year"];
                    if ([yearArray count] > 1)
                        [dictionary setValue:[[NSNumber numberWithInt:[[yearArray objectAtIndex:1] intValue]] stringValue] forKey:@"year_month"];
                    if ([yearArray count] > 2)
                        [dictionary setValue:[[NSNumber numberWithInt:[[yearArray objectAtIndex:2] intValue]] stringValue] forKey:@"year_day"];
                }
                
                // collect the artwork, in order of preference
                NSMutableArray* artwork = [[NSMutableArray alloc] init];
                [self collectArtwork: [series elementsForName:@"poster"] toArray:artwork];
                [self collectArtwork: [series elementsForName:@"fanart"] toArray:artwork];
                [self collectArtwork: [series elementsForName:@"banner"] toArray:artwork];
                [dictionary setValue:artwork forKey:@"artwork"];
            }
            
            // load up the m_foundSeasons array
            [m_foundSeasons release];
            NSMutableArray* foundSeasons = [[NSMutableArray alloc] init];
            for (NSString* key in m_seasons)
                [foundSeasons addObject: key];
            m_foundSeasons = [numericallySortedArray(foundSeasons) retain];
        }
    }
}

-(NSDictionary*) detailsForShow:(int) showId season:(int) season episode:(int) episode
{
    if (showId != m_loadedShowId)
        [self loadDetailsForShow:showId];
    
    NSString* s = [[NSNumber numberWithInt:season] stringValue];
    NSString* e = [[NSNumber numberWithInt:episode] stringValue];
    NSDictionary* episodes = [m_seasons valueForKey:s];
    
    if (!episodes)
        return nil;

    // load up the m_foundEpisodes array
    [m_foundEpisodes release];
    NSMutableArray* foundEpisodes = [[NSMutableArray alloc] init];
    for (NSString* key in episodes)
        [foundEpisodes addObject: key];
    m_foundEpisodes = [numericallySortedArray(foundEpisodes) retain];

    return [episodes valueForKey:e];
}

@end