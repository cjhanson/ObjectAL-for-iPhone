//
//  OALAudioPlayer.h
//  ObjectAL
//
//  Created by CJ Hanson on 29-OCT-2010
//  Based on code by Karl Stenerud
//
// Copyright 2010 CJ Hanson
// Copyright 2010 Karl Stenerud
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

#import "OALAudioPlayer.h"
#import "OALAudioPlayerAVAudioPlayer.h"
#import "OALAudioPlayerAVPlayer.h"
#import "OALAudioPlayerAudioQueueAVAssetReader.h"
#import "OALAudioPlayerAudioQueueAudioFile.h"
#import "OALAudioPlayerAudioUnitAVAssetReader.h"
#import "ObjectALMacros.h"

@implementation OALAudioPlayer

+ (Class) getClassForPlayerType:(OALAudioPlayerType)aPlayerType
{
	Class aClass = nil;
	switch(aPlayerType)
	{
		case OALAudioPlayerTypeAVAudioPlayer:
			aClass = [OALAudioPlayerAVAudioPlayer class];
			break;
		case OALAudioPlayerTypeAVPlayer:
			aClass = [OALAudioPlayerAVPlayer class];
			break;
		case OALAudioPlayerTypeAudioQueueAudioFile:
			aClass = [OALAudioPlayerAudioQueueAudioFile class];
			break;
		case OALAudioPlayerTypeAudioQueueAVAssetReader:
			aClass = [OALAudioPlayerAudioQueueAVAssetReader class];
			break;
		case OALAudioPlayerTypeAudioUnitAVAssetReader:
			aClass = [OALAudioPlayerAudioUnitAVAssetReader class];
			break;
		default:
			aClass = [OALAudioPlayerAVAudioPlayer class];
			break;
	}
	return aClass;
}

@synthesize playerType;

- (NSString *) description
{
	return [NSString stringWithFormat:@""
			"<%@ = %08X>\n"
			"  Type:         %d\n"
			"  URL:          %@\n"
			"  Status:       %d\n"
			"  State:        %d\n"
			"  Playing:      %s\n"
			"  CurrentTime:  %.2f\n"
			"  Duration:     %.2f\n"
			"  Loops:        %d",
			[self class],
			self,
			self.playerType,
			[self.url absoluteString],
			self.status,
			self.state,
			self.isPlaying,
			self.currentTime,
			self.duration,
			self.numberOfLoops
			];
}

- (void) dealloc
{
	[super dealloc];
}

- (id) init
{
	self = [super init];
	if(self){
		delegate = nil;
		playerType = OALAudioPlayerTypeInvalid;
		suspended = NO;
	}
	return self;
}

- (id) initWithContentsOfURL:(NSURL *)inURL seekTime:(NSTimeInterval)inSeekTime error:(NSError **)outError
{
	[self doesNotRecognizeSelector:_cmd];
	[self release];
	return nil;
}

- (void) setDelegate:(id <OALAudioPlayerDelegate>)d
{
	delegate = d;
}

- (id<OALAudioPlayerDelegate>) delegate
{
	return delegate;
}


/* get ready to play the sound. happens automatically on play. */
- (BOOL)prepareToPlay
{
	[self doesNotRecognizeSelector:_cmd];
	return NO;
}

/* sound is played asynchronously. */
- (BOOL)play
{
	[self doesNotRecognizeSelector:_cmd];
	return NO;
}

/* play a sound some time in the future. time should be greater than deviceCurrentTime. */
- (BOOL)playAtTime:(NSTimeInterval) time
{
	[self doesNotRecognizeSelector:_cmd];
	return NO;
}

/* pauses playback, but remains ready to play. */
- (void)pause
{
	[self doesNotRecognizeSelector:_cmd];
}

/* stops playback. no longer ready to play. */
- (void)stop
{
	[self doesNotRecognizeSelector:_cmd];
}

/* properties */

- (BOOL) isPlaying
{
	[self doesNotRecognizeSelector:_cmd];
	return NO;
}

- (NSUInteger) numberOfChannels
{
	[self doesNotRecognizeSelector:_cmd];
	return 0;
}

