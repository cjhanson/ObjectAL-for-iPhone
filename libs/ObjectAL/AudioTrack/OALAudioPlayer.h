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

#import <Foundation/Foundation.h>
#import "OALAudioTrackNotifications.h"

/*!
 @enum OALAudioPlayerType
 @abstract
 These constants are used to identify the specific implementation of the audio player.
 
 @constant OALAudioPlayerTypeInvalid
 Used by the abstract base class to indiciate it is itself invalid for use.
 @constant OALAudioPlayerTypeAVAudioPlayer
 Used to denote an underlying AVAudioPlayer
 @constant OALAudioPlayerTypeAVPlayer
 Used to denote an underlying AVPlayer
 @constant OALAudioPlayerTypeAudioQueueAVAssetReader
 Used to denote an underlying AudioQueue reading an AVAsset
 @constant OALAudioPlayerTypeAudioQueueAudioFile
 Used to denote an underlying AudioQueue reading an file
 @constant OALAudioPlayerTypeDefault
 Used to select the default implementation, but is not a valid value when subclassing OALAudioPlayer ;)
 */
enum {
	OALAudioPlayerTypeInvalid = -1,
	OALAudioPlayerTypeAVAudioPlayer,
	OALAudioPlayerTypeAVPlayer,
	OALAudioPlayerTypeAudioQueueAVAssetReader,
	OALAudioPlayerTypeAudioQueueAudioFile,
	
	//! Default
	OALAudioPlayerTypeDefault = OALAudioPlayerTypeAudioQueueAVAssetReader
};
typedef NSInteger OALAudioPlayerType;

/*!
 @enum OALPlayerStatus
 @abstract
 These constants are returned by the OALPlayer status property to indicate whether it can successfully play items.
 
 @constant	 OALPlayerStatusUnknown
 Indicates that the status of the player is not yet known because it has not tried to load new media resources for
 playback.
 @constant	 OALPlayerStatusReadyToPlay
 Indicates that the player is ready to play.
 @constant	 OALPlayerStatusFailed
 Indicates that the player can no longer play because of an error. The error is described by
 the value of the player's error property.
 */
enum {
	OALPlayerStatusUnknown,
	OALPlayerStatusReadyToPlay,
	OALPlayerStatusFailed
};
typedef NSInteger OALPlayerStatus;

@interface OALAudioPlayer : NSObject {
	OALAudioPlayerType playerType;
	id<OALAudioPlayerDelegate> delegate;
}

+ (Class) getClassForPlayerType:(OALAudioPlayerType)aPlayerType;

- (void) postPlayerReadyNotification;

/* transport control */
/* methods that return BOOL return YES on success and NO on failure. */
- (BOOL)prepareToPlay;	/* get ready to play the sound. happens automatically on play. */
- (BOOL)play;			/* sound is played asynchronously. */
- (BOOL)playAtTime:(NSTimeInterval) time;  /* play a sound some time in the future. time should be greater than deviceCurrentTime. */
- (void)pause;			/* pauses playback, but remains ready to play. */
- (void)stop;			/* stops playback. no longer ready to play. */

/* properties */

@property (readonly) OALAudioPlayerType playerType;

@property(readonly, getter=isPlaying) BOOL playing;

@property(readonly) NSUInteger numberOfChannels;
@property(readonly) NSTimeInterval duration; /* the duration of the sound. */

@property(assign) id<OALAudioPlayerDelegate> delegate; /* the delegate will be sent playerDidFinishPlaying */ 

/* one of these two properties will be non-nil based on the init... method used */
@property(readonly) NSURL *url; /* returns nil if object was not created with a URL */
@property(readonly) NSData *data; /* returns nil if object was not created with a data object */

@property float pan; /* set panning. -1.0 is left, 0.0 is center, 1.0 is right. */
@property float volume; /* The volume for the sound. The nominal range is from 0.0 to 1.0. */

/*  If the sound is playing, currentTime is the offset into the sound of the current playback position.  
 If the sound is not playing, currentTime is the offset into the sound where playing would start. */
@property NSTimeInterval currentTime;

/* returns the current time associated with the output device */
@property(readonly) NSTimeInterval deviceCurrentTime;

/* "numberOfLoops" is the number of times that the sound will return to the beginning upon reaching the end. 
 A value of zero means to play the sound just once.
 A value of one will result in playing the sound twice, and so on..
 Any negative number will loop indefinitely until stopped.
 */
@property NSInteger numberOfLoops;

/* settings */
@property(readonly) NSDictionary *settings; /* returns a settings dictionary with keys as described in AVAudioSettings.h */

/* metering */

@property(getter=isMeteringEnabled) BOOL meteringEnabled; /* turns level metering on or off. default is off. */

- (void)updateMeters; /* call to refresh meter values */

- (float)peakPowerForChannel:(NSUInteger)channelNumber; /* returns peak power in decibels for a given channel */
- (float)averagePowerForChannel:(NSUInteger)channelNumber; /* returns average power in decibels for a given channel */

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
@property (nonatomic, readonly) OALPlayerStatus status;

/*!
 @property error
 @abstract
 If the receiver's status is OALPlayerStatusFailed, this describes the error that caused the failure.
 
 @discussion
 The value of this property is an NSError that describes what caused the receiver to no longer be able to play items.
 If the receiver's status is not OALPlayerStatusFailed, the value of this property is nil.
 */
@property (nonatomic, readonly) NSError *error;

@end
