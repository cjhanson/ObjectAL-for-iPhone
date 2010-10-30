//
//  OALAudioPlayerAudioQueueAudioFile.m
//  ObjectAL
//
//  Created by CJ Hanson on 30-OCT-2010
//
// Copyright 2010 CJ Hanson
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// Note: You are NOT required to make the license available from within your
// iOS application. Including it in your project is sufficient.
//
// Attribution is not required, but appreciated :)
//

#import "OALAudioPlayerAudioQueueAudioFile.h"

@implementation OALAudioPlayerAudioQueueAudioFile

- (id)initWithContentsOfURL:(NSURL *)inUrl error:(NSError **)outError
{
	self = [super init];
	if(self){
		
		[self performSelector:@selector(postPlayerReadyNotification) withObject:nil afterDelay:0.01];
	}
	return self;
}

- (id)initWithData:(NSData *)data error:(NSError **)outError
{
	[self doesNotRecognizeSelector:_cmd];
	[self release];
	return nil;
}

@end
