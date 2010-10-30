//
//  OALAudioPlayerAVAudioPlayer.m
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

#import "OALAudioPlayerAVAudioPlayer.h"
#import "OALAudioSupport.h"

@implementation OALAudioPlayerAVAudioPlayer
@synthesize player;

- (void) dealloc
{
	[player release];
	[super dealloc];
}

- (id)initWithContentsOfURL:(NSURL *)url error:(NSError **)outError
{
	self = [super init];
	if(self){
		player = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:outError];
		if(!player){
			[self release];
			return nil;
		}
		player.delegate = self;
		
		playerType = OALAudioPlayerTypeAVAudioPlayer;
		
		[self performSelector:@selector(postPlayerReadyNotification) withObject:nil afterDelay:0.01];
	}
	return self;
}

- (id)initWithData:(NSData *)data error:(NSError **)outError
{
	self = [super init];
	if(self){
		player = [[AVAudioPlayer alloc] initWithData:data error:outError];
		player.delegate = self;
		
		playerType = OALAudioPlayerTypeAVAudioPlayer;
		
		[self performSelector:@selector(postPlayerReadyNotification) withObject:nil afterDelay:0.01];
	}
	return self;
}

#pragma mark -
#pragma mark Custom implementation of abstract super class

/* get ready to play the sound. happens automatically on play. */
- (BOOL)prepareToPlay
{
	return [player prepareToPlay];
}

/* sound is played asynchronously. */
- (BOOL)play
{
	return [player play];
}

/* play a sound some time in the future. time should be greater than deviceCurrentTime. */
- (BOOL)playAtTime:(NSTimeInterval) time
{
	return [player playAtTime:time];
}

/* pauses playback, but remains ready to play. */
- (void)pause
{
	[player pause];
}

/* stops playback. no longer ready to play. */
- (void)stop
{
	[player stop];
}

/* properties */

- (BOOL) isPlaying
{
	return player.isPlaying;
}

- (NSUInteger) numberOfChannels
{
	return player.numberOfChannels;
}

- (NSTimeInterval) duration
{
	return player.duration;
}


- (NSURL *) url
{
	return player.url;
}

- (NSData *) data
{
	return player.data;
}

- (void) setPan:(float)p
{
	player.pan = p;
}

- (float) pan
{
	return player.pan;
}

- (void) setVolume:(float)v
{
	player.volume = v;
}

- (float) volume
{
	return player.volume;
}

- (void) setCurrentTime:(NSTimeInterval)t
{
	player.currentTime = t;
}

- (NSTimeInterval) currentTime
{
	return player.currentTime;
}

- (NSTimeInterval) deviceCurrentTime
{
	return player.deviceCurrentTime;
}

- (void) setNumberOfLoops:(NSInteger)n
{
	player.numberOfLoops = n;
}

- (NSInteger) numberOfLoops
{
	return player.numberOfLoops;
}

- (NSDictionary *) settings
{
	return player.settings;
}

/* metering */

- (void) setMeteringEnabled:(BOOL)yn
{
	player.meteringEnabled = yn;
}

- (BOOL) isMeteringEnabled
{
	return player.isMeteringEnabled;
}

/* call to refresh meter values */
- (void)updateMeters
{
	[player updateMeters];
}

/* returns peak power in decibels for a given channel */
- (float)peakPowerForChannel:(NSUInteger)channelNumber
{
	return [player peakPowerForChannel:channelNumber];
}

/* returns average power in decibels for a given channel */
- (float)averagePowerForChannel:(NSUInteger)channelNumber
{
	return [player averagePowerForChannel:channelNumber];
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
	return OALPlayerStatusReadyToPlay;
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
	return nil;
}

#pragma mark -
#pragma mark AVAudioPlayerDelegate

#if TARGET_OS_IPHONE
- (void) audioPlayerBeginInterruption:(AVAudioPlayer*) playerIn
{
	if([delegate respondsToSelector:@selector(audioPlayerBeginInterruption:)])
	{
		[delegate audioPlayerBeginInterruption:self];
	}
}

#if defined(__MAC_10_7) || defined(__IPHONE_4_0)
- (void)audioPlayerEndInterruption:(AVAudioPlayer *)playerIn withFlags:(NSUInteger)flags
{
	if([delegate respondsToSelector:@selector(audioPlayerEndInterruption:withFlags:)])
	{
		[delegate audioPlayerEndInterruption:self withFlags:flags];
	}
}
#endif

- (void) audioPlayerEndInterruption:(AVAudioPlayer*) playerIn
{
	if([delegate respondsToSelector:@selector(audioPlayerEndInterruption:)])
	{
		[delegate audioPlayerEndInterruption:self];
	}
}
#endif //TARGET_OS_IPHONE

- (void) audioPlayerDecodeErrorDidOccur:(AVAudioPlayer*) playerIn error:(NSError*) error
{
	if([delegate respondsToSelector:@selector(audioPlayerDecodeErrorDidOccur:error:)])
	{
		[delegate audioPlayerDecodeErrorDidOccur:self error:error];
	}
}

- (void) audioPlayerDidFinishPlaying:(AVAudioPlayer*) playerIn successfully:(BOOL) flag
{
	if([delegate respondsToSelector:@selector(audioPlayerDidFinishPlaying:successfully:)])
	{
		[delegate audioPlayerDidFinishPlaying:self successfully:flag];
	}
}

@end