- (NSTimeInterval) duration
{
	[self doesNotRecognizeSelector:_cmd];
	return -1;
}

- (NSURL *) url
{
	[self doesNotRecognizeSelector:_cmd];
	return nil;
}

- (NSData *) data
{
	[self doesNotRecognizeSelector:_cmd];
	return nil;
}

- (void) setPan:(float)p
{
	[self doesNotRecognizeSelector:_cmd];
}

- (float) pan
{
	[self doesNotRecognizeSelector:_cmd];
	return -1;
}

- (void) setVolume:(float)v
{
	[self doesNotRecognizeSelector:_cmd];
}

- (float) volume
{
	[self doesNotRecognizeSelector:_cmd];
	return -1;
}

- (void) setCurrentTime:(NSTimeInterval)t
{
	[self doesNotRecognizeSelector:_cmd];
}

- (NSTimeInterval) currentTime
{
	[self doesNotRecognizeSelector:_cmd];
	return -1;
}

- (NSTimeInterval) deviceCurrentTime
{
	[self doesNotRecognizeSelector:_cmd];
	return -1;
}

- (void) setNumberOfLoops:(NSInteger)n
{
	[self doesNotRecognizeSelector:_cmd];
}

- (NSInteger) numberOfLoops
{
	[self doesNotRecognizeSelector:_cmd];
	return -2;
}

- (NSDictionary *) settings
{
	[self doesNotRecognizeSelector:_cmd];
	return nil;
}

/* metering */

- (void) setMeteringEnabled:(BOOL)yn
{
	[self doesNotRecognizeSelector:_cmd];
}

- (BOOL) isMeteringEnabled
{
	[self doesNotRecognizeSelector:_cmd];
	return NO;
}

/* call to refresh meter values */
- (void)updateMeters
{
	[self doesNotRecognizeSelector:_cmd];
}

/* returns peak power in decibels for a given channel */
- (float)peakPowerForChannel:(NSUInteger)channelNumber
{
	[self doesNotRecognizeSelector:_cmd];
	return -1;
}

/* returns average power in decibels for a given channel */
- (float)averagePowerForChannel:(NSUInteger)channelNumber
{
	[self doesNotRecognizeSelector:_cmd];
	return -1;
}

/*!
 @property status
 @abstract
 The ability of the receiver to be used for playback.
 
 @discussion
 The value of this property is an OALPlayerStatus that indicates whether the receiver can be used for playback. When
 the value of this property is OALPlayerStatusFailed, the receiver can no longer be used for playback and a new
 instance needs to be created in its place. When this happens, clients can check the value of the error property to
 determine the nature of the failure. This property is key value observable.
 */

- (OALPlayerStatus) status
{
	[self doesNotRecognizeSelector:_cmd];
	return OALPlayerStatusFailed;
}

/*!
 @property state
 @abstract
 The current playback state
 
 @discussion
 The value of this property is an OALPlayerState that indicates the current playback state.
 */

- (OALPlayerState) state
{
	[self doesNotRecognizeSelector:_cmd];
	return OALPlayerStateNotReady;
}

/*!
 @property error
 @abstract
 If the receiver's status is OALPlayerStatusFailed, this describes the error that caused the failure.
 
 @discussion
 The value of this property is an NSError that describes what caused the receiver to no longer be able to play items.
 If the receiver's status is not OALPlayerStatusFailed, the value of this property is nil.
 */

- (NSError *)error
{
	return [NSError errorWithDomain:@"OALAudioPlayer is abstract. Use a concrete subclass." code:1337 userInfo:nil];
}

#pragma mark Internal Use

/** (INTERNAL USE) Used by the parent OALAudioTrack to keep us in sync with the suspend/interrupt state above.
 */

- (bool) suspended
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return suspended;
	}
}

- (void) setSuspended:(bool) value
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(suspended != value)
		{
			suspended = value;
			if(suspended)
			{
				//currentTime = player.currentTime;
				[self stop];
			}
			else
			{
				
			}
		}
	}
}

@end
