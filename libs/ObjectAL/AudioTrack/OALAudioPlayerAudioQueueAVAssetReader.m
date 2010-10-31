//
//  OALAudioPlayerAudioQueueAVAssetReader.m
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

#import "OALAudioPlayerAudioQueueAVAssetReader.h"
#import "OALAudioSupport.h"
#import "ObjectALMacros.h"

#define CheckReaderStatus(__READER__) OAL_LOG_INFO(@"AVAssetReader Status: %@", [OALAudioSupport stringFromAVAssetReaderStatus:[(__READER__) status]]);

@interface OALAudioPlayerAudioQueueAVAssetReader (PrivateMethods)
- (BOOL)setupReaderAndOutput;
- (BOOL)setupAudioQueue;
- (void)prefetchBuffers;
static void BufferCallback(void *inUserData, AudioQueueRef inAQ, AudioQueueBufferRef buffer);
- (void)callbackForBuffer:(AudioQueueBufferRef)buffer;
- (int)readPacketsIntoBuffer:(AudioQueueBufferRef)buffer;
static void audioQueuePropertyListenerCallback(void *inUserData, AudioQueueRef queueObject, AudioQueuePropertyID propertyID);
- (void)playBackIsRunningStateChanged:(NSNumber *)isRunningN;
- (void)close;
@end

@implementation OALAudioPlayerAudioQueueAVAssetReader

- (void)dealloc
{
	[self close];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[super dealloc];
}

- (void)close
{
	if(state == OALPlayerStateClosed)
		return;
	
	if(isPodSource){
		[OALAudioSupport sharedInstance].allowIpod = wasIPodAllowedBeforePlaybackStarted;
	}
	isPodSource			= NO;
	
	[url release];
	url					= nil;
	
	[assetReader cancelReading];
	[assetReader release];
	assetReader			= nil;
	
	[assetReaderMixerOutput release];
	assetReaderMixerOutput = nil;
	
	[asset release];
	asset				= nil;
	
	loopCount			= 0;
	numberOfLoops		= 0;
	trackEnded			= NO;
	//	volume		= 1.0f;
	
	OSStatus audioError;
	
	//AudioQueueSetParameter(queue, kAudioQueueParam_Volume, 0.0f);
	
	if(queue){
		audioError			= AudioQueueStop(queue, YES); // <-- YES means stop immediately
		REPORT_AUDIO_QUEUE_CALL(audioError, @"AudioQueueStop(queue, YES);");
	
		//Note about not freeing the buffers:
		//Disposing of an audio queue also disposes of its buffers.
		//Call AudioQueueFreeBuffer only if you want to dispose of a particular buffer while continuing to use an audio queue.
		//You can dispose of a buffer only when the audio queue that owns it is stopped (that is, not processing audio data).
		
		//Note about not freeing timeline:
		//Disposing of an audio queue automatically disposes of any associated resources, including a timeline object.
		//Call AudioQueueDisposeTimeline only if you want to dispose of a timeline object and not the audio queue associated with it.
		
		audioError			= AudioQueueDispose(queue, YES);// <-- YES means do so synchronously
		REPORT_AUDIO_QUEUE_CALL(audioError, @"AudioQueueDispose(queue, YES);");
	}
	queue				= NULL;
	queueTimeline		= NULL;
	
	packetIndex			= 0;
	seekTimeOffset		= 0.0;
	
	//Set state
	state				= OALPlayerStateClosed;
	status				= OALPlayerStatusUnknown;
	
	OAL_LOG_INFO(@"audio queue player closed");
}

