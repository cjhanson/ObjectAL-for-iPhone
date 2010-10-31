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
		playerType = OALAudioPlayerTypeAudioQueueAudioFile;
		state = OALPlayerStateClosed;
		status = OALPlayerStatusUnknown;
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

#pragma mark -
#pragma mark Custom implementation of abstract super class

#if 0

/* get ready to play the sound. happens automatically on play. */
- (BOOL)prepareToPlay
{
	return YES;
}

/* sound is played asynchronously. */
- (BOOL)play
{
	if(isPlaying)
		return YES;
	
	if(isPodSource){
		wasIPodAllowedBeforePlaybackStarted = [OALAudioSupport sharedInstance].allowIpod;
		[OALAudioSupport sharedInstance].allowIpod = YES;
	}
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
	
	if(isPodSource && !wasIPodAllowedBeforePlaybackStarted){
		[OALAudioSupport sharedInstance].allowIpod = wasIPodAllowedBeforePlaybackStarted;
	}
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
	CMTime cTime = CMTimeMakeWithSeconds(t, 1);
	[player seekToTime:cTime toleranceBefore:CMTimeMakeWithSeconds(0.2, 1) toleranceAfter:CMTimeMakeWithSeconds(0.2, 1)];
}

- (NSTimeInterval) currentTime
{
	CMTime cTime = [player currentTime];
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
	return status;
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

#endif

@end
