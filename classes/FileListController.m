//
//  FileListController.m
//  VideoMonkey
//
//  Created by Chris Marrin on 1/21/09.
//  Copyright 2009 Apple. All rights reserved.
//

#import "FileListController.h"

#import "AppController.h"
#import "DeviceController.h"
#import "FileInfoPanelController.h"
#import "Metadata.h"
#import "MetadataSearch.h"
#import "MoviePanelController.h"
#import "ProgressCell.h"
#import "Transcoder.h"

#define FileListItemType @"FileListItemType"

@implementation FileListController

@synthesize fileList = m_fileList;
@synthesize lastFoundShowNames = m_lastFoundShowNames;
@synthesize lastShowName = m_lastShowName;

- (void) awakeFromNib
{
    [m_fileListView setDelegate:self];
    
    m_fileList = [[NSMutableArray alloc] init];
    [self setContent:m_fileList];

	// Register to accept filename drag/drop
	[m_fileListView registerForDraggedTypes:[NSArray arrayWithObjects:NSFilenamesPboardType, FileListItemType, nil]];

    // Setup ProgressCell
    [[m_fileListView tableColumnWithIdentifier: @"progress"] setDataCell: [[ProgressCell alloc] init]];
}

- (void)dealloc
{
    [m_fileList release];
    [super dealloc];
}

static NSString* getOutputFileName(NSString* inputFileName, NSString* savePath, NSString* suffix)
{
    // extract filename
    NSString* lastComponent = [inputFileName lastPathComponent];
    NSString* inputPath = [inputFileName stringByDeletingLastPathComponent];
    NSString* baseName = [lastComponent stringByDeletingPathExtension];

    if (!savePath)
        savePath = inputPath;
        
    // now make sure the file doesn't exist
    NSString* filename;
    for (int i = 0; i < 10000; ++i) {
        if (i == 0)
            filename = [[savePath stringByAppendingPathComponent: baseName] stringByAppendingPathExtension: suffix];
        else
            filename = [[savePath stringByAppendingPathComponent: 
                        [NSString stringWithFormat: @"%@_%d", baseName, i]] stringByAppendingPathExtension: suffix];
            
        if (![[NSFileManager defaultManager] fileExistsAtPath: filename])
            break;
    }
    
    return filename;
}

-(void) setOutputFileName
{
    NSString* suffix = [[AppController instance].deviceController fileSuffix];
    for (Transcoder* transcoder in m_fileList)
        [transcoder changeOutputFileName: getOutputFileName(transcoder.inputFileInfo.filename, [AppController instance].savePath, suffix)];
}

-(Transcoder*) transcoderForFileName:(NSString*) fileName
{
    NSString* suffix = [[AppController instance].deviceController fileSuffix];
    Transcoder* transcoder = [Transcoder transcoder];
    [transcoder addInputFile: fileName];
    [transcoder addOutputFile: getOutputFileName(fileName, [AppController instance].savePath, suffix)];
    transcoder.outputFileInfo.duration = transcoder.inputFileInfo.duration;
    return transcoder;
}

-(void) reloadData
{
    //NSIndexSet* indexes = [self selectionIndexes];
    //[self setSelectionIndexes:[NSIndexSet indexSet]];
    //[self setSelectionIndexes:indexes];
    [m_fileListView reloadData];
}

-(void)setSearchBox
{
    if ([[self selectionIndexes] count] == 0) {
        self.lastFoundShowNames = nil;
        self.lastShowName = nil;
        return;
    }
    
    Transcoder* transcoder = [[self arrangedObjects] objectAtIndex:[self selectionIndex]];
    self.lastFoundShowNames = [[[transcoder metadata] search] foundShowNames];
    self.lastShowName = [[[transcoder metadata] search] currentShowName];
}

-(void) searchSelectedFiles
{
    NSArray* selectedObjects = [self selectedObjects];
    Transcoder* lastTranscoder = nil;
    for (Transcoder* transcoder in selectedObjects) {
        lastTranscoder = transcoder;
        [transcoder.metadata searchAgain];
    }
}