- (id)initWithContentsOfURL:(NSURL *)inUrl error:(NSError **)outError
{
	self = [super init];
	if(self){
		url						= [inUrl retain];
		playerType				= OALAudioPlayerTypeAudioQueueAVAssetReader;
		state					= OALPlayerStateClosed;
		status					= OALPlayerStatusUnknown;
		loopCount				= 0;
		numberOfLoops			= 0;
		trackEnded				= NO;
		volume					= 1.0f;
		asset					= nil;
		assetReader				= nil;
		assetReaderMixerOutput	= nil;
		queue					= NULL;
		queueTimeline			= NULL;
		packetIndex				= 0;
		seekTimeOffset			= 0.0;
		
		isPodSource				= [[url scheme] isEqualToString:@"ipod-library"];
		
		NSDictionary *options	= nil;//[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:AVURLAssetPreferPreciseDurationAndTimingKey];
		asset					= [[AVURLAsset alloc] initWithURL:inUrl options:options];
		if(!asset){
			if(outError)
				*outError		= [NSError errorWithDomain:@"AudioQueuePlayer failed with AVURLAsset" code:-1 userInfo:nil];
			[self release];
			return nil;
		}
		
		OAL_LOG_INFO(@"Asset duration: %.2f", CMTimeGetSeconds(asset.duration));
		
		state					= OALPlayerStateNotReady;
		
		[self performSelector:@selector(postPlayerReadyNotification) withObject:nil afterDelay:0.01];
		
		if(outError)
			*outError			= nil;
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
#pragma mark Prepare AVAsset

- (BOOL)prepareToPlay
{
	if(asset == nil){
		OAL_LOG_ERROR(@"Abort prepareToPlay. AVAsset is nil.");
		return NO;
	}
	
	if(state != OALPlayerStateClosed){
		OAL_LOG_INFO(@"Closing track before prepare to play.");
		AVURLAsset *anAsset	= [asset retain];
		[self close];
		asset				= anAsset;
	}
	
	if(isPodSource){
		wasIPodAllowedBeforePlaybackStarted = [OALAudioSupport sharedInstance].allowIpod;
		[OALAudioSupport sharedInstance].allowIpod = YES;
	}
	
	if(![self setupReaderAndOutput]){
		OAL_LOG_ERROR(@"Abort prepareToPlay. Setup Reader/Output failed.");
		[self close];
		return NO;
	}
	
	if(![self setupAudioQueue]){
		OAL_LOG_ERROR(@"Abort prepareToPlay. Failed to setup Audio Queue.");
		[self close];
		return NO;
	}
	
	status			= OALPlayerStatusReadyToPlay;
	state			= OALPlayerStateStopped;
	
	return YES;
}

#pragma mark -
#pragma mark AVAssetReader

- (BOOL) setupReaderAndOutput
{
	if(!asset){
		return NO;
	}
	
	if([asset.tracks count] < 1){
		OAL_LOG_ERROR(@"AVAsset has no tracks");
		return NO;
	}
	if([asset.tracks count] > 1){
		OAL_LOG_WARNING(@"AVAsset has more than one track");
	}
	
	// Create the AVAssetReader
	NSError *anError;
	assetReader	= [[AVAssetReader alloc] initWithAsset:asset error:&anError];
	
	if(!assetReader){
		OAL_LOG_ERROR(@"Could not create AVAssetReader: %@",[anError localizedDescription]);
		[assetReader release];
		assetReader = nil;
		return NO;
	}
	
	// Create the options dictionary to initialize the AVAssetReaderOuput
	// Note: It doesn't like it when certain options are set.
	// The Reader refuses to start reading if you try to specify nonInterleaved, Float, Endian, etc.
	// The following settings are working in all of my own tests.
	
	// Note that is is the output format, and it does not have to match the source format. It does have to match our queue format, so create that format object here for use later:
	dataFormat						= (AudioStreamBasicDescription){0};
	
	dataFormat.mSampleRate			= 44100.0;
	dataFormat.mFormatID			= kAudioFormatLinearPCM;
	dataFormat.mFormatFlags			= kAudioFormatFlagsCanonical;
	dataFormat.mChannelsPerFrame	= 2;
	dataFormat.mFramesPerPacket		= 1;
	dataFormat.mBitsPerChannel		= sizeof(SInt16) * 4 * dataFormat.mChannelsPerFrame; // 16-bit Signed Integer PCM
	dataFormat.mBytesPerFrame		= (dataFormat.mBitsPerChannel>>3) * dataFormat.mChannelsPerFrame;
	dataFormat.mBytesPerPacket		= dataFormat.mBytesPerFrame * dataFormat.mFramesPerPacket;
	
	OAL_LOG_INFO(@"ABSD:\n%@", [OALAudioSupport stringFromAudioStreamBasicDescription:&dataFormat]);
	
	NSDictionary *optionsDictionary	= [[NSDictionary alloc] initWithObjectsAndKeys:
									   [NSNumber numberWithFloat:(float)dataFormat.mSampleRate],	AVSampleRateKey,
									   [NSNumber numberWithInt:dataFormat.mFormatID],				AVFormatIDKey,
									   [NSNumber numberWithBool:(dataFormat.mFormatFlags == kAudioFormatFlagIsBigEndian)],		AVLinearPCMIsBigEndianKey,
									   [NSNumber numberWithBool:(dataFormat.mFormatFlags == kAudioFormatFlagIsFloat)],			AVLinearPCMIsFloatKey,
									   [NSNumber numberWithBool:(dataFormat.mFormatFlags == kAudioFormatFlagIsNonInterleaved)],	AVLinearPCMIsNonInterleaved,
									   [NSNumber numberWithInt:dataFormat.mChannelsPerFrame],		AVNumberOfChannelsKey,
									   [NSNumber numberWithInt:dataFormat.mBitsPerChannel],			AVLinearPCMBitDepthKey,
									   nil];
	
	OAL_LOG_INFO(@"AVAssetReaderAudioMixOutput Options:\n%@", [OALAudioSupport stringFromAVAssetReaderAudioMixOutputOptionsDictionary:optionsDictionary]);
	
	// Create our AVAssetReaderOutput subclass with our options
	assetReaderMixerOutput			= [[AVAssetReaderAudioMixOutput alloc] initWithAudioTracks:[asset tracks] audioSettings:optionsDictionary];
	
	[optionsDictionary release];
	
	if(!assetReaderMixerOutput){
		OAL_LOG_ERROR(@"Could not create the AVAssetReaderAudioMixOutput.");
		
		dataFormat	= (AudioStreamBasicDescription){0};
		
		[assetReader release];
		assetReader = nil;
		
		[assetReaderMixerOutput release];
		assetReaderMixerOutput = nil;
		
		return NO;
	}
	
	if([assetReader canAddOutput:assetReaderMixerOutput]){
		[assetReader addOutput:assetReaderMixerOutput];
	}else{
		OAL_LOG_ERROR(@"AVAssetReader could not add output");
		
		dataFormat	= (AudioStreamBasicDescription){0};
		
		[assetReader release];
		assetReader = nil;
		
		[assetReaderMixerOutput release];
		assetReaderMixerOutput = nil;
		
		return NO;
	}
	
	// Should be unknown before startReading is called
	CheckReaderStatus(assetReader);
	
	if(![assetReader startReading]){
		OAL_LOG_ERROR(@"AVAssetReader cannot start reading. %@",[assetReader.error localizedDescription]);
		
		CheckReaderStatus(assetReader);
		
		dataFormat	= (AudioStreamBasicDescription){0};
		
		[assetReader release];
		assetReader = nil;
		
		[assetReaderMixerOutput release];
		assetReaderMixerOutput = nil;
		
		return NO;
	}
	
	CheckReaderStatus(assetReader);
	
	return YES;
}

#pragma mark -
#pragma mark Audio Queue

- (BOOL) setupAudioQueue
{
	OSStatus	audioError;
		
	// create a new playback queue using the specified data format and buffer callback
	//param #4 and 5 set to NULL means AudioQueue will use it's own threads runloop with the CommonModes
	audioError	= AudioQueueNewOutput(&dataFormat, BufferCallback, self, NULL, NULL, 0, &queue);
	REPORT_AUDIO_QUEUE_CALL(audioError, @"AudioQueueNewOutput");
	
	audioError	= AudioQueueCreateTimeline(queue, &queueTimeline);
	REPORT_AUDIO_QUEUE_CALL(audioError, @"AudioQueueCreateTimeline");
	
	UInt32 hardwarePolicy = (UInt32)kAudioQueueHardwareCodecPolicy_PreferHardware;
	audioError = AudioQueueSetProperty(queue, kAudioQueueProperty_HardwareCodecPolicy, (const void *)&hardwarePolicy, sizeof(UInt32));
	REPORT_AUDIO_QUEUE_CALL(audioError, @"AudioQueueSetProperty: HardwareCodecPolicy");
	
	// for CBR data (Constant BitRate), we can simply fill each buffer with as many packets as will fit
	numPacketsToRead = OBJECTAL_CFG_AUDIO_QUEUE_BUFFER_SIZE_BYTES / dataFormat.mBytesPerPacket;
	
	OAL_LOG_INFO(@"AudioQueue set to read %d packets", numPacketsToRead);
	
	// we want to know when the playing state changes so we can properly dispose of the audio queue when it's done
	audioError	= AudioQueueAddPropertyListener(queue, kAudioQueueProperty_IsRunning, audioQueuePropertyListenerCallback, self);
	REPORT_AUDIO_QUEUE_CALL(audioError, @"AudioQueueAddPropertyListener: IsRunning");
	
	// allocate the play buffers
	for(int i = 0; i < OBJECTAL_CFG_AUDIO_QUEUE_NUM_BUFFERS; i++){
		audioError	= AudioQueueAllocateBuffer(queue, OBJECTAL_CFG_AUDIO_QUEUE_BUFFER_SIZE_BYTES, &buffers[i]);
		REPORT_AUDIO_QUEUE_CALL(audioError, @"AudioQueueAllocateBuffer: %d", i);
	}
	
	return YES;
}

- (void) prefetchBuffers
{
	OAL_LOG_INFO(@"AudioQueue prefetching buffers");
	if(assetReader.status != AVAssetReaderStatusReading){
		if(![assetReader startReading]){
			OAL_LOG_ERROR(@"AVAssetReader failed to start reading: %@", [assetReader.error localizedDescription]);
			return;
		}
	}
	
	for(int i = 0; i < OBJECTAL_CFG_AUDIO_QUEUE_NUM_BUFFERS; i++){
		if([self readPacketsIntoBuffer:buffers[i]] < 1){
			//			if(isLooping){
			// End Of File reached, so rewind and refill the buffer using the beginning of the file instead
			//				packetIndex = 0;
			//[self readPacketsIntoBuffer:buffers[i]];
			//			}else{
			// this might happen if the file was so short that it needed less buffers than we planned on using
			break;
			//			}
		}
	}
}

static void BufferCallback(void *inUserData, AudioQueueRef inAQ, AudioQueueBufferRef buffer)
{
	// redirect back to the class to handle it there instead, so we have direct access to the instance variables
	[(OALAudioPlayerAudioQueueAVAssetReader *)inUserData callbackForBuffer:buffer];
}

- (void)callbackForBuffer:(AudioQueueBufferRef)buffer
{
	// I guess it's possible for the callback to continue to be called since this is in another thread, so to be safe,
	// don't do anything else if the track is closed, and also don't bother reading anymore packets if the track ended
	if(state != OALPlayerStatePlaying || trackEnded){
		OAL_LOG_WARNING(@"callbackForBuffer while not playing or trackEnded");
		return;
	}
	
	int readCount = [self readPacketsIntoBuffer:buffer];
	if(readCount < 0){
		OAL_LOG_ERROR(@"callbackForBuffer failed to read packets into buffer");
		return;
	}
	if(readCount == 0){
		if(loopCount < numberOfLoops){
			OAL_LOG_INFO(@"Reached end of buffer, but isLooping, so reset packetIndex and read more packets into buffer");
			[self performSelectorOnMainThread:@selector(postTrackLoopedNotification:) withObject:nil waitUntilDone:NO];
			
			// End Of File reached, so rewind and refill the buffer using the beginning of the file instead
			self.currentTime = 0;
			[self readPacketsIntoBuffer:buffer];
			
			loopCount++;
		}else{
			OAL_LOG_INFO(@"Reached end of buffer, not looping, so set trackEnded = YES and stop audio queue asynch so it finishes playing the remaining buffers");
			// set it to stop, but let it play to the end, where the property listener will pick up that it actually finished
			trackEnded			= YES;
			OSStatus audioError	= AudioQueueStop(queue, NO);
			REPORT_AUDIO_QUEUE_CALL(audioError, @"callbackForBuffer AudioQueueStop(queue, NO)");
		}
	}
}

- (int)readPacketsIntoBuffer:(AudioQueueBufferRef)buffer
{
	if(state == OALPlayerStateClosed){
		OAL_LOG_ERROR(@"Not reading packets because player is closed.");
		return -1;
	}
	
	if([assetReader status] == AVAssetReaderStatusCompleted){
		return 0;
	}
	if([assetReader status] != AVAssetReaderStatusReading){
		OAL_LOG_ERROR(@"Attempted to read packets into buffer while asset reader is not reading.");
		return -1;
	}
	
	NSAutoreleasePool *pool = [NSAutoreleasePool new];	
	
	int audioBPS			= (float)(dataFormat.mSampleRate * dataFormat.mBitsPerChannel * dataFormat.mChannelsPerFrame)/8;
	NSTimeInterval playTime	= NSTimeInterval(numPacketsToRead * dataFormat.mBytesPerPacket)/audioBPS;
	
	UInt32		numBytes, numPackets;
	OSStatus	audioError = noErr;
	// read packets into buffer from file
	numPackets	= numPacketsToRead;
	
#pragma mark AVAsset to audio Queue	
	CMSampleBufferRef myBuff;
	CMBlockBufferRef blockBufferOut;
	AudioBufferList buffList;
	CFAllocatorRef structAllocator = NULL;
	CFAllocatorRef memoryAllocator = NULL;
	
	UInt32 myFlags = 0;
	
	myBuff = [assetReaderMixerOutput copyNextSampleBuffer];
	if(!myBuff){
		[pool drain];
		return 0;
	}
	
	size_t sizeNeeded;
	audioError = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
					 myBuff,
					 &sizeNeeded,
					 &buffList,
					 sizeof(buffList),
					 structAllocator,
					 memoryAllocator,
					 myFlags,
					 &blockBufferOut
				 );
	CFRelease(myBuff);
	
	if(audioError != noErr){
		OAL_LOG_ERROR(@"CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer %d", audioError);
	}
	
	size_t dataLength	= MIN(buffer->mAudioDataBytesCapacity, CMBlockBufferGetDataLength(blockBufferOut));
	numBytes			= dataLength;
	audioError			= CMBlockBufferCopyDataBytes(
							blockBufferOut,
							0,
							dataLength,
							buffer->mAudioData
						   );
	CFRelease(blockBufferOut);
	
	if(audioError != noErr){
		OAL_LOG_ERROR(@"CMBlockBufferCopyDataBytes %d", audioError);
	}
	
	buffer->mAudioDataByteSize = numBytes;
	audioError	= AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
	
	if(audioError != noErr){
		OAL_LOG_ERROR(@"readPacketsIntoBuffer, AudioQueueEnqueueBuffer %d", audioError);
	}
	
	[pool drain];
	
	packetIndex += numPackets;
	
	return numPackets;
}

static void audioQueuePropertyListenerCallback(void *inUserData, AudioQueueRef queueObject, AudioQueuePropertyID propertyID)
{
	if (propertyID == kAudioQueueProperty_IsRunning){
		UInt32 isRunningVal;
		UInt32 size	= sizeof(isRunningVal);
		OSStatus readPropOK	= AudioQueueGetProperty(queueObject, kAudioQueueProperty_IsRunning, &isRunningVal, &size);
		REPORT_AUDIO_QUEUE_CALL(readPropOK, @"AudioQueueGetProperty IsRunning");
		if(readPropOK == noErr){
			// redirect back to the class to handle it there instead, so we have direct access to the instance variables
			[(OALAudioPlayerAudioQueueAVAssetReader *)inUserData performSelectorOnMainThread:@selector(playBackIsRunningStateChanged:) withObject:[NSNumber numberWithBool:(isRunningVal==1)?YES:NO] waitUntilDone:NO];
		}
	}
}

- (void)playBackIsRunningStateChanged:(NSNumber *)isRunningN
{
	BOOL isRunning	= [isRunningN boolValue];
	OAL_LOG_INFO(@"playBackIsRunningStateChanged: %s and trackEnded: %s", isRunning?"Playing":"Stopped", trackEnded?"Y":"N");
	if(isRunning == NO){
		//stopped
		if(trackEnded){
			state = OALPlayerStateStopped;

//TODO: notifications
//			[self postTrackStoppedPlayingNotification:nil];
//			[self postTrackFinishedPlayingNotification:nil];
			
			// go ahead and close the track now
			[self close];
		}
	}else{
		//started
		//systemTimeAtPlayStart	= SecondsSinceStart();
//TODO: notifications
//		[self postTrackStartedPlayingNotification:nil];
	}
}

#pragma mark -
#pragma mark Custom implementation of abstract super class

/* sound is played asynchronously. */
- (BOOL)play
{
	if(state == OALPlayerStateClosed){
		OAL_LOG_WARNING(@"Attempted to play a closed AudioQueuePlayer.");
		return NO;
	}
	
	if(state == OALPlayerStateNotReady){
		if(![self prepareToPlay]){
			OAL_LOG_ERROR(@"play -> prepareToPlay");
			return NO;
		}
	}
	
	if(state == OALPlayerStatePlaying){
		return YES;
	}
	
	if(state == OALPlayerStateStopped || state == OALPlayerStateSeeking)
		[self prefetchBuffers];
	
	OSStatus audioError;
	
	if(state != OALPlayerStatePaused){
		audioError = AudioQueuePrime(queue, 1, nil);	
		if(audioError != noErr){
			REPORT_AUDIO_QUEUE_CALL(audioError, @"play -> AudioQueuePrime");
			return NO;
		}
	}
	
	audioError = AudioQueueStart(queue, NULL);
	if(audioError != noErr){
		REPORT_AUDIO_QUEUE_CALL(audioError, @"play -> AudioQueueStart");
		return NO;
	}
	
	audioError = AudioQueueSetParameter(queue, kAudioQueueParam_Volume, volume);
	if(audioError != noErr){
		REPORT_AUDIO_QUEUE_CALL(audioError, @"play -> AudioQueueSetParameter Volume %f", volume);
	}
	
	if(state == OALPlayerStatePaused){
// TODO: look into this
//		[self performSelectorOnMainThread:@selector(postTrackStartedPlayingNotification:) withObject:nil waitUntilDone:NO];
	}
	
	loopCount = 0;
	state	= OALPlayerStatePlaying;
	
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
	if(state != OALPlayerStatePlaying)
		return;
	
	state			= OALPlayerStatePaused;
	
	OSStatus audioError	= AudioQueuePause(queue);
	REPORT_AUDIO_QUEUE_CALL(audioError, @"AudioQueuePause");
	
// TODO: Look into this	
//	[self performSelectorOnMainThread:@selector(postTrackStoppedPlayingNotification:) withObject:nil waitUntilDone:NO];
}

/* stops playback. no longer ready to play. */
- (void)stop
{
	[self pause];
}

/* properties */

- (BOOL) isPlaying
{
	return (state == OALPlayerStatePlaying);
}

- (NSUInteger) numberOfChannels
{
	return dataFormat.mChannelsPerFrame;
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
	
	if(state == OALPlayerStateClosed)
		return;
	
	OSStatus audioError	= AudioQueueSetParameter(queue, kAudioQueueParam_Volume, volume);
	REPORT_AUDIO_QUEUE_CALL(audioError, @"AudioQueueSetParameter Volume %f", volume);
}

- (float) volume
{
	return volume;
}

//TODO: Figure out seek and current time
- (void) setCurrentTime:(NSTimeInterval)t
{
	if(state == OALPlayerStateClosed)
		return;
	
	if(state != OALPlayerStateNotReady){
		OAL_LOG_ERROR(@"Cannot set current time when the player is ready. The time must be set before playback.");
		return;
	}	
	
	CMTime startTime		= CMTimeMakeWithSeconds(t, 1);
	CMTime playDuration		= kCMTimePositiveInfinity;
	assetReader.timeRange	= CMTimeRangeMake(startTime, playDuration);
	packetIndex				= (uint)(t * dataFormat.mSampleRate);
}

- (NSTimeInterval) currentTime
{
	if(state == OALPlayerStateClosed)
		return 0;
	
	//CMTime readerTime		= CMTimeGetSeconds(assetReader.timeRange.start);
	
	AudioTimeStamp currentTime;
	Boolean outTimelineDiscontinuity;
	OSStatus audioError = AudioQueueGetCurrentTime (
													queue,
													queueTimeline,
													&currentTime,
													&outTimelineDiscontinuity
													);
	if(audioError != noErr){
		currentTime.mSampleTime	= -1.0;
		REPORT_AUDIO_QUEUE_CALL(audioError, @"getCurrentTime AudioQueueGetCurrentTime");
		return 0;
	}
	return dataFormat.mSampleRate / currentTime.mSampleTime;
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
	return nil;
}

#pragma mark -
#pragma mark Audio Session

- (void) setSuspended:(bool) value
{
	if(suspended != value){
		suspended = value;
		if(suspended){
			if(state != OALPlayerStateClosed){
				OAL_LOG_INFO(@"Session Interrupted an open AudioQueue Player, saving position, shutting down audio queue.");

				//TODO: notification
//				[[NSNotificationCenter defaultCenter] postNotificationName:CJMusicPlayerStoppedPlayingNotification object:self];
				positionBeforeInterruption	= (NSTimeInterval)self.currentTime;
				
				//Manually close track
				OSStatus audioError;
				audioError					= AudioQueueSetParameter(queue, kAudioQueueParam_Volume, 0.0f);
				REPORT_AUDIO_QUEUE_CALL(audioError, @"audioSessionInterrupted, AudioQueueSetParameter, Volume 0");
				
				audioError					= AudioQueueStop(queue, YES); // <-- YES means stop immediately
				REPORT_AUDIO_QUEUE_CALL(audioError, @"audioSessionInterrupted, AudioQueueStop");
				
				audioError					= AudioQueueDispose(queue, YES);// <-- YES means do so synchronously
				REPORT_AUDIO_QUEUE_CALL(audioError, @"audioSessionInterrupted, AudioQueueDispose");
				
				queue				= NULL;
				queueTimeline		= NULL;
				
				state				= OALPlayerStateClosed;
			}
		}else{
			OAL_LOG_INFO(@"Session Restored open AudioQueue Player, restoring position.");
			
			if([self prepareToPlay]){			
				self.currentTime = positionBeforeInterruption;
			}else{
				OAL_LOG_ERROR(@"AudioQueue player failed to prepare to play in audio session restore.");
			}
		}
	}
}

@end

#if 0

#import "CJAudioErrors.h"
#import "CJAudioSessionNotifications.h"
#import "CJMusicPlayerNotifications.h"
#import "TimeHelper.h"
#import "CJDSP.h"

#ifndef CJLOG
#define CJLOG NSLog
#endif

//0x4000=16k, 0x8000=32k, 0x10000=64k
static UInt32	gBufferSizeBytes = 0x8000;

@interface CJAVAssetPlayer (InternalMethods)

- (AudioTimeStamp)getCurrentTime;
- (void) finishedProcessing;

static void audioQueuePropertyListenerCallback(void *inUserData, AudioQueueRef queueObject, AudioQueuePropertyID	propertyID);
- (void)playBackIsRunningStateChanged:(NSNumber *)isRunningN;

static void BufferCallback(void *inUserData, AudioQueueRef inAQ, AudioQueueBufferRef buffer);
- (void)callbackForBuffer:(AudioQueueBufferRef)buffer;
- (int)readPacketsIntoBuffer:(AudioQueueBufferRef)buffer;
- (int) processAudioBuffer:(AudioQueueBufferRef)buffer;
- (void)prefetchBuffers;
- (void)preProcessAudio;
- (void) postAudioStateChangedNotification;
- (void) postTrackSourceChangedNotification:(id)object;
- (void)postTrackStartedPlayingNotification:(id)object;
- (void)postTrackStoppedPlayingNotification:(id)object;
- (void)postTrackLoopedNotification:(id)object;
- (void)postTrackFinishedPlayingNotification:(id)object;
@end

@implementation CJAVAssetPlayer

@synthesize audioState, queue, numPacketsToRead, isLooping, duration, volume=currentVolume;
@synthesize audioReader;
@synthesize audioReaderMixerOutput;
@synthesize audioAsset;


//Block for checking the status of an AVAssetReader so that useful information is printed to the console

void (^CheckReaderStatus)(AVAssetReader*) = ^(AVAssetReader *theReader)
{	
	if (theReader) {
		switch ([theReader status]) {
			case AVAssetReaderStatusUnknown:
				NSLog(@"Reader status is Unknown");
				break;
			case AVAssetReaderStatusReading:
				NSLog(@"Reader status is Reading");
				
				break;
			case AVAssetReaderStatusCompleted:
				NSLog(@"Reader status is Completed");
				
				break;
			case AVAssetReaderStatusFailed:
				NSLog(@"Reader status is Failed");
				
				break;
			case AVAssetReaderStatusCancelled:
				NSLog(@"Reader status is Cancelled");
				
				break;
				
			default:
				break;
		}
	}
};

#pragma mark -
#pragma mark CJAVAssetPlayer

- (void)dealloc
{
	[self close];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[super dealloc];
}

- (void)close
{
	if(audioState == E_CJMP_State_Closed)
		return;
	
	[audioReader cancelReading];
	[audioReader release];
	audioReader = nil;
	
	[audioReaderMixerOutput release];
	audioReaderMixerOutput = nil;
	
	[audioAsset release];
	audioAsset			= nil;
	
	isLooping			= NO;
	trackEnded			= NO;
	//	currentVolume		= 1.0f;
	duration			= 0.0f;
	
	playbackStartTime	= 0.0;
	pauseStartTime		= 0.0;
	pauseDuration		= 0.0;
	
	OSStatus audioError;
	
	//AudioQueueSetParameter(queue, kAudioQueueParam_Volume, 0.0f);
	audioError			= AudioQueueStop(queue, YES); // <-- YES means stop immediately
	if(audioError != noErr){
		CJLOG(@"Error: %@ | close, AudioQueueStop", GetNSStringFromAudioQueueError(audioError));
	}
	audioError			= AudioQueueDispose(queue, YES);// <-- YES means do so synchronously
	if(audioError != noErr){
		CJLOG(@"Error: %@ | close, AudioQueueDispose", GetNSStringFromAudioQueueError(audioError));
	}
	queue				= NULL;
	queueTimeline		= NULL;
	
	if(packetDescs)
		free(packetDescs);
	packetDescs			= NULL;
	
	packetIndex			= 0;
	
	if(dsp)
		delete dsp;
	dsp					= NULL;
	
	if(audioConverter)
		AudioConverterDispose(audioConverter);
	audioConverter		= NULL;
	
	if(convertedDataRaw)
		free(convertedDataRaw);
	convertedDataRaw	= NULL;
	convertedData		= NULL;
	
	//Set state
	audioState	= E_CJMP_State_Closed;
	
	CJLOG(@"CJAVAssetPlayer closed.");
}

- (id) init
{
	self = [super init];
	if(self != nil){
		isLooping				= NO;
		trackEnded				= NO;
		currentVolume			= 1.0f;
		audioAsset				= nil;
		audioReader				= nil;
		audioReaderMixerOutput	= nil;
		duration				= 0.0f;
		lastCurrentTime			= 0.0;
		packetIndex				= 0;
		timeOfLastCurrentTimeCheck		= 0.0f;
		timeOfLastEstimatedTimeCheck	= 0.0f;
		playbackStartTime	= 0.0;
		pauseStartTime		= 0.0;
		pauseDuration		= 0.0;
		
		sessionWasInterrupted		= NO;
		willDispatchNotifications	= YES;
		
		audioState				= E_CJMP_State_Closed;
		
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioSessionInterrupted:) name:AudioSessionInterruptedNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioSessionRestored:) name:AudioSessionRestoredNotification object:nil];
	}
	return self;
}

