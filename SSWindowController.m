//
//  SSDocumentController.m
//  PDFPresenter
//
//  Created by Christophe Tournery on 11/04/2008.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "SSWindowController.h"
#import "SSDocument.h"
#import "NSScreen_Extension.h"


@implementation SSWindowController

+ (void)initialize
{
    NSUserDefaults *defaults =  [NSUserDefaults standardUserDefaults];
    NSDictionary *appDefaults = [NSDictionary dictionaryWithObject:@"YES"
                                                            forKey:@"TestDefaults"];
    [defaults registerDefaults:appDefaults];
}

// -------------------------------------------------------------
// Overridding init implementations
// This class should only work with the Nib file 'SSDocument' so
// we are preventing any load operation with a specific Nib file
// -------------------------------------------------------------

- (id)init
{
    if ((self = [super initWithWindowNibName:@"SSDocument"]))
    {
        splitView =             nil;
        pdfViewCG1 =            nil;
        pdfViewCG2 =            nil;
        slideshowModeChooser =  nil;
        pageNbrs1 =             nil;
        pageNbrs2 =             nil;
        currentPageIdx =        0;
        slideshowMode =         SlideshowModeMirror;
        screensSwapped =        NO;
        screens =               [NSScreen screens];
        
        if ([screens count] == 0)
        {
            screen1 =   nil;
            screen2 =   nil;
        }
        else if ([screens count] == 1)
        {
            // only one screen is present
            screen1 =   [screens objectAtIndex:0];
            screen2 =   nil;
        }
        else
        {
            // screen 1: try to get a non built-in display
            // screen 2: try to get a built-in display or by default fall back on the display with the menu bar

            NSMutableArray * builtinScreens =   [NSMutableArray arrayWithCapacity:1];
            NSMutableArray * externalScreens =  [NSMutableArray arrayWithCapacity:1];
            [NSScreen builtin:builtinScreens AndExternalScreens:externalScreens];
            
            if ([builtinScreens count] > 0 && [externalScreens count] > 0)
            {
                screen1 =   [externalScreens objectAtIndex:0];
                screen2 =   [builtinScreens objectAtIndex:0];
            }
            else
            {
                screen1 =   [screens objectAtIndex:1];
                screen2 =   [screens objectAtIndex:0]; // display with the menu bar
            }
        }
    }
    return self;
}

- (id)initWithWindowNibName:(NSString *)windowNibName
{
    NSLog(@"Error: trying to initialize SSDocumentController with a specific Nib file!");
    [self release];
    return nil;
}

// -------------------------------------------------------------
// Additional initialization once Nib is loaded
// -------------------------------------------------------------

- (void)windowDidLoad
{
    NSArray * draggableType =   nil;

    // try to auto-detect document type
    // set slideshow type and recompute page numbers accordingly

    [self setSlideshowMode:[self guessSlideshowMode]];

    // register PDF as an acceptable drag type

    draggableType = [NSArray arrayWithObject:NSURLPboardType];
    [[self window] registerForDraggedTypes:draggableType];
}

// -------------------------------------------------------------
// Properties implementation
// -------------------------------------------------------------

- (NSArray *)pageNbrs1
{
    return pageNbrs1;
}
- (void)setPageNbrs1:(NSArray *)newPageNbrs1
{
    [pageNbrs1 autorelease];
    pageNbrs1 = [newPageNbrs1 copy];
    [self setCurrentPageIdx:currentPageIdx];    // load current page
}

- (NSArray *)pageNbrs2
{
    return pageNbrs2;
}
- (void)setPageNbrs2:(NSArray *)newPageNbrs2
{
    [pageNbrs2 autorelease];
    pageNbrs2 = [newPageNbrs2 copy];
    [self setCurrentPageIdx:currentPageIdx];    // load current page
}

- (size_t)currentPageIdx
{
    return currentPageIdx;
}
- (void)setCurrentPageIdx:(size_t)newPageIdx
{
    size_t pageNbr1, pageNbr2;

    if (pageNbrs1 == nil || pageNbrs2 == nil || [pageNbrs1 count] == 0 || [pageNbrs2 count] == 0)
    {
        currentPageIdx = 0;
        [pdfViewCG1 setPdfPage:NULL];
        [pdfViewCG2 setPdfPage:NULL];
        return;
    }
    else
    {
        currentPageIdx = MIN(newPageIdx, MIN([pageNbrs1 count], [pageNbrs2 count])-1);
    }

    pageNbr1 = [[pageNbrs1 objectAtIndex:currentPageIdx] unsignedIntValue];
    pageNbr2 = [[pageNbrs2 objectAtIndex:currentPageIdx] unsignedIntValue];    
    if (! screensSwapped)
    {
        [pdfViewCG1 setPdfPage:CGPDFDocumentGetPage([[self document] pdfDocRef], pageNbr1)];
        [pdfViewCG2 setPdfPage:CGPDFDocumentGetPage([[self document] pdfDocRef], pageNbr2)];
    }
    else
    {
        [pdfViewCG1 setPdfPage:CGPDFDocumentGetPage([[self document] pdfDocRef], pageNbr2)];
        [pdfViewCG2 setPdfPage:CGPDFDocumentGetPage([[self document] pdfDocRef], pageNbr1)];
    }
}

