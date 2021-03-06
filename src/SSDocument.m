/*
 * Copyright (c) 2008 Christophe Tournery, Gunnar Schaefer
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#import "SSDocument.h"
#import "SSWindowController.h"


@interface SSDocument (Private)

- (NSString *)promptForPDFPassword;

@end


@implementation SSDocument

- (id)init
{
    if ((self = [super init]))
    {
        pdfDocRef =         NULL;
        hasNAVFile =        NO;
        navPageNbrSlides =  nil;
        navPageNbrNotes =   nil;
    }
    return self;
}

- (void)dealloc
{
    [self setPdfDocRef:NULL];
    [self setNavPageNbrSlides:nil];
    [self setNavPageNbrNotes:nil];
    [super dealloc];
}

- (void)makeWindowControllers
{
    SSWindowController * ctrl = [[SSWindowController alloc] init];
    [self addWindowController:ctrl];
}

//- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError
//{
//    // Insert code here to write your document to data of the specified type. If the given outError != NULL, ensure that you set *outError when returning nil.
//
//    // You can also choose to override -fileWrapperOfType:error:, -writeToURL:ofType:error:, or -writeToURL:ofType:forSaveOperation:originalContentsURL:error: instead.
//
//    // For applications targeted for Panther or earlier systems, you should use the deprecated API -dataRepresentationOfType:. In this case you can also choose to override -fileWrapperRepresentationOfType: or -writeToFile:ofType: instead.
//
//    return nil;
//}

//- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError
//{
//    // Insert code here to read your document from the given data of the specified type.  If the given outError != NULL, ensure that you set *outError when returning NO.
//
//    // You can also choose to override -readFromFileWrapper:ofType:error: or -readFromURL:ofType:error: instead.
//
//    // For applications targeted for Panther or earlier systems, you should use the deprecated API -loadDataRepresentation:ofType. In this case you can also choose to override -readFromFile:ofType: or -loadFileWrapperRepresentation:ofType: instead.
//
//    return YES;
//}

- (BOOL)readFromURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError **)outError
{
    CGPDFDocumentRef ref = NULL;

    // load PDF document

    ref = CGPDFDocumentCreateWithURL( (CFURLRef)absoluteURL );
    if (ref == NULL)
        return NO;

    // prompt for password to decrypt the document

    if (CGPDFDocumentIsEncrypted(ref) && ! CGPDFDocumentIsUnlocked(ref))
    {
        NSString * passwd = nil;
        do
        {
            passwd = [self promptForPDFPassword];
            if (passwd == nil)
            {
                CGPDFDocumentRelease(ref);
                NSLog(@"Could not decrypt document!");
                return NO;
            }
        }
        while (! CGPDFDocumentUnlockWithPassword(ref, [passwd UTF8String]));
    }

    //TODO: check file type
    size_t pageCount = CGPDFDocumentGetNumberOfPages(ref);
    if (pageCount == 0)
    {
        CGPDFDocumentRelease(ref);
        //TODO: return an error
        NSLog(@"PDF document needs at least one page!");
        return NO;
    }

    // save handle to PDF document

    [self setPdfDocRef:ref];
    CGPDFDocumentRelease(ref);

    // load NAV file if found

    [self loadNAVFile];

    return YES;
}

@synthesize pdfDocRef;
- (void)setPdfDocRef:(CGPDFDocumentRef)newPdfDocRef
{
    if (pdfDocRef != newPdfDocRef)
    {
        CGPDFDocumentRelease(pdfDocRef);
        pdfDocRef = CGPDFDocumentRetain(newPdfDocRef);
    }
}

@synthesize hasNAVFile;
@synthesize navPageNbrSlides;
@synthesize navPageNbrNotes;

- (size_t)numberOfPages
{
    if (pdfDocRef != NULL)
        return CGPDFDocumentGetNumberOfPages(pdfDocRef);
    else
        return 0;
}

/**
 * Prompt for a password to decrypt PDF.
 * If the user dismisses the dialog with the 'Ok' button, return the typed password (possibly an empty string)
 * If the user dismisses the dialog with the 'Cancel' button, return nil.
 */