- (BOOL) setupReaderAndOutput
{
	if(!audioAsset){
		return NO;
	}
#pragma mark AVAssetReader
	
	AVAsset *anAsset	= audioAsset;
	
	///////////////////////
	///// AssetReader Setup
	///////////////////////
	
	// Create the AVAssetReader
	NSError *error;
	AVAssetReader *assetReader = [[AVAssetReader alloc] initWithAsset:anAsset error:&error];
	
	if(error){
		NSLog(@"Error creating assetReader: %@",[error localizedDescription]);
		
		[assetReader release];
		
		return NO;
	}
	
	// Create the options dictionary to initialize our AVAssetReaderOuput subclass with
	// Note: It doesn't like it when certain options are set. The Reader refuses to start reading if you try to specify nonInterleaved, Float, Endian, etc.
	//           The following settings are working pretty well.
	NSDictionary *optionsDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
									   [NSNumber numberWithFloat:44100.0f], AVSampleRateKey,
									   [NSNumber numberWithInt:2], AVNumberOfChannelsKey,
									   [NSNumber numberWithInt:16], AVLinearPCMBitDepthKey,
									   [NSNumber numberWithInt:kAudioFormatLinearPCM], AVFormatIDKey,
									   [NSNumber numberWithBool:NO], AVLinearPCMIsBigEndianKey,
									   [NSNumber numberWithBool:NO], AVLinearPCMIsFloatKey,
									   [NSNumber numberWithBool:NO], AVLinearPCMIsNonInterleaved,
									   nil];
	
	// Create our AVAssetReaderOutput subclass with our options
	AVAssetReaderAudioMixOutput *mixOutput = [[AVAssetReaderAudioMixOutput alloc] initWithAudioTracks:[anAsset tracks] audioSettings:optionsDictionary];
	
	if(!mixOutput){
		NSLog(@"Could not initialize the AVAssetReaderTrackOutput.");
		
		[assetReader release];
		[mixOutput release];
		
		return NO;
	}else{
		if([assetReader canAddOutput:mixOutput]){
			[assetReader addOutput:mixOutput];
		}else{
			NSLog(@"Error: Cannot add output!!!");
			
			[assetReader release];
			[mixOutput release];
			
			return NO;
		}
		
		// Should be unknown before startReading is called
		CheckReaderStatus(assetReader);
		
		// Attempt to startReading from our Asset Reader
		if(![assetReader startReading]){
			NSLog(@"Error: Asset reader cannot start reading. Error: %@",[assetReader.error localizedDescription]);
			
			CheckReaderStatus(assetReader);
			
			[assetReader release];
			[mixOutput release];
			
			return NO;
		}else{
			self.audioReader			= [assetReader autorelease];
			
			self.audioReaderMixerOutput = [mixOutput autorelease];
		}
	}
	
	return YES;
}

