/* Copyright © 2007-2008 The Sequential Project. All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a
copy of this software and associated documentation files (the "Software"),
to deal with the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following conditions:
1. Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimers.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimers in the
   documentation and/or other materials provided with the distribution.
3. Neither the name of The Sequential Project nor the names of its
   contributors may be used to endorse or promote products derived from
   this Software without specific prior written permission.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
THE CONTRIBUTORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS WITH THE SOFTWARE. */
#import "PGWebAdapter.h"

// Models
#import "PGNode.h"
#import "PGURLConnection.h"
#import "PGResourceIdentifier.h"

// Controllers
#import "PGDocumentController.h"

// Categories
#import "NSObjectAdditions.h"

@implementation PGWebAdapter

#pragma mark PGResourceAdapter

+ (PGMatchPriority)matchPriorityForNode:(PGNode *)node
                   withInfo:(NSMutableDictionary *)info
{
	NSURL *const URL = [info objectForKey:PGURLKey];
	return !URL || [URL isFileURL] || [info objectForKey:PGURLResponseKey] || [node dataWithInfo:info] ? PGNotAMatch : PGMatchByIntrinsicAttribute;
}

#pragma mark PGURLConnectionDelegate Protocol

- (void)connectionLoadingDidProgress:(PGURLConnection *)sender
{
	if(sender == _mainConnection) [[self node] AE_postNotificationName:PGNodeLoadingDidProgressNotification];
}
- (void)connectionDidReceiveResponse:(PGURLConnection *)sender
{
	if(sender != _mainConnection) return;
	id const resp = [sender response];
	if([resp respondsToSelector:@selector(statusCode)] && ([resp statusCode] < 200 || [resp statusCode] >= 300)) {
		[_mainConnection cancelAndNotify:NO];
		[_faviconConnection cancelAndNotify:NO];
		[[self node] setError:[NSError errorWithDomain:PGNodeErrorDomain code:PGGenericError userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:NSLocalizedString(@"The error %u %@ was generated while loading the URL %@.", @"The URL returned a error status code. %u is replaced by the status code, the first %@ is replaced by the human-readable error (automatically localized), the second %@ is replaced by the full URL."), [resp statusCode], [NSHTTPURLResponse localizedStringForStatusCode:[resp statusCode]], [resp URL]] forKey:NSLocalizedDescriptionKey]]];
		[[self node] loadFinished];
	} else if(![[PGResourceAdapter adapterClassesInstantiated:NO forNode:[self node] withInfo:[NSDictionary dictionaryWithObjectsAndKeys:[resp MIMEType], PGMIMETypeKey, [NSNumber numberWithBool:YES], PGPromisesURLDataKey, nil]] count]) {
		[_mainConnection cancelAndNotify:YES];
		[_faviconConnection cancelAndNotify:YES];
	}
}
- (void)connectionDidSucceed:(PGURLConnection *)sender
{
	if(sender == _mainConnection) {
		[_faviconConnection cancelAndNotify:NO];
		NSURLResponse *const resp = [_mainConnection response];
		[[self node] continueLoadWithInfo:[NSDictionary dictionaryWithObjectsAndKeys:resp, PGURLResponseKey, [resp MIMEType], PGMIMETypeKey, [_mainConnection data], PGURLDataKey, nil]];
	} else if(sender == _faviconConnection) {
		NSImage *const favicon = [[[NSImage alloc] initWithData:[_faviconConnection data]] autorelease];
		if(favicon) [[self identifier] setIcon:favicon notify:YES]; // Don't clear the favicon we already have if we can't load a new one.
	}
}
- (void)connectionDidFail:(PGURLConnection *)sender
{
	if(sender != _mainConnection) return;
	[_faviconConnection cancelAndNotify:NO];
	[[self node] setError:[NSError errorWithDomain:PGNodeErrorDomain code:PGGenericError userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:NSLocalizedString(@"The URL %@ could not be loaded.", @"The URL could not be loaded for an unknown reason. %@ is replaced by the full URL."), [[_mainConnection request] URL]] forKey:NSLocalizedDescriptionKey]]];
	[[self node] loadFinished];
}
- (void)connectionDidCancel:(PGURLConnection *)sender
{
	if(sender != _mainConnection) return;
	[_faviconConnection cancelAndNotify:NO];
	[[self node] loadFinished];
}

#pragma mark PGResourceAdapting

- (float)loadingProgress
{
	return [_mainConnection progress];
}

#pragma mark PGResourceAdapter

- (void)load
{
	NSParameterAssert(![self canGetData]);
	NSURL *const URL = [[self info] objectForKey:PGURLKey];
	[_mainConnection cancelAndNotify:NO];
	[_mainConnection release];
	_mainConnection = [[PGURLConnection alloc] initWithRequest:[NSURLRequest requestWithURL:URL cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:15.0] delegate:self];
	[_faviconConnection cancelAndNotify:NO];
	[_faviconConnection release];
	_faviconConnection = [[PGURLConnection alloc] initWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"/favicon.ico" relativeToURL:URL] cachePolicy:NSURLRequestReturnCacheDataElseLoad timeoutInterval:15.0] delegate:self];
}

#pragma mark NSObject

- (void)dealloc
{
	[_mainConnection cancelAndNotify:NO];
	[_mainConnection release];
	[_faviconConnection cancelAndNotify:NO];
	[_faviconConnection release];
	[super dealloc];
}

@end
