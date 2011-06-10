//	Copyright (c) 2007 Adam Knight
//
//	Permission is hereby granted, free of charge, to any person obtaining a
//	copy of this software and associated documentation files (the
//	"Software"), to deal in the Software without restriction, including
//	without limitation the rights to use, copy, modify, merge, publish,
//	distribute, sublicense, and/or sell copies of the Software, and to
//	permit persons to whom the Software is furnished to do so, subject to
//	the following conditions:
//
//	The above copyright notice and this permission notice shall be included
//	in all copies or substantial portions of the Software.
//
//	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
//	OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
//	MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
//	IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
//	CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
//	TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
//	SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//    
//      Original from http://www.macgeekery.com/gspot/2007-02/setting_an_icon_from_the_cli
//      To compile: gcc -arch i386 -arch ppc -framework AppKit -o SetIcon SetIcon.m
#import <AppKit/AppKit.h>
#include <getopt.h>

void usage() {
	printf("usage: SetFile -i image target\n");
	exit(EXIT_FAILURE);
}

int main (int argc, char * argv[]) {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	char option;
	NSString *sourceFile = nil;
	NSString *targetFile = nil;
	BOOL result;
	
	while ((option = getopt(argc, argv, "i:")) != -1) {
		switch (option) {
			case 'i':
				sourceFile = [NSString stringWithCString:optarg];
				break;
			default:
				usage();
				break;
		}
	}
	
	if (optind < argc)
		targetFile = [NSString stringWithCString:(char*)argv[optind]];
	else
		usage();
	
	// Begin
	result = [[NSFileManager defaultManager] fileExistsAtPath:sourceFile];

	if (!result) {
		printf("file does not exist: %s\n", [sourceFile cString]);
		exit(EXIT_FAILURE);
	}

	NSImage *icon = [[[NSImage alloc] initWithContentsOfFile:sourceFile] autorelease];
	
	if (!icon) {
		printf("file is not a valid image file: %s\n", [sourceFile cString]);
		exit(EXIT_FAILURE);
	}
	
	result = [[NSFileManager defaultManager] fileExistsAtPath:targetFile];

	if (!result) {
		printf("file does not exist: %s\n", [targetFile cString]);
		exit(EXIT_FAILURE);
	}
	
	result = [[NSWorkspace sharedWorkspace] setIcon:icon forFile:targetFile options:0];

	if (!result) {
		printf("failed to set icon for file: %s\n", [targetFile cString]);
		exit(EXIT_FAILURE);
	}
	
	[pool release];
    return 0;
}