- (BOOL)prepareToPlayAsset:(AVAsset *)anAsset
{
	if(anAsset == nil){
		return NO;
	}
	if(!sessionWasInterrupted){
		if(anAsset == audioAsset){
			CJLOG(@"Aborting prepareToPlayAsset. Asset already loaded.");
			return YES;
		}
	}
	if(audioState != E_CJMP_State_Closed){
		[self close];
	}
	
	self.audioAsset = anAsset;
	
	if(![self setupReaderAndOutput]){
		CJLOG(@"Aborting prepareToPlayAsset. Setup Reader/Output failed.");
		self.audioAsset = nil;
		return NO;
	}
	
#pragma mark Audio Queue
	
	OSStatus	audioError;
	int			i;
	
	if([audioAsset.tracks count] != 1){
		CJLOG(@"Warning: Asset has more than one track");
	}
	AVAssetTrack *firstTrack			= [audioReaderMixerOutput.audioTracks objectAtIndex:0];
	if(!firstTrack){
		CJLOG(@"Error: No track for asset");
	}
	
	dataFormat = (AudioStreamBasicDescription){0};
	
	dataFormat.mSampleRate				= 44100.0;
	dataFormat.mFormatID				= kAudioFormatLinearPCM;
	dataFormat.mFormatFlags				= kAudioFormatFlagsCanonical;
	dataFormat.mChannelsPerFrame		= 2;
	dataFormat.mFramesPerPacket			= 1;
	dataFormat.mBitsPerChannel			= sizeof(SInt16) * 4 * dataFormat.mChannelsPerFrame; // 16-bit Signed Integer PCM
	dataFormat.mBytesPerFrame			= (dataFormat.mBitsPerChannel>>3) * dataFormat.mChannelsPerFrame;
	dataFormat.mBytesPerPacket			= dataFormat.mBytesPerFrame * dataFormat.mFramesPerPacket;
	
	CJLOG(@"Info: Audio Format: %@\n"
		  "Sample Rate: %f\n"
		  "Bytes Per Packet: %d, isVBR? %s\n"
		  "Frames Per Packet: %d\n"
		  "Data type: %s\n",
		  GetNSStringFrom4CharCode(dataFormat.mFormatID),
		  dataFormat.mSampleRate,
		  dataFormat.mBytesPerPacket,
		  (dataFormat.mBytesPerPacket == 0)?"Y":"N",
		  dataFormat.mFramesPerPacket,
		  (dataFormat.mFormatFlags & kAudioFormatFlagIsFloat)?"Float":"SInt"
		  );
	
	//get duration
	CMTime assetDuration	= audioAsset.duration;
	if(CMTIME_IS_VALID(assetDuration)){
		duration			= assetDuration.value / assetDuration.timescale;
	}else{
		CJLOG(@"ERROR: duration is invalid");
	}
	CJLOG(@"Audio file duration: %.2f", duration);
	
	// create a new playback queue using the specified data format and buffer callback
	//param #4 and 5 set to NULL means AudioQueue will use it's own threads runloop with the CommonModes
	audioError	= AudioQueueNewOutput(&dataFormat, BufferCallback, self, NULL, NULL, 0, &queue);
	if(audioError != noErr){
		CJLOG(@"Error: %@ | loadFile, AudioQueueNewOutput", GetNSStringFromAudioQueueError(audioError));
	}
	
	audioError	= AudioQueueCreateTimeline(queue, &queueTimeline);
	if(audioError != noErr){
		CJLOG(@"Error: %@ | loadFile, AudioQueueCreateTimeline", GetNSStringFromAudioQueueError(audioError));
	}
	
	UInt32 hardwarePolicy = (UInt32)kAudioQueueHardwareCodecPolicy_PreferHardware;
	audioError = AudioQueueSetProperty(queue, kAudioQueueProperty_HardwareCodecPolicy, (const void *)&hardwarePolicy, sizeof(UInt32));
	if(audioError != noErr){
		CJLOG(@"Error: %@ | loadFile, AudioQueueSetProperty->HardwareCodecPolicy", GetNSStringFromAudioQueueError(audioError));
	}
	
	// for CBR data (Constant BitRate), we can simply fill each buffer with as many packets as will fit
	numPacketsToRead = gBufferSizeBytes / dataFormat.mBytesPerPacket;
	
	// don't need packet descriptions for CBR data
	packetDescs = NULL;
	
	CJLOG(@"Packets to read: %d", numPacketsToRead);
	
	// we want to know when the playing state changes so we can properly dispose of the audio queue when it's done
	audioError	= AudioQueueAddPropertyListener(queue, kAudioQueueProperty_IsRunning, audioQueuePropertyListenerCallback, self);
	if(audioError != noErr){
		CJLOG(@"Error: %@ | loadFile, AudioQueueAddPropertyListener, kAudioQueueProperty_IsRunning", GetNSStringFromAudioQueueError(audioError));
	}
	
	// allocate and prime buffers with some data
	packetIndex = 0;
	seekTimeOffset	= 0.0;
	for (i = 0; i < CJMP_NUM_QUEUE_BUFFERS; i++){
		//audioError	= AudioQueueAllocateBufferWithPacketDescriptions(queue, gBufferSizeBytes, numPacketsToRead, &buffers[i]);
		audioError	= AudioQueueAllocateBuffer(queue, gBufferSizeBytes, &buffers[i]);
		if(audioError != noErr){
			CJLOG(@"Error: %@ | loadFile, AudioQueueAllocateBuffer, %d", GetNSStringFromAudioQueueError(audioError), i);
		}
	}
	
#pragma mark FFT / Beat Detection
	
	convertedFormat = (AudioStreamBasicDescription){0};
	convertedFormat.mSampleRate				= dataFormat.mSampleRate;
	convertedFormat.mFormatID				= dataFormat.mFormatID;
	convertedFormat.mFormatFlags			= kAudioFormatFlagsNativeFloatPacked;
	convertedFormat.mChannelsPerFrame		= 1;//dataFormat.mChannelsPerFrame;
	convertedFormat.mBitsPerChannel			= sizeof(Float32) * 8 * convertedFormat.mChannelsPerFrame;
	convertedFormat.mFramesPerPacket		= 1;
	convertedFormat.mBytesPerFrame			= (convertedFormat.mBitsPerChannel>>3) * convertedFormat.mChannelsPerFrame;
	convertedFormat.mBytesPerPacket			= convertedFormat.mBytesPerFrame * convertedFormat.mFramesPerPacket;
	
	audioError = AudioConverterNew(&dataFormat, &convertedFormat, &audioConverter);
	if(audioError != noErr){
		CJLOG(@"Error: %@ | loadFile, AudioConverterNew", GetNSStringFromAudioQueueError(audioError));
	}
	
	CJLOG(@"Info: Audio Format: %@\n"
		  "Sample Rate: %f\n"
		  "Bytes Per Packet: %d, isVBR? %s\n"
		  "Frames Per Packet: %d\n"
		  "Data type: %s\n",
		  GetNSStringFrom4CharCode(convertedFormat.mFormatID),
		  convertedFormat.mSampleRate,
		  convertedFormat.mBytesPerPacket,
		  (convertedFormat.mBytesPerPacket == 0)?"Y":"N",
		  convertedFormat.mFramesPerPacket,
		  (convertedFormat.mFormatFlags & kAudioFormatFlagIsFloat)?"Float":"SInt"
		  );
	convertedDataLength = convertedFormat.mBytesPerPacket * numPacketsToRead;
	
	uintptr_t mask			= ~(uintptr_t)(31);
	convertedDataRaw		= malloc(convertedDataLength + 31);
	memset(convertedDataRaw, 0, convertedDataLength+31);
	convertedData			= (Float32*)(((uintptr_t)convertedDataRaw+31) & mask);
	
	dsp						= new CJDSP;
	audioError = dsp->initialize(dataFormat.mSampleRate, 1024, 20, (int)CMTimeGetSeconds(audioAsset.duration));
	if(audioError != noErr){
		CJLOG(@"Error: DSP::initialize, %d", audioError);
	}
	
#if DEVTEST_BUILD
	//	dsp->beatDetector->debugmode	= true;
#endif
	
#pragma mark State
	//currentVolume			= 1.0f;
	isLooping				= NO;
	trackEnded				= NO;
	audioState				= E_CJMP_State_NotReady;
	
	/*
	 dispatch_queue_t myNewRunLoop = dispatch_queue_create("com.hansoninteractive.CJAVAssetPlayer.preprocessAudio", NULL);
	 dispatch_async(myNewRunLoop, ^{
	 [self preProcessAudio];
	 //[self performSelectorOnMainThread:@selector(finishedProcessing) withObject:nil waitUntilDone:NO];
	 [self finishedProcessing];
	 });
	 dispatch_release(myNewRunLoop);
	 */
	
	[self finishedProcessing];
	
	return YES;
}

