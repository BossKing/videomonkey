//
//  FileListController.h
//  VideoMonkey
//
//  Created by Chris Marrin on 1/21/09.
//  Copyright 2009 Apple. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class AppController;
@class Transcoder;

@interface FileListController : NSArrayController {
    IBOutlet NSTableView* m_fileListView;

    int m_draggedRow;
    NSArray* m_lastFoundShowNames;
    NSString* m_lastShowName;
    NSMutableArray* m_fileList;
}

@property(retain) NSArray* lastFoundShowNames;
@property(retain) NSString* lastShowName;

- (void)setSearchBox;
- (void)reloadData;
- (void)searchSelectedFiles;
- (void)searchAllFiles;
- (void)searchSelectedFilesForString:(NSString*) searchString;

- (void)addFile:(NSString*) filename;

- (IBAction)addFiles:(id)sender;
- (IBAction)clearAll:(id)sender;
- (IBAction)selectAll:(id)sender;
- (IBAction)remove:(id)sender;
- (IBAction)selectNext:(id)sender;
- (IBAction)selectPrevious:(id)sender;

-(void) updateState;

@end
