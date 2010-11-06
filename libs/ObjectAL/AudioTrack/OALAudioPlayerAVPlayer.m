//
//  OALAudioPlayerAVPlayer.m
//  ObjectAL
//
//  Created by CJ Hanson on 29-OCT-2010
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

#import "OALAudioPlayerAVPlayer.h"
#import "OALAudioSupport.h"
#import "ObjectALMacros.h"

static const int PlayerStatusContext = 1;

@implementation OALAudioPlayerAVPlayer
@synthesize player;

- (void) dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	[player removeObserver:self forKeyPath:@"status"];
	
	[asset release];
	[url release];
	[player release];
	[super dealloc];
}

- (id) initWithContentsOfURL:(NSURL *)inURL seekTime:(NSTimeInterval)inSeekTime error:(NSError **)outError
{
	self = [super init];
	if(self){
		//I don't know why but passing this option enabled will cause the time to progress but no sound to output.
		NSDictionary *options	= nil;//[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:AVURLAssetPreferPreciseDurationAndTimingKey];
		asset					= [[AVURLAsset alloc] initWithURL:inURL options:options];
		if(!asset){
			if(outError)
				*outError		= [NSError errorWithDomain:@"AVPlayer failed with AVURLAsset" code:-1 userInfo:nil];
			[self release];
			return nil;
		}
		
		AVPlayerItem *item		= [[[AVPlayerItem alloc] initWithAsset:asset] autorelease];
		player					= [[AVPlayer alloc] initWithPlayerItem:item];
		
		if(!player){
			if(outError)
				*outError		= [NSError errorWithDomain:@"AVPlayer failed with AVPlayerItem" code:-1 userInfo:nil];
			[self release];
			return nil;
		}
		
		if(outError)
			*outError			= nil;
		
		player.actionAtItemEnd	= AVPlayerActionAtItemEndNone;
		playerType = OALAudioPlayerTypeAVPlayer;
		state = OALPlayerStateNotReady;
		
		url = [inURL retain];
		volume = 1.0f;
		isPlaying = NO;
		loopCount = 0;
		
		self.currentTime		= inSeekTime;
//		CMTime cTime = CMTimeMakeWithSeconds(120, 1);
//		[player seekToTime:cTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
		
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onAVPlayerItemDidPlayToEndTimeNotification:) name:AVPlayerItemDidPlayToEndTimeNotification object:item];
		
		[player addObserver:self forKeyPath:@"status" options:0 context:(void *)&PlayerStatusContext];
	}
	return self;
}
		 
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	OAL_LOG_INFO(@"Got key observing callback. Context %s", (*(int *)context == PlayerStatusContext)?"Y":"N");
	int cID = *(int *)context;
	switch(cID){
		case 1:
		{
			//AVPlayer
			AVPlayer *thePlayer = (AVPlayer *)object;
			switch(thePlayer.status){
				case AVPlayerStatusReadyToPlay:
				{
					OAL_LOG_INFO(@"AVPlayer status is Ready to Play");
					
					state = OALPlayerStateStopped;
					
					[[NSNotificationCenter defaultCenter] postNotificationName:@"OALAudioPlayerReadyToPlay" object:self];
				}
					break;
				case AVPlayerStatusUnknown:
				{
					OAL_LOG_INFO(@"AVPlayer status is Unknown");
				}
					break;
				case AVPlayerStatusFailed:
				{
					NSError *playerError = [thePlayer error];
					OAL_LOG_ERROR(@"AVPlayer status is Error %@", playerError);
					return;
				}
					break;
			}
		}
			break;
		case 2:
		{
			//AVPlayerItem
		}
			break;
		default:
			break;
	}
	
    return;
}

- (void) onAVPlayerItemDidPlayToEndTimeNotification:(NSNotification *)notification
{
	OAL_LOG_INFO(@"Track completed.");
	if(numberOfLoops == -1 || numberOfLoops > loopCount){
		loopCount++;
		OAL_LOG_INFO(@"Looping %d / %d", loopCount, numberOfLoops);
		self.currentTime = 0;
		[player seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
		[player play];
		return;
	}
	dispatch_async(dispatch_get_main_queue(), ^{
		[self stop];
		if([delegate respondsToSelector:@selector(audioPlayerDidFinishPlaying:successfully:)])
		{
			[delegate audioPlayerDidFinishPlaying:self successfully:YES];
		}
	});
}

#pragma mark -
#pragma mark Custom implementation of abstract super class

/* get ready to play the sound. happens automatically on play. */
- (BOOL)prepareToPlay
{
	return YES;
}

- (BOOL) canPlay
{
	if(isPlaying)
		return NO;
	if(self.status != OALPlayerStatusReadyToPlay){
		OAL_LOG_INFO(@"Cannot play. status is %@", (self.status == OALPlayerStatusUnknown)?@"Unknown":(self.status == OALPlayerStatusFailed)?[NSString stringWithFormat:@"Failed: %@", self.error]:@"Ready to play?!?!");
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10000000), dispatch_get_main_queue(), ^{
			[self play];
		});
		return NO;
	}
	return YES;
}