- (void) finishedProcessing
{
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
	
	if(![self setupReaderAndOutput]){
		CJLOG(@"After preprocessing. Failed to re-setup the AVAsset reader/output");
		[self close];
		[pool drain];
		return;
	}
	
	packetIndex = 0;
	pauseDuration = 0;
	dsp->beatDetector->resetTiming();
	//	dsp->beatDetector->reset(false);
	
	//	dsp->beatDetector->last_timer = 0;
	//	dsp->beatDetector->bpm_timer = 0;
	
	audioState				= E_CJMP_State_Stopped;
	[self performSelectorOnMainThread:@selector(postTrackSourceChangedNotification:) withObject:nil waitUntilDone:YES];
	[pool drain];
}

- (void)preProcessAudio
{
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
	
	CJLOG(@"preProcessAudio");
	NSTimeInterval now = SecondsSinceStart();
	
	if(audioReader.status != AVAssetReaderStatusReading){
		NSLog(@"Asset reader failed to start reading: %@", [audioReader.error localizedDescription]);
		[pool drain];
		return;
	}
	
	BeatDetector *det = dsp->beatDetector;
	int minPacketsToBelieveBPM = SecondsToSamples(20.0);
	int maxPacketsToProcess	= SecondsToSamples(70.0);
	packetIndex = 0;
	int rCount = 0;
	int i = 0;
	do{
		rCount = [self processAudioBuffer:buffers[i]];
		i++;
		i %= CJMP_NUM_QUEUE_BUFFERS;
		
		if(packetIndex >= minPacketsToBelieveBPM){
			if(det &&
			   det->winning_et &&
			   det->win_bpm_int &&
			   (
				(det->bpm_contest[det->win_bpm_int] > 30.0f && !dsp->bpm_latch) ||
				(det->bpm_contest[det->win_bpm_int] > 25.0f && dsp->bpm_latch)
				)
			   ){
				CJLOG(@"Locked onto BPM");
				break;
			}
		}
	}while(rCount > 0 && packetIndex < maxPacketsToProcess);
	
	CJLOG(@"Processed %f seconds of audio in %f seconds", (float)SamplesToSeconds((int)packetIndex), (float)(SecondsSinceStart()-now));
	
	packetIndex = 0;
	
	
	[pool drain];
}

- (void)prefetchBuffers
{
	CJLOG(@"PREFETCH buffers");
	if(audioReader.status != AVAssetReaderStatusReading){
		if(![audioReader startReading]){
			NSLog(@"Asset reader failed to start reading: %@", [audioReader.error localizedDescription]);
			return;
		}
	}
	// prime buffers with some data
	for(int i = 0; i < CJMP_NUM_QUEUE_BUFFERS; i++){
		if([self readPacketsIntoBuffer:buffers[i]] < 1){
			//			if(isLooping){
			// End Of File reached, so rewind and refill the buffer using the beginning of the file instead
			//				packetIndex = 0;
			//[self readPacketsIntoBuffer:buffers[i]];
			//			}else{
			// this might happen if the file was so short that it needed less buffers than we planned on using
			break;
			//			}
		}
	}
}

- (void)seek:(UInt64)packetOffset
{
	NSLog(@"seek unsupported");
	if(audioState == E_CJMP_State_Closed)
		return;
	
	E_CJMP_State audioStateNow	= audioState;
	audioState					= E_CJMP_State_Seeking;
	
	BOOL isPlayingNow	= (audioStateNow == E_CJMP_State_Playing);
	
	[self stop];
	
	//	packetIndex			= packetOffset;
	if(isPlayingNow)
		[self play];
}

- (void)setVolume:(Float32)volume
{
	if(currentVolume == volume){
		return;
	}
	currentVolume = volume;
	OSStatus audioError	= AudioQueueSetParameter(queue, kAudioQueueParam_Volume, currentVolume);
	if(audioError != noErr){
		CJLOG(@"Error: %@ | setVolume, AudioQueueSetParameter, kAudioQueueParam_Volume", GetNSStringFromAudioQueueError(audioError));
	}
}

- (AudioTimeStamp)getCurrentTime
{
	AudioTimeStamp currentTime;
	Boolean outTimelineDiscontinuity;
	OSStatus audioError = AudioQueueGetCurrentTime (
													queue,
													queueTimeline,
													&currentTime,
													&outTimelineDiscontinuity
													);
	if(audioError != noErr){
		currentTime.mSampleTime	= -1.0;
		CJLOG(@"Error: %@ | getCurrentTime, AudioQueueGetCurrentTime", GetNSStringFromAudioQueueError(audioError));
	}else{
		timeOfLastCurrentTimeCheck	= SecondsSinceStart();
	}
	return currentTime;
}

- (UInt32)getCurrentTimeInSamples
{
	return SecondsToSamples([self getCurrentTimeInSeconds]);
}

- (NSTimeInterval)getCurrentTimeInSecondsNoCache
{
	return [self getCurrentTimeInSeconds];
}

- (NSTimeInterval)getCurrentTimeInSeconds
{
	return SecondsSinceStart() - playbackStartTime - pauseDuration;//SamplesToSeconds([self getCurrentTimeInSamples]);
}