@synthesize slideshowMode;
- (void)setSlideshowMode:(SlideshowMode)newSlideshowMode
{
    slideshowMode = newSlideshowMode;
    [self computePageNumbersAndCropBox];
}

@synthesize screensSwapped;
- (void)setScreensSwapped:(BOOL)newScreensSwapped
{
    screensSwapped = newScreensSwapped;
    [self computePageNumbersAndCropBox];
}

@synthesize screens;
@synthesize screen1;
@synthesize screen2;

// -------------------------------------------------------------
//
// -------------------------------------------------------------

- (SlideshowMode)guessSlideshowMode
{
    CGRect          rect;
    CGPDFPageRef    page = NULL;

    if ([[self document] numberOfPages] < 1)
        return SlideshowModeMirror;

    page = CGPDFDocumentGetPage([[self document] pdfDocRef], 1);
    rect = CGPDFPageGetBoxRect(page, kCGPDFCropBox);

    // consider 2.39:1 the widest commonly found aspect ratio of a single frame
    if ((rect.size.width / rect.size.height) >= 2.39)
        return SlideshowModeWidePage;
    else if ([[self document] hasNAVFile])
        return SlideshowModeInterleaved;
    else
        return SlideshowModeMirror;
}

- (void)computePageNumbersAndCropBox
{
    size_t          pageCount;
    NSMutableArray  * pages1 = nil;
    NSMutableArray  * pages2 = nil;

    // build pages numbers according to slideshow mode

    pageCount = [[self document] numberOfPages];
    pages1 =    [NSMutableArray arrayWithCapacity:pageCount];
    pages2 =    [NSMutableArray arrayWithCapacity:pageCount];

    switch (slideshowMode)
    {
        case SlideshowModeMirror:
            [pdfViewCG1 setCropType:FULL_PAGE];
            [pdfViewCG2 setCropType:FULL_PAGE];

            for (int i = 0; i < pageCount; i++)
            {
                [pages1 addObject:[NSNumber numberWithUnsignedInt:i+1]];
                [pages2 addObject:[NSNumber numberWithUnsignedInt:i+1]];
            }
            break;

        case SlideshowModeWidePage:
            if (! screensSwapped)
            {
                [pdfViewCG1 setCropType:LEFT_HALF];
                [pdfViewCG2 setCropType:RIGHT_HALF];
            }
            else
            {
                [pdfViewCG1 setCropType:RIGHT_HALF];
                [pdfViewCG2 setCropType:LEFT_HALF];
            }

            for (int i = 0; i < pageCount; i++)
            {
                [pages1 addObject:[NSNumber numberWithUnsignedInt:i+1]];
                [pages2 addObject:[NSNumber numberWithUnsignedInt:i+1]];
            }
            break;

        case SlideshowModeInterleaved:
            [pdfViewCG1 setCropType:FULL_PAGE];
            [pdfViewCG2 setCropType:FULL_PAGE];

            if ([[self document] hasNAVFile])
            {
                [pages1 setArray:[[self document] navPageNbrSlides]];
                [pages2 setArray:[[self document] navPageNbrNotes]];
            }
            else
            {
                // no NAV file, file must contain an even number of pages
                if (pageCount % 2 == 1)
                {
                    NSAlert * theAlert = [NSAlert alertWithMessageText:@"Not a proper interleaved format."
                                                         defaultButton:@"OK"
                                                       alternateButton:nil
                                                           otherButton:nil
                                             informativeTextWithFormat:@"This document contains an odd number of pages.\nFalling back to Mirror mode."];
                    [theAlert beginSheetModalForWindow:[self window]
                                         modalDelegate:self
                                        didEndSelector:nil
                                           contextInfo:nil];
                    [self setSlideshowMode:SlideshowModeMirror];
                    return;
                }

                // build arrays of interleaved page numbers
                for (int i = 0; i < pageCount; i += 2)
                {
                    [pages1 addObject:[NSNumber numberWithUnsignedInt:i+1]];
                    [pages2 addObject:[NSNumber numberWithUnsignedInt:i+2]];
                }
            }
            break;
    }

    [self setPageNbrs1:pages1];
    [self setPageNbrs2:pages2];
}

// -------------------------------------------------------------
// Drag and Drop support (as delegate of the NSWindow)
// -------------------------------------------------------------

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
    NSPasteboard    * pboard;
    NSDragOperation sourceDragMask;

    sourceDragMask =    [sender draggingSourceOperationMask];
    pboard =            [sender draggingPasteboard];

    if ( [[pboard types] containsObject:NSURLPboardType] )
        if (sourceDragMask & NSDragOperationLink)
            return NSDragOperationLink;
    return NSDragOperationNone;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
    NSPasteboard    * pboard;
    NSURL           * fileURL;
    NSDragOperation sourceDragMask;
    BOOL            ret;

    sourceDragMask =    [sender draggingSourceOperationMask];
    pboard =            [sender draggingPasteboard];

    if ( (ret = [[pboard types] containsObject:NSURLPboardType]) )
    {
        fileURL =       [NSURL URLFromPasteboard:pboard];
        ret =           [[self document] readFromURL:fileURL ofType:nil error:NULL];
        if (ret)
        {
            [self setSlideshowMode:[self guessSlideshowMode]];
            [[self window] setTitleWithRepresentedFilename:[fileURL path]];
        }
    }
    return ret;
}