-(void) searchAllFiles
{
    NSArray* arrangedObjects = [self arrangedObjects];
    for (Transcoder* transcoder in arrangedObjects)
        [transcoder.metadata searchAgain];
    [self setSearchBox];
}

-(void) searchSelectedFilesForString:(NSString*) searchString
{
    NSArray* selectedObjects = [self selectedObjects];
    for (Transcoder* transcoder in selectedObjects)
        [[transcoder metadata] searchWithString:searchString];
    [self setSearchBox];
}

- (void)rearrangeObjects
{
	// Remember the selection because rearrange loses it on SnowLeopard
    NSIndexSet* indexes = [self selectionIndexes];
	[super rearrangeObjects];
	[self setSelectionIndexes:indexes];
}

// dragging methods
- (BOOL)tableView: (NSTableView *)aTableView
    writeRows: (NSArray *)rows
    toPasteboard: (NSPasteboard *)pboard
{
    // This method is called after it has been determined that a drag should begin, but before the drag has been started.  
    // To refuse the drag, return NO.  To start a drag, return YES and place the drag data onto the pasteboard (data, owner, etc...).  
    // The drag image and other drag related information will be set up and provided by the table view once this call returns with YES.  
    // The rows array is the list of row numbers that will be participating in the drag.
    if ([rows count] > 1)	// don't allow dragging with more than one row
        return NO;
    
    // get rid of any selections
    [m_fileListView deselectAll:nil];
    m_draggedRow = [[rows objectAtIndex: 0] intValue];
    // the NSArray "rows" is actually an array of the indecies dragged
    
    // declare our dragged type in the paste board
    [pboard declareTypes: [NSArray arrayWithObjects: NSFilenamesPboardType, FileListItemType, nil] owner: self];
    
    // put the string value into the paste board
    [pboard setString: [[m_fileList objectAtIndex: m_draggedRow] inputFileInfo].filename forType: FileListItemType];
    
    return YES;
}

- (NSDragOperation)tableView: (NSTableView *)aTableView
    validateDrop: (id <NSDraggingInfo>)item
    proposedRow: (int)row
    proposedDropOperation: (NSTableViewDropOperation)op
{
    // prevent row from highlighting during drag
    return (op == NSTableViewDropAbove) ? NSDragOperationMove : NSDragOperationNone;
}

- (BOOL)tableView:(NSTableView*)aTableView
    acceptDrop: (id <NSDraggingInfo>)item
    row: (int)row
    dropOperation:(NSTableViewDropOperation)op
{
    // This method is called when the mouse is released over an outline view that previously decided to allow 
    // a drop via the validateDrop method.  The data source should incorporate the data from the dragging 
    // pasteboard at this time.
    NSPasteboard *pboard = [item draggingPasteboard];	// get the paste board
    NSString *aString;
    
    if ([pboard availableTypeFromArray:[NSArray arrayWithObjects: NSFilenamesPboardType, FileListItemType, nil]])
    {
        // test to see if the string for the type we defined in the paste board.
        // if doesn't, do nothing.
        aString = [pboard stringForType: FileListItemType];
        
        if (aString) {
            // handle move of an item in the table
            // remove the index that got dragged, now that we are accepting the dragging
            id obj = [m_fileList objectAtIndex: m_draggedRow];
            [obj retain];
            [self removeObjectAtArrangedObjectIndex: m_draggedRow];
            
            // insert the new string (same one that got dragger) into the array
            if (row > [m_fileList count])
                [self addObject: obj];
            else
                [self insertObject: obj atArrangedObjectIndex: (row > m_draggedRow) ? (row-1) : row];
        
            [obj release];
            [self reloadData];
        }
        else {
            // handle add of a new filename(s)
            NSArray *filenames = [[pboard propertyListForType:NSFilenamesPboardType] 
                                    sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
            
            for (NSString* filename in filenames) {
                Transcoder* transcoder = [self transcoderForFileName: filename];
                [self addObject: transcoder];
                [transcoder release];
            }
            
            [self reloadData];
            [[AppController instance] uiChanged];    
            [[AppController instance] updateEncodingInfo];    
        }
    }
    
    return YES;
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
    // If we have only one item selected, set it otherwise set nothing
    int index = ([m_fileListView numberOfSelectedRows] != 1) ? -1 : [m_fileListView selectedRow];
    
    // Set the current movie
    NSString* filename = [(index < 0) ? nil : [m_fileList objectAtIndex:index] inputFileInfo].filename;
    [[AppController instance].moviePanelController setMovie:filename];

    // Update metadata panel
    [self updateMetadataPanelState];
    [self reloadData];



}

// End of delegation methods

-(void) addFile:(NSString*) filename
{
    Transcoder* transcoder = [self transcoderForFileName: filename];
    [self addObject:transcoder];
    [transcoder release];
    [[AppController instance] uiChanged];    
    [[AppController instance] updateEncodingInfo];    
}

-(IBAction)addFiles:(id)sender
{
    // Ask for file names
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:YES];
    [panel setCanChooseDirectories:NO];
    [panel setCanCreateDirectories:NO];
    [panel setAllowsMultipleSelection:YES];
    [panel setTitle:@"Choose a File"];
    [panel setPrompt:@"Add"];
    if ([panel runModalForTypes: nil] == NSOKButton) {
        for (NSString* filename in [panel filenames])
            [self addFile:filename];
    }
}