- (NSTimeInterval) setPosition:(NSTimeInterval)position
{
	if(audioState == E_CJMP_State_Closed)
		return -1;
	
	CJLOG(@"Set Position: %.4f", position);
	
	//	[audioReader cancelReading];
	CMTime startTime		= CMTimeMake(position*1000, 1000);
	CMTime playDuration		= kCMTimePositiveInfinity;
	audioReader.timeRange = CMTimeRangeMake(startTime, playDuration);
	//	[audioReader startReading];
	packetIndex				= SecondsToSamples(position);
	
	return (NSTimeInterval)(startTime.value/(NSTimeInterval)startTime.timescale);
}

- (void)play
{
	if(audioState == E_CJMP_State_Closed || audioState == E_CJMP_State_Playing){
		CJLOG(@"Not playing. Closed or already playing.");
		return;
	}
	
	if(audioState == E_CJMP_State_Stopped || audioState == E_CJMP_State_Seeking)
		[self prefetchBuffers];
	
	OSStatus audioError;
	
	if(audioState != E_CJMP_State_Paused){
		audioError = AudioQueuePrime(queue, 1, nil);	
		if(audioError != noErr){
			CJLOG(@"Error: %@ | play, AudioQueuePrime", GetNSStringFromAudioQueueError(audioError));
			return;
		}
	}
	
	audioError = AudioQueueStart(queue, NULL);
	if(audioError != noErr){
		CJLOG(@"Error: %@ | play, AudioQueueStart", GetNSStringFromAudioQueueError(audioError));
	}
	
	if(audioState == E_CJMP_State_Paused){
		pauseDuration		+= SecondsSinceStart() - pauseStartTime;
	}else{
		playbackStartTime	= SecondsSinceStart();
	}
	
	audioError = AudioQueueSetParameter(queue, kAudioQueueParam_Volume, currentVolume);
	if(audioError != noErr){
		CJLOG(@"Error: %@ | play, AudioQueueSetParameter, kAudioQueueParam_Volume", GetNSStringFromAudioQueueError(audioError));
	}
	
	if(audioState == E_CJMP_State_Paused){
		[self performSelectorOnMainThread:@selector(postTrackStartedPlayingNotification:) withObject:nil waitUntilDone:NO];
	}
	
	audioState	= E_CJMP_State_Playing;
}

- (void)pause
{
	if(audioState != E_CJMP_State_Playing)
		return;
	
	audioState = E_CJMP_State_Paused;
	
	pauseStartTime		= SecondsSinceStart();
	
	OSStatus audioError	= AudioQueuePause(queue);
	if(audioError != noErr){
		CJLOG(@"Error: %@ | pause, AudioQueuePause", GetNSStringFromAudioQueueError(audioError));
	}
	[self performSelectorOnMainThread:@selector(postTrackStoppedPlayingNotification:) withObject:nil waitUntilDone:NO];
}

- (void) cancelFading
{
	
}

- (void)fadeOutAndPauseOverDuration:(NSTimeInterval)fadeDuration
{
	if(audioState != E_CJMP_State_Playing)
		return;
	
	if(currentVolume < 0.05f){
		[self pause];
		return;
	}
	
	NSThread *fadeThread	= [[NSThread alloc] initWithTarget:self selector:@selector(fadeOutOverDurationThenPause:) object:[NSNumber numberWithDouble:fadeDuration]];
	[fadeThread start];
	[fadeThread release];
}

- (void)fadeOutOverDurationThenPause:(NSNumber *)fadeDuration
{
	NSAutoreleasePool *pool	= [[NSAutoreleasePool alloc] init];
	
	BOOL continueLooping		= ![[NSThread currentThread] isCancelled];
	if(continueLooping){
		NSTimeInterval fadeD		= [fadeDuration doubleValue];
		float curVolume				= self.volume;
		float durationPerStep		= 0.05f;
		int numSteps				= (int)(fadeD / durationPerStep);
		float volumePerStep			= curVolume / (float)numSteps;
		
		while(continueLooping){
			if([[NSThread currentThread] isCancelled] || curVolume <= 0.0f){
				if(curVolume <= 0.0f){
					[self pause];
				}
				break;
			}
			
			curVolume				-= volumePerStep;
			OSStatus audioError		= AudioQueueSetParameter(queue, kAudioQueueParam_Volume, MAX(curVolume, 0.0f));
			if(audioError != noErr){
				CJLOG(@"Error: %@ | fadeOutOverDurationThenPause, AudioQueueSetParameter, kAudioQueueParam_Volume", GetNSStringFromAudioQueueError(audioError));
			}
			
			[NSThread sleepForTimeInterval:durationPerStep];
		}
	}
	
	[pool drain];
}

- (void)fadeOutAndCloseOverDuration:(NSTimeInterval)fadeDuration
{
	if(audioState == E_CJMP_State_Closed)
		return;
	if(audioState != E_CJMP_State_Playing){
		[self close];
		return;
	}
	
	if(currentVolume < 0.05f){
		[self close];
		return;
	}
	
	NSThread *fadeThread	= [[NSThread alloc] initWithTarget:self selector:@selector(fadeOutOverDurationThenClose:) object:[NSNumber numberWithDouble:fadeDuration]];
	[fadeThread start];
	[fadeThread release];
}

- (void)resume
{
	if(audioState == E_CJMP_State_Closed)
		return;
	
	[self play];
}

- (void)fadeInAndResumeOverDuration:(NSTimeInterval)fadeDuration
{
	if(audioState == E_CJMP_State_Closed)
		return;
	
	if(currentVolume > 0.95f){
		[self resume];
		return;
	}
	
	NSThread *fadeThread	= [[NSThread alloc] initWithTarget:self selector:@selector(resumeAndFadeInOverDuration:) object:[NSNumber numberWithDouble:fadeDuration]];
	[fadeThread start];
	[fadeThread release];
}

- (void)resumeAndFadeInOverDuration:(NSNumber *)fadeDuration
{
	NSAutoreleasePool *pool	= [[NSAutoreleasePool alloc] init];
	
	BOOL continueLooping		= ![[NSThread currentThread] isCancelled];
	if(continueLooping){
		NSTimeInterval fadeD		= [fadeDuration doubleValue];
		float curVolume				= 0.0f;
		float origVolume			= self.volume;
		float durationPerStep		= 0.05f;
		int numSteps				= (int)(fadeD / durationPerStep);
		float volumePerStep			= origVolume / (float)numSteps;
		
		[self resume];
		
		while(continueLooping){
			if([[NSThread currentThread] isCancelled] || curVolume >= origVolume){
				break;
			}
			
			curVolume				+= volumePerStep;
			OSStatus audioError		= AudioQueueSetParameter(queue, kAudioQueueParam_Volume, MIN(curVolume, origVolume));
			if(audioError != noErr){
				CJLOG(@"Error: %@ | resumeAndFadeInOverDuration, AudioQueueSetParameter, kAudioQueueParam_Volume", GetNSStringFromAudioQueueError(audioError));
			}
			
			[NSThread sleepForTimeInterval:durationPerStep];
		}
	}
	
	[pool drain];
}

- (void)stop
{
	if(audioState == E_CJMP_State_Closed)
		return;
	
	if(audioState != E_CJMP_State_Seeking)
		audioState	= E_CJMP_State_Stopped;
	
	packetIndex = 0;
	playbackStartTime	= 0.0;
	pauseStartTime		= 0.0;
	pauseDuration		= 0.0;
	
	OSStatus audioError;
	audioError		= AudioQueueSetParameter(queue, kAudioQueueParam_Volume, 0.0f);
	if(audioError != noErr){
		CJLOG(@"Error: %@ | stop, AudioQueueSetParameter, kAudioQueueParam_Volume", GetNSStringFromAudioQueueError(audioError));
	}
	audioError		= AudioQueueStop(queue, YES);
	if(audioError != noErr){
		CJLOG(@"Error: %@ | stop, AudioQueueStop", GetNSStringFromAudioQueueError(audioError));
	}
}

- (void)stopKeepPosition
{
	[self pause];
}

- (void)restorePosition
{
	
}

- (void)fadeOutAndStopOverDuration:(NSTimeInterval)fadeDuration
{
	if(audioState == E_CJMP_State_Closed)
		return;
	
	if(audioState != E_CJMP_State_Playing){
		[self stop];
		return;
	}
	
	if(currentVolume < 0.05f){
		[self stop];
		return;
	}
	
	NSThread *fadeThread	= [[NSThread alloc] initWithTarget:self selector:@selector(fadeOutOverDurationThenStop:) object:[NSNumber numberWithDouble:fadeDuration]];
	[fadeThread start];
	[fadeThread release];
}

- (void)fadeOutOverDurationThenStop:(NSNumber *)fadeDuration
{
	NSAutoreleasePool *pool	= [[NSAutoreleasePool alloc] init];
	
	BOOL continueLooping		= ![[NSThread currentThread] isCancelled];
	if(continueLooping){
		NSTimeInterval fadeD		= [fadeDuration doubleValue];
		float curVolume				= self.volume;
		float durationPerStep		= 0.05f;
		int numSteps				= (int)(fadeD / durationPerStep);
		float volumePerStep			= curVolume / (float)numSteps;
		
		while(continueLooping){
			if([[NSThread currentThread] isCancelled] || curVolume <= 0.0f){
				if(curVolume <= 0.0f){
					[self stop];
				}
				break;
			}
			
			curVolume				-= volumePerStep;
			OSStatus audioError		= AudioQueueSetParameter(queue, kAudioQueueParam_Volume, MAX(curVolume, 0.0f));
			if(audioError != noErr){
				CJLOG(@"Error: %@ | fadeOutOverDurationThenStop, AudioQueueSetParameter, kAudioQueueParam_Volume", GetNSStringFromAudioQueueError(audioError));
			}
			
			[NSThread sleepForTimeInterval:durationPerStep];
		}
	}
	
	[pool drain];
}