// -------------------------------------------------------------
// Events: interpret key event as action when in full-screen
// -------------------------------------------------------------

- (void)keyDown:(NSEvent *)theEvent
{
    [self interpretKeyEvents:[NSArray arrayWithObject:theEvent]];
}

// -------------------------------------------------------------
// Events: go to previous page
// -------------------------------------------------------------

- (void)moveUp:(id)sender
{
    [self goToPrevPage];
}
- (void)moveLeft:(id)sender
{
    [self goToPrevPage];
}
- (void)goToPrevPage
{
    if (currentPageIdx > 0)
        [self setCurrentPageIdx:currentPageIdx-1];
}

// -------------------------------------------------------------
// Events: go to next page
// -------------------------------------------------------------

- (void)moveDown:(id)sender
{
    [self goToNextPage];
}
- (void)moveRight:(id)sender
{
    [self goToNextPage];
}
- (void)goToNextPage
{
    size_t nextPageIdx = currentPageIdx + 1;

    if (pageNbrs1 == nil || pageNbrs2 == nil)
        return;
    
    if (nextPageIdx < [pageNbrs1 count] && nextPageIdx < [pageNbrs2 count])
        [self setCurrentPageIdx:nextPageIdx];
}

// -------------------------------------------------------------
// Events: go to first page
// -------------------------------------------------------------

- (void)pageUp:(id)sender
{
    [self goToFirstPage];
}
- (void)goToFirstPage
{
    [self setCurrentPageIdx:0];
}

// -------------------------------------------------------------
// Events: go to last page
// -------------------------------------------------------------

- (void)pageDown:(id)sender
{
    [self goToLastPage];
}
- (void)goToLastPage
{
    if (pageNbrs1 == nil || pageNbrs2 == nil)
        return;
    
    [self setCurrentPageIdx:MAX([pageNbrs1 count], [pageNbrs2 count])-1];
}

// -------------------------------------------------------------
// Events: go to full-screen mode and exit from it
// -------------------------------------------------------------

- (void)enterFullScreenMode:(id)sender
{
    NSDictionary * options = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:NO] forKey:NSFullScreenModeAllScreens];
    
    // save current size before going full-screen

    [pdfViewCG1 setSavedFrame:[pdfViewCG1 frame]];
    [pdfViewCG2 setSavedFrame:[pdfViewCG2 frame]];

    // go full-screen
    
    if (screen1 != nil)
    {
        [pdfViewCG1 enterFullScreenMode:screen1 withOptions:options];
        [pdfViewCG1 setNextResponder:self];
    }
    if (screen2 != nil)
    {
        [pdfViewCG2 enterFullScreenMode:screen2 withOptions:options];
        [pdfViewCG2 setNextResponder:self];
    }
}

- (void)cancelOperation:(id)sender
{
    // exit full-screen mode
    
    if ([pdfViewCG1 isInFullScreenMode])
        [pdfViewCG1 exitFullScreenModeWithOptions:nil];
    if ([pdfViewCG2 isInFullScreenMode])
        [pdfViewCG2 exitFullScreenModeWithOptions:nil];

    // recover original position and previous size, in case only one view went to full-screen mode
    
    [pdfViewCG1 retain];
    [pdfViewCG2 retain];
    
    [pdfViewCG1 removeFromSuperview];
    [pdfViewCG2 removeFromSuperview];
    [pdfViewCG1 setFrame:[pdfViewCG1 savedFrame]];
    [pdfViewCG2 setFrame:[pdfViewCG2 savedFrame]];
    [splitView  addSubview:pdfViewCG1];
    [splitView  addSubview:pdfViewCG2 positioned:NSWindowAbove relativeTo:pdfViewCG1];
    [pdfViewCG1 setNeedsDisplay:YES];
    [pdfViewCG2 setNeedsDisplay:YES];
    [splitView  setNeedsDisplay:YES];
    
    [pdfViewCG1 release];
    [pdfViewCG2 release];
}

// -------------------------------------------------------------
//
// -------------------------------------------------------------

/**
 * Constraining split view to split evenly
 */
- (CGFloat)splitView:(NSSplitView *)sender constrainSplitPosition:(CGFloat)proposedPosition ofSubviewAt:(NSInteger)offset
{
    NSRect rect =       [sender bounds];
    CGFloat halfSize =  rect.size.width / 2.f;
    if (fabs(proposedPosition - halfSize) > 8)
        return proposedPosition;
    return halfSize;
}

// -------------------------------------------------------------

// -------------------------------------------------------------

// -------------------------------------------------------------

@end