- (NSString *)promptForPDFPassword
{
    NSRect              rect;
    NSInteger           ret;
    NSAlert             * theAlert =    nil;
    NSSecureTextField   * passwdField = nil;
    NSString            * passwd =      nil;

    // prepare password field as an accessory view

    passwdField =   [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0,0,300,20)];
    [passwdField sizeToFit];
    rect =          [passwdField frame];
    [passwdField setFrameSize:(NSSize){300,rect.size.height}];

    // prepare the "alert"

    theAlert =      [NSAlert alertWithMessageText:@"PDF document protected."
                                    defaultButton:@"OK"
                                  alternateButton:@"Cancel"
                                      otherButton:nil
                        informativeTextWithFormat:@"Enter a password to open the document."];
    [theAlert setAccessoryView:passwdField];
    [theAlert layout];
    [[theAlert window] setInitialFirstResponder:passwdField];

    // read user input

    ret =           [theAlert runModal];
    if (ret == NSAlertDefaultReturn)
        passwd =    [passwdField stringValue];
    return passwd;
}

- (BOOL)loadNAVFile
{
    BOOL        navFileParsed =     NO;
    size_t      pageCount =         0;
    NSString    * navFileStr =      nil;
    NSArray     * pageNbrsSlides =  nil;
    NSArray     * pageNbrsNotes =   nil;

    pageCount =     CGPDFDocumentGetNumberOfPages(pdfDocRef);

    // check if NAV file is embedded

    navFileStr = [self getEmbeddedNAVFile];

    // if not, check if NAV file is next to PDF file

    if (navFileStr == nil)
    {
        NSString * navPath =    [[[[self fileURL] path] stringByDeletingPathExtension] stringByAppendingPathExtension:@"nav"];
        BOOL isDirectory =      FALSE;
        navFileParsed =         [[NSFileManager defaultManager] fileExistsAtPath:navPath
                                                                     isDirectory:&isDirectory];
        navFileParsed &=        !isDirectory;
        if (navFileParsed)
        {
            // read NAV file
            NSStringEncoding encoding;
            navFileStr = [NSString stringWithContentsOfFile:navPath usedEncoding:&encoding error:NULL];
        }
    }

    // parse NAV file

    if (navFileStr != nil)
        navFileParsed = [SSDocument parseNAVFileFromStr:navFileStr slides1:&pageNbrsSlides slides2:&pageNbrsNotes];

    if (navFileParsed)
    {
        [self setNavPageNbrSlides:pageNbrsSlides];
        [self setNavPageNbrNotes:pageNbrsNotes];
    }
    else
    {
        [self setNavPageNbrSlides:nil];
        [self setNavPageNbrNotes:nil];
    }
    [self setHasNAVFile:navFileParsed];

    return [self hasNAVFile];
}

// -------------------------------------------------------------

/**
 * Get a the NAV file embedded in the PDF as a NSString.
 * If the NAV file is not found, return nil.
 * You do not own the returned string, so don't release it.
 */
- (NSString *)getEmbeddedNAVFile
{
    size_t              count =         0;
    CGPDFDictionaryRef  catalog =       NULL;
    CGPDFDictionaryRef  namesDict =     NULL;
    CGPDFDictionaryRef  efDict =        NULL;
    CGPDFDictionaryRef  fileSpecDict =  NULL;
    CGPDFDictionaryRef  efItemDict =    NULL;
    CGPDFArrayRef       efArray =       NULL;
    CGPDFStringRef      cgpdfFilename = NULL;
    NSString            * emFilename =  NULL;
    NSString            * navContent =  nil;
    CGPDFStreamRef      fileStream =    NULL;
    NSData              * cfData =      nil;
    CGPDFDataFormat     dataFormat;

    if (pdfDocRef == NULL)
        return nil;

    catalog = CGPDFDocumentGetCatalog(pdfDocRef);
    if (! CGPDFDictionaryGetDictionary(catalog, "Names", &namesDict))
        return nil;
    if (! CGPDFDictionaryGetDictionary(namesDict, "EmbeddedFiles", &efDict))
        return nil;
    if (! CGPDFDictionaryGetArray(efDict, "Names", &efArray))
        return nil;

    count = CGPDFArrayGetCount(efArray);
    for (size_t i = 0; i < count; i++)
    {
        if (! CGPDFArrayGetDictionary(efArray, i, &fileSpecDict))
            continue;
        if (! CGPDFDictionaryGetString(fileSpecDict, "F", &cgpdfFilename))
            continue;

        // is this a ".nav" file?
        emFilename = (NSString *)CGPDFStringCopyTextString(cgpdfFilename);
        if ([[(NSString *)emFilename pathExtension] caseInsensitiveCompare:@"nav"] != NSOrderedSame)
        {
            [emFilename release];
            continue;
        }
        [emFilename release];

        if (! CGPDFDictionaryGetDictionary(fileSpecDict, "EF", &efItemDict))
            continue;
        if (! CGPDFDictionaryGetStream(efItemDict, "F", &fileStream))
            continue;

        cfData = (NSData *)CGPDFStreamCopyData(fileStream, &dataFormat);
        navContent = [[[NSString alloc] initWithData:cfData encoding:NSUTF8StringEncoding] autorelease];
        [cfData release];
        break;
    }

    if (navContent != NULL)
        return (NSString *)navContent;
    return nil;
}