- (void)fadeOutOverDurationThenClose:(NSNumber *)fadeDuration
{
	NSAutoreleasePool *pool	= [[NSAutoreleasePool alloc] init];
	
	BOOL continueLooping		= ![[NSThread currentThread] isCancelled];
	if(continueLooping){
		NSTimeInterval fadeD		= [fadeDuration doubleValue];
		float curVolume				= self.volume;
		float durationPerStep		= 0.05f;
		int numSteps				= (int)(fadeD / durationPerStep);
		float volumePerStep			= curVolume / (float)numSteps;
		
		while(continueLooping){
			if([[NSThread currentThread] isCancelled] || curVolume <= 0.0f){
				if(curVolume <= 0.0f){
					[self close];
				}
				break;
			}
			
			curVolume				-= volumePerStep;
			OSStatus audioError		= AudioQueueSetParameter(queue, kAudioQueueParam_Volume, MAX(curVolume, 0.0f));
			if(audioError != noErr){
				CJLOG(@"Error: %@ | fadeOutOverDurationThenClose, AudioQueueSetParameter, kAudioQueueParam_Volume", GetNSStringFromAudioQueueError(audioError));
			}
			
			[NSThread sleepForTimeInterval:durationPerStep];
		}
	}
	
	[pool drain];
}

- (void) setAudioState:(E_CJMP_State)newState
{
	if(audioState == newState)
		return;
	audioState	= newState;
	//[self postAudioStateChangedNotification];
}

- (BOOL) isPlaying
{
	return (audioState == E_CJMP_State_Playing);
}

- (BOOL) isPaused
{
	return (audioState == E_CJMP_State_Paused);
}

#pragma mark -
#pragma mark Audio Session

- (void) audioSessionInterrupted:(NSNotification *)notification
{
	if(audioState != E_CJMP_State_Closed){
		CJLOG(@"MusicTrack: Session Interrupted and had current track, saving position, then closing file.");
		
		[[NSNotificationCenter defaultCenter] postNotificationName:CJMusicPlayerStoppedPlayingNotification object:self];
		willDispatchNotifications	= NO;
		positionBeforeInterruption	= (NSTimeInterval)[self getCurrentTimeInSeconds];
		
		//Manually close track
		OSStatus audioError;
		audioError					= AudioQueueSetParameter(queue, kAudioQueueParam_Volume, 0.0f);
		if(audioError != noErr){
			CJLOG(@"Error: %@ | audioSessionInterrupted, AudioQueueSetParameter, kAudioQueueParam_Volume", GetNSStringFromAudioQueueError(audioError));
		}
		audioError					= AudioQueueStop(queue, YES); // <-- YES means stop immediately
		if(audioError != noErr){
			CJLOG(@"Error: %@ | audioSessionInterrupted, AudioQueueStop", GetNSStringFromAudioQueueError(audioError));
		}
		audioError					= AudioQueueDispose(queue, YES);// <-- YES means do so synchronously
		if(audioError != noErr){
			CJLOG(@"Error: %@ | audioSessionInterrupted, AudioQueueDispose", GetNSStringFromAudioQueueError(audioError));
		}
		queue				= NULL;
		queueTimeline		= NULL;
		
		if(packetDescs != nil)
			free(packetDescs);
		packetDescs			= nil;
		audioState	= E_CJMP_State_Closed;
		
		sessionWasInterrupted	= YES;
	}
}

- (void) audioSessionRestored:(NSNotification *)notification
{
	if(sessionWasInterrupted){
		CJLOG(@"MusicTrack: Session Restored and had current track, loading file and restoring position.");
		
		if([self prepareToPlayAsset:audioAsset]){			
			[self setPosition:positionBeforeInterruption];
			willDispatchNotifications	= YES;
		}
		
		sessionWasInterrupted	= NO;
	}
}

#pragma mark -
#pragma mark Callback

static void audioQueuePropertyListenerCallback(void *inUserData, AudioQueueRef queueObject, AudioQueuePropertyID propertyID)
{
	if (propertyID == kAudioQueueProperty_IsRunning){
		UInt32 isRunningVal;
		UInt32 size	= sizeof(isRunningVal);
		OSStatus readPropOK	= AudioQueueGetProperty(queueObject, kAudioQueueProperty_IsRunning, &isRunningVal, &size);
		if(readPropOK != noErr){
			//couldn't read property
			CJLOG(@"Error: %@ | audioQueuePropertyListenerCallback, AudioQueueGetProperty, kAudioQueueProperty_IsRunning", GetNSStringFromAudioQueueError(readPropOK));
		}else{
			// redirect back to the class to handle it there instead, so we have direct access to the instance variables
			NSAutoreleasePool *pool	= [NSAutoreleasePool new];
			[(CJAVAssetPlayer *)inUserData performSelectorOnMainThread:@selector(playBackIsRunningStateChanged:) withObject:[NSNumber numberWithBool:(isRunningVal==1)?YES:NO] waitUntilDone:NO];
			[pool drain];
		}
	}
}

- (void)playBackIsRunningStateChanged:(NSNumber *)isRunningN
{
	BOOL isRunning	= [isRunningN boolValue];
	CJLOG(@"%@ playBackIsRunningStateChanged: %s and trackEnded: %s", self, isRunning?"Playing":"Stopped", trackEnded?"Y":"N");
	if(isRunning == NO){
		//stopped
		if(trackEnded){
			audioState = E_CJMP_State_Stopped;
			
			[self postTrackStoppedPlayingNotification:nil];
			[self postTrackFinishedPlayingNotification:nil];
			
			// go ahead and close the track now
			[self close];
		}
	}else{
		//started
		//systemTimeAtPlayStart	= SecondsSinceStart();
		[self postTrackStartedPlayingNotification:nil];
	}
}

static void BufferCallback(void *inUserData, AudioQueueRef inAQ, AudioQueueBufferRef buffer)
{
	// redirect back to the class to handle it there instead, so we have direct access to the instance variables
	[(CJAVAssetPlayer *)inUserData callbackForBuffer:buffer];
}

- (void)callbackForBuffer:(AudioQueueBufferRef)buffer
{
	// I guess it's possible for the callback to continue to be called since this is in another thread, so to be safe,
	// don't do anything else if the track is closed, and also don't bother reading anymore packets if the track ended
	//if(audioState == E_CJMP_State_Closed || audioState == E_CJMP_State_Seeking || trackEnded)
	if(audioState != E_CJMP_State_Playing || trackEnded){
		CJLOG(@"Warning: callbackForBuffer while not playing or trackEnded");
		return;
	}
	
	int readCount = [self readPacketsIntoBuffer:buffer];
	if(readCount < 0){
		//encountered error
		return;
	}
	if(readCount == 0){
		if(isLooping){
			CJLOG(@"Reached end of buffer, but isLooping, so reset packetIndex and read more packets into buffer");
			[self performSelectorOnMainThread:@selector(postTrackLoopedNotification:) withObject:nil waitUntilDone:NO];
			
			// End Of File reached, so rewind and refill the buffer using the beginning of the file instead
			[self setPosition:0];
			[self readPacketsIntoBuffer:buffer];
		}else{
			CJLOG(@"Reached end of buffer, not looping, so set trackEnded = YES and stop audio queue asynch so it finishes playing the remaining buffers");
			// set it to stop, but let it play to the end, where the property listener will pick up that it actually finished
			trackEnded			= YES;
			OSStatus audioError	= AudioQueueStop(queue, NO);
			if(audioError != noErr){
				CJLOG(@"Error: %@ | callbackForBuffer, AudioQueueStop", GetNSStringFromAudioQueueError(audioError));
			}
		}
	}
}

- (void) postTrackSourceChangedNotification:(id)object
{
	if(willDispatchNotifications)
		[[NSNotificationCenter defaultCenter] postNotificationName:CJMusicPlayerSourceChangedNotification object:self];
}

- (void)postTrackStartedPlayingNotification:(id)object
{
	timeOfLastCurrentTimeCheck	= 0;
	timeOfLastEstimatedTimeCheck= 0;
	// if we're here then we're in the main thread as specified by the callback, so now we can post notification that
	// the track is started without the notification observer(s) having to worry about thread safety and autorelease pools
	if(willDispatchNotifications)
		[[NSNotificationCenter defaultCenter] postNotificationName:CJMusicPlayerStartedPlayingNotification object:self];
}

- (void)postTrackStoppedPlayingNotification:(id)object
{
	// if we're here then we're in the main thread as specified by the callback, so now we can post notification that
	// the track is stopped without the notification observer(s) having to worry about thread safety and autorelease pools
	if(willDispatchNotifications)
		[[NSNotificationCenter defaultCenter] postNotificationName:CJMusicPlayerStoppedPlayingNotification object:self];
}

- (void)postTrackLoopedNotification:(id)object
{
	// if we're here then we're in the main thread as specified by the callback, so now we can post notification that
	// the track looped without the notification observer(s) having to worry about thread safety and autorelease pools
	if(willDispatchNotifications)
		[[NSNotificationCenter defaultCenter] postNotificationName:CJMusicPlayerLoopedNotification object:self];
}

- (void)postTrackFinishedPlayingNotification:(id)object
{
	// if we're here then we're in the main thread as specified by the callback, so now we can post notification that
	// the track is done without the notification observer(s) having to worry about thread safety and autorelease pools
	if(willDispatchNotifications)
		[[NSNotificationCenter defaultCenter] postNotificationName:CJMusicPlayerFinishedPlayingNotification object:self];
}

#pragma mark Audio Queue read callback