/* sound is played asynchronously. */
- (BOOL)play
{
	if(isPlaying)
		return YES;
	
	if(![self canPlay])
		return YES;
	
	loopCount = 0;
	isPlaying = YES;
	[player play];
	return YES;
}

/* play a sound some time in the future. time should be greater than deviceCurrentTime. */
- (BOOL)playAtTime:(NSTimeInterval) time
{
	return NO;
}

/* pauses playback, but remains ready to play. */
- (void)pause
{
	if(!isPlaying)
		return;
	isPlaying = NO;
	[player pause];
}

/* stops playback. no longer ready to play. */
- (void)stop
{
	[self pause];
}

/* properties */

- (BOOL) isPlaying
{
	return isPlaying;
}

- (NSUInteger) numberOfChannels
{
	return 0;
}

- (NSTimeInterval) duration
{
	return CMTimeGetSeconds(asset.duration);
}

- (NSURL *) url
{
	return url;
}

- (NSData *) data
{
	return nil;
}

- (void) setPan:(float)p
{
	
}

- (float) pan
{
	return 0.5f;
}

- (void) setVolume:(float)v
{
	volume = v;
	
	
/*	
	AVPlayerItem *item	= (isItemAActive)?itemB:itemA;
	
	NSArray *audioTracks = [asset tracksWithMediaType:AVMediaTypeAudio];
	
	NSMutableArray *allAudioParams = [NSMutableArray array];
	for (AVAssetTrack *track in audioTracks) {
		AVMutableAudioMixInputParameters *audioInputParams =[AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:track];
		[audioInputParams setVolume:volume atTime:kCMTimeZero];
		[allAudioParams addObject:audioInputParams];
	}
	AVMutableAudioMix *audioMix = [AVMutableAudioMix audioMix];
	[audioMix setInputParameters:allAudioParams];
	
	[item setAudioMix:audioMix];
	[player setCurrentItem:item];
	
	isItemAActive = !isItemAActive;
*/	
	/*
	AVMutableAudioMixInputParameters *mix;
	
	if([player.currentItem.tracks count] > 0)
		mix = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:[player.currentItem.tracks objectAtIndex:0]];
	else
		mix = [AVMutableAudioMixInputParameters audioMixInputParameters];

	[mix setVolume:v atTime:CMTimeMake(0, 1)];
	
	if([player.currentItem.tracks count] < 1){
		AVMutableAudioMix *avMix = [AVMutableAudioMix audioMix];
		avMix.inputParameters	= [NSArray arrayWithObject:mix];
		
		player.currentItem.audioMix = avMix;
	}
	 */
}

- (float) volume
{
	return volume;
}

- (void) setCurrentTime:(NSTimeInterval)t
{
	return;
	
	NSArray *timeRanges = player.currentItem.seekableTimeRanges;
	OAL_LOG_INFO(@"Set current time %.2f", t);
	if([timeRanges count] == 0){
		OAL_LOG_INFO(@"Not yet seekable, try again in 0.01 seconds");
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10000000), dispatch_get_main_queue(), ^{
			[self setCurrentTime:t];
		});
		return;
	}
	
	for(NSValue *aTimeRangeValue in timeRanges){
		CMTimeRange aTimeRange = [aTimeRangeValue CMTimeRangeValue];
		OAL_LOG_INFO(@"Time range start %.2f (%lld), duration %.2f", CMTimeGetSeconds(aTimeRange.start), aTimeRange.start.epoch, CMTimeGetSeconds(aTimeRange.duration));
	}
	
	CMTime cTime = CMTimeMakeWithSeconds(t, 1);
	[player seekToTime:cTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
}

- (NSTimeInterval) currentTime
{
	CMTime cTime = player.currentTime;
	return CMTimeGetSeconds(cTime);
}

- (NSTimeInterval) deviceCurrentTime
{
	return 0;
}

- (void) setNumberOfLoops:(NSInteger)n
{
	numberOfLoops = n;
}

- (NSInteger) numberOfLoops
{
	return numberOfLoops;
}

- (NSDictionary *) settings
{
	return nil;
}

/* metering */

- (void) setMeteringEnabled:(BOOL)yn
{
	
}

- (BOOL) isMeteringEnabled
{
	return NO;
}

/* call to refresh meter values */
- (void)updateMeters
{
	
}

/* returns peak power in decibels for a given channel */
- (float)peakPowerForChannel:(NSUInteger)channelNumber
{
	return 0;
}

/* returns average power in decibels for a given channel */
- (float)averagePowerForChannel:(NSUInteger)channelNumber
{
	return 0;
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
	OALPlayerStatus s;
	switch (player.status)
	{
		case AVPlayerStatusUnknown:
			s = OALPlayerStatusUnknown;
			break;
		case AVPlayerStatusFailed:
			s = OALPlayerStatusFailed;
			break;
		case AVPlayerStatusReadyToPlay:
			s = OALPlayerStatusReadyToPlay;
			break;
		default:
			s = OALPlayerStatusUnknown;
	}
	return s;
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
	return state;
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
	return player.error;
}

@end