/**
 * Parse a NAV file to get page numbers of slides and notes.
 * navFileStr:  a string of the NAV file's content
 * pSlides1:    on return, an array of page numbers for the slides (autoreleased)
 * pSlides2:    on return, an array of page numbers for the notes (autoreleased)
 *
 * Note: on input, *pSlides1 and *pSlides2 should point to nil or to autoreleased objects.
 */
+ (BOOL)parseNAVFileFromStr:(NSString *)navFileStr slides1:(NSArray **)pSlides1 slides2:(NSArray **)pSlides2
{
    int             i, j, k, l;
    NSScanner       * theScanner;
    NSInteger       nbPages;
    NSInteger       first;
    NSInteger       last;
    NSMutableArray  * firstFrames = nil;
    NSMutableArray  * lastFrames =  nil;
    NSMutableArray  * slides1 =     nil;
    NSMutableArray  * slides2 =     nil;

    if (navFileStr == nil)
        return NO;

    // read the total number of pages

    theScanner = [NSScanner scannerWithString:navFileStr];
    NSString * DOCUMENTPAGES = @"\\headcommand {\\beamer@documentpages {";

    while ([theScanner isAtEnd] == NO)
    {
        if ([theScanner scanUpToString:DOCUMENTPAGES intoString:NULL] &&
            [theScanner scanString:DOCUMENTPAGES intoString:NULL] &&
            [theScanner scanInteger:&nbPages])
        {
            break;
        }
    }

    // allocate arrays

    firstFrames =   [NSMutableArray arrayWithCapacity:nbPages];
    lastFrames =    [NSMutableArray arrayWithCapacity:nbPages];
    slides1 =       [NSMutableArray arrayWithCapacity:nbPages];
    slides2 =       [NSMutableArray arrayWithCapacity:nbPages];

    // read page numbers of frames (as opposed to notes)

    theScanner = [NSScanner scannerWithString:navFileStr];
    NSString * FRAMEPAGES = @"\\headcommand {\\beamer@framepages {";

    while ([theScanner isAtEnd] == NO)
    {
        if ([theScanner scanUpToString:FRAMEPAGES intoString:NULL] &&
            [theScanner scanString:FRAMEPAGES intoString:NULL] &&
            [theScanner scanInteger:&first] &&
            [theScanner scanString:@"}{" intoString:NULL] &&
            [theScanner scanInteger:&last])
        {
            [firstFrames addObject:[NSNumber numberWithUnsignedInt:first]];
            [lastFrames  addObject:[NSNumber numberWithUnsignedInt:last]];
        }
    }
    // append total number of pages +1 to the list of first pages
    [firstFrames addObject:[NSNumber numberWithInt:nbPages+1]];

    // generate indices of the pages to be displayed on each screen

    k = 0;
    for (i = 0; i < [firstFrames count]-1; i++)
    {
        for (j = [[firstFrames objectAtIndex:i] unsignedIntValue]; j <= [[lastFrames objectAtIndex:i] unsignedIntValue]; j++, k++)
        {
            int nbNotes = [[firstFrames objectAtIndex:i+1] unsignedIntValue] - [[lastFrames objectAtIndex:i] unsignedIntValue] - 1;
            assert(nbNotes >= 0);
            if (nbNotes == 0)
            {
                // no note, mirror slides
                [slides1 addObject:[NSNumber numberWithUnsignedInt:j]];
                [slides2 addObject:[NSNumber numberWithUnsignedInt:j]];
            }
            else
            {
                // one or more note pages
                for (l = 0; l < nbNotes; l++)
                {
                    [slides1 addObject:[NSNumber numberWithUnsignedInt:j]];
                    [slides2 addObject:[NSNumber numberWithUnsignedInt:[[lastFrames objectAtIndex:i] unsignedIntValue]+1+l]];
                }
            }
        }
    }

    *pSlides1 = slides1;
    *pSlides2 = slides2;
    return YES;
}

@end