- (int)readPacketsIntoBuffer:(AudioQueueBufferRef)buffer
{
	if(audioState == E_CJMP_State_Closed){
		CJLOG(@"Error: not reading packets because state is closed.");
		return -1;
	}
	
	if([audioReader status] == AVAssetReaderStatusCompleted){
		return 0;
	}
	if([audioReader status] != AVAssetReaderStatusReading){
		CJLOG(@"Attempted to read packets into buffer while asset reader is not reading. Returning.");
		return -1;
	}
	
	NSTimeInterval absNow	= CFAbsoluteTimeGetCurrent();
	
	NSAutoreleasePool *pool = [NSAutoreleasePool new];	
	
	int audioBPS			= (float)(dataFormat.mSampleRate * dataFormat.mBitsPerChannel * dataFormat.mChannelsPerFrame)/8;
	NSTimeInterval playTime	= NSTimeInterval(numPacketsToRead * dataFormat.mBytesPerPacket)/audioBPS;
	//CJLOG(@"readPacketsIntoBuffer %f", playTime);
	
	
	UInt32		numBytes, numPackets;
	OSStatus	audioError = noErr;
	// read packets into buffer from file
	numPackets	= numPacketsToRead;
	
#pragma mark AVAsset to audio Queue	
	CMSampleBufferRef myBuff;
	CMBlockBufferRef blockBufferOut;
	AudioBufferList buffList;
	CFAllocatorRef structAllocator = NULL;
	CFAllocatorRef memoryAllocator = NULL;
	
	UInt32 myFlags = 0;
	
	// For debugging purposes. Status should be "Reading" throughout this loop
	//CheckReaderStatus(audioReader);
	
	myBuff = [audioReaderMixerOutput copyNextSampleBuffer];
	if(!myBuff){
		//CJLOG(@"Next sample buffer is null");
		[pool drain];
		return 0;
	}
	
	/*
	 CMSampleTimingInfo curTimeInfo;
	 OSStatus err = CMSampleBufferGetSampleTimingInfo(myBuff, 0, &curTimeInfo);
	 if(err != noErr){
	 CJLOG(@"Error: %@ | CMSampleBufferGetSampleTimingInfo", GetNSStringFromAudioQueueError(err));
	 }
	 NSTimeInterval curTime		= curTimeInfo.presentationTimeStamp.value/(NSTimeInterval)curTimeInfo.presentationTimeStamp.timescale;
	 CJLOG(@"Cur Time: %f", curTime);
	 */
	//	CMItemCount numSamples = CMSampleBufferGetNumSamples(myBuff);
	
	size_t sizeNeeded;
	audioError = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
																		 myBuff,
																		 &sizeNeeded,
																		 &buffList,
																		 sizeof(buffList),
																		 structAllocator,
																		 memoryAllocator,
																		 myFlags,
																		 &blockBufferOut
																		 );
	if(audioError != noErr){
		CJLOG(@"Error: %@ | CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer", GetNSStringFromAudioQueueError(audioError));
	}
	
	
	CFRelease(myBuff);
	
	//CJLOG(@"AudiobufferList size needed: %d", sizeNeeded);
	//CJLOG(@"Buffer capacity: %d, Buffer data length: %d", buffer->mAudioDataBytesCapacity, CMBlockBufferGetDataLength(blockBufferOut));
	size_t dataLength	= MIN(buffer->mAudioDataBytesCapacity, CMBlockBufferGetDataLength(blockBufferOut));
	numBytes			= dataLength;
	
	audioError = CMBlockBufferCopyDataBytes(
											blockBufferOut,
											0,
											dataLength,
											buffer->mAudioData
											);
	
	if(audioError != noErr){
		CJLOG(@"Error: %@ | CMBlockBufferCopyDataBytes", GetNSStringFromAudioQueueError(audioError));
	}
	
	CFRelease(blockBufferOut);
	
#pragma mark FFT
	if(numPackets >= (uint)dsp->n){
		//Convert to floating point single channel
		vDSP_vflt16((short int *)buffer->mAudioData, 2, convertedData, 1, numPackets);
		float floatScale = 32767.f;
		vDSP_vsdiv(convertedData, 1, &floatScale, convertedData, 1, numPackets);
		
		int cIDX	= 0;
		int cI		= 0;
		int cMax	= numPackets;
		int cStep	= dsp->n;
		float *samples_ptr	= convertedData;
		NSTimeInterval sampleTime	= SamplesToSeconds((uint)packetIndex);
		NSTimeInterval cDT			= playTime / (NSTimeInterval)(cMax/cStep);
		for(cIDX=0, cI=0; cIDX < cMax; cIDX += cStep, cI++){
			dsp->renderFFT(samples_ptr);
			dsp->analyzeBPM(sampleTime);
			sampleTime += cDT;
			samples_ptr += dsp->n;
		}
	}
#pragma mark end FFT
	
	//CJLOG(@"numPackets: %d, numSamples: %d, numBytes: %d", numPackets, numSamples, numBytes);
	
	//CJLOG(@"Buffer packet desc count: %d, capacity: %d", buffer->mPacketDescriptionCount, buffer->mPacketDescriptionCapacity);
	buffer->mAudioDataByteSize = numBytes;
	audioError	= AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
	if(audioError != noErr){
		CJLOG(@"Error: %@ | readPacketsIntoBuffer, AudioQueueEnqueueBuffer", GetNSStringFromAudioQueueError(audioError));
	}
	
	[pool drain];
	
	NSTimeInterval elapsedTime = CFAbsoluteTimeGetCurrent() - absNow;
	printf("Render Audio cpu time: %f\n", elapsedTime);
	
	packetIndex += numPackets;
	
	return numPackets;
}

- (int) processAudioBuffer:(AudioQueueBufferRef)buffer
{
	if(audioState == E_CJMP_State_Closed){
		CJLOG(@"Error: not reading packets because state is closed.");
		return -1;
	}
	
	if([audioReader status] == AVAssetReaderStatusCompleted){
		return 0;
	}
	
	if([audioReader status] != AVAssetReaderStatusReading){
		CJLOG(@"Attempted to read packets into buffer while asset reader is not reading. Returning.");
		return -1;
	}
	
	//NSTimeInterval absNow	= CFAbsoluteTimeGetCurrent();
	
	NSAutoreleasePool *pool = [NSAutoreleasePool new];	
	
	int audioBPS			= (float)(dataFormat.mSampleRate * dataFormat.mBitsPerChannel * dataFormat.mChannelsPerFrame)/8;
	NSTimeInterval playTime	= NSTimeInterval(numPacketsToRead * dataFormat.mBytesPerPacket)/audioBPS;
	
	UInt32		numBytes, numPackets;
	OSStatus	audioError = noErr;
	// read packets into buffer from file
	numPackets	= numPacketsToRead;
	
#pragma mark AVAsset data
	CMSampleBufferRef myBuff;
	CMBlockBufferRef blockBufferOut;
	AudioBufferList buffList;
	CFAllocatorRef structAllocator = NULL;
	CFAllocatorRef memoryAllocator = NULL;
	
	UInt32 myFlags = 0;
	
	// For debugging purposes. Status should be "Reading" throughout this loop
	//CheckReaderStatus(audioReader);
	
	myBuff = [audioReaderMixerOutput copyNextSampleBuffer];
	if(!myBuff){
		//CJLOG(@"Next sample buffer is null");
		[pool drain];
		return 0;
	}
	
	size_t sizeNeeded;
	audioError = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
																		 myBuff,
																		 &sizeNeeded,
																		 &buffList,
																		 sizeof(buffList),
																		 structAllocator,
																		 memoryAllocator,
																		 myFlags,
																		 &blockBufferOut
																		 );
	if(audioError != noErr){
		CJLOG(@"Error: %@ | CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer", GetNSStringFromAudioQueueError(audioError));
	}
	
	CFRelease(myBuff);
	
	//CJLOG(@"AudiobufferList size needed: %d", sizeNeeded);
	//CJLOG(@"Buffer capacity: %d, Buffer data length: %d", buffer->mAudioDataBytesCapacity, CMBlockBufferGetDataLength(blockBufferOut));
	size_t dataLength	= MIN(buffer->mAudioDataBytesCapacity, CMBlockBufferGetDataLength(blockBufferOut));
	numBytes			= dataLength;
	
	audioError = CMBlockBufferCopyDataBytes(
											blockBufferOut,
											0,
											dataLength,
											buffer->mAudioData
											);
	
	if(audioError != noErr){
		CJLOG(@"Error: %@ | CMBlockBufferCopyDataBytes", GetNSStringFromAudioQueueError(audioError));
	}
	
	CFRelease(blockBufferOut);
	
#pragma mark FFT
	if(numPackets >= (uint)dsp->n){
		//Convert to floating point single channel
		vDSP_vflt16((short int *)buffer->mAudioData, 2, convertedData, 1, numPackets);
		float floatScale = 32767.f;
		vDSP_vsdiv(convertedData, 1, &floatScale, convertedData, 1, numPackets);
		
		int cIDX	= 0;
		int cI		= 0;
		int cMax	= numPackets;
		int cStep	= dsp->n;
		float *samples_ptr	= convertedData;
		NSTimeInterval sampleTime	= SamplesToSeconds((uint)packetIndex);
		NSTimeInterval cDT			= playTime / (NSTimeInterval)(cMax/cStep);
		for(cIDX=0, cI=0; cIDX < cMax; cIDX += cStep, cI++){
			dsp->renderFFT(samples_ptr);
			dsp->analyzeBPM(sampleTime);
			sampleTime += cDT;
			samples_ptr += dsp->n;
		}
	}
#pragma mark end FFT
	
	[pool drain];
	
	//NSTimeInterval elapsedTime = CFAbsoluteTimeGetCurrent() - absNow;
	//printf("Render Audio cpu time: %f\n", elapsedTime);
	
	packetIndex += numPackets;
	
	return numPackets;
}

@end
#endif