- (IBAction)remove:(id)sender
{
    NSArray* selectedObjects = [self selectedObjects];
    for (Transcoder* transcoder in selectedObjects) {
        if ([transcoder fileStatus] == FS_ENCODING || [transcoder fileStatus] == FS_PAUSED) {
            NSString* filename = [[[transcoder inputFileInfo] filename] lastPathComponent];
            NSBeginAlertSheet([NSString stringWithFormat:@"Unable to remove %@", filename], nil, nil, nil, [[NSApplication sharedApplication] mainWindow], 
                            nil, nil, nil, nil, 
                            @"File is being encoded. Stop encoding then try again.");
        }
        else {
            [self removeObject:transcoder];
            [[AppController instance] updateEncodingInfo];
        }
    }
}

-(IBAction)clearAll:(id)sender
{
    [self selectAll:sender];
    [self remove:sender];
    [self setSearchBox];
}

-(IBAction)selectAll:(id)sender
{
    [self setSelectedObjects:[self arrangedObjects]];
    [self setSearchBox];
}

-(id) selection
{
    if ([[self selectionIndexes] count] != 1) 
        return nil;
        
    [self setSearchBox];
    return [[self arrangedObjects] objectAtIndex:[self selectionIndex]];
}

- (IBAction)selectNext:(id)sender
{
    if ([[self selectionIndexes] count] == 0)
        [self setSelectionIndex:0];
    else if ([[self selectionIndexes] count] > 1)
        [self setSelectionIndex:[self selectionIndex]];
    else
        [super selectNext:sender];
    [self setSearchBox];
}

- (IBAction)selectPrevious:(id)sender
{
    if ([[self selectionIndexes] count] == 0)
        [self setSelectionIndex:[[self arrangedObjects] count] - 1];
    else if ([[self selectionIndexes] count] > 1)
        [self setSelectionIndex:[[self selectionIndexes] lastIndex]];
    else
        [super selectPrevious:sender];
    [self setSearchBox];
}

-(void) updateMetadataPanelState
{
    Transcoder* transcoder = nil;
    if ([m_fileListView numberOfSelectedRows] == 1)
        transcoder = [m_fileList objectAtIndex:[m_fileListView selectedRow]];
    
    // Enable or disable metadata panel based on file type
    NSString* fileType = nil;
    
    if ([[[AppController instance] deviceController] shouldWriteMetadataToInputFile])
        fileType = [transcoder inputFileInfo].format;
    else
        fileType = [transcoder outputFileInfo].format;
        
    [[AppController instance].fileInfoPanelController setMetadataStateForFileType:fileType];
}

- (id)valueForUndefinedKey:(NSString *)key
{
    NSLog(@"*** FileListController::valueForUndefinedKey:%@\n", key);
    return nil;
}

@end
