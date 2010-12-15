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

#define CheckReaderStatus(__READER__) OAL_LOG_DEBUG(@"AVAssetReader Status: %@", [OALAudioSupport stringFromAVAssetReaderStatus:[(__READER__) status]]);
#define CompareReaderStatus(__READER__, __STATUS__)  OAL_LOG_DEBUG(@"AVAssetReader Status: %@, Expected %@", [OALAudioSupport stringFromAVAssetReaderStatus:[(__READER__) status]], [OALAudioSupport stringFromAVAssetReaderStatus:(__STATUS__)]);

@interface OALAudioPlayerAudioQueueAVAssetReader (PrivateMethods)
- (BOOL)prefetchBuffers;
- (void)getCurrentTime:(AudioTimeStamp *)currentTime;
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
	[url release];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	[super dealloc];
}

- (void)close
{
	if(state == OALPlayerStateClosed)
		return;
	state				= OALPlayerStateClosed;
	
	OAL_LOG_DEBUG(@"Closing AudioQueue player.");
	
	[assetReaderMixerOutput release];
	assetReaderMixerOutput	= nil;
	
	[assetReaderMixerOutputSeeking release];
	assetReaderMixerOutputSeeking = nil;
	
	[assetReader cancelReading];
	[assetReader release];
	assetReader				= nil;
	
	[assetReaderSeeking cancelReading];
	[assetReaderSeeking release];
	assetReaderSeeking		= nil;
	
	[asset release];
	asset					= nil;
	
	loopCount			= 0;
	numberOfLoops		= 0;
	trackEnded			= NO;
	duration			= 0;
	//	volume		= 1.0f;
	
	OSStatus audioError;
	
	//AudioQueueSetParameter(queue, kAudioQueueParam_Volume, 0.0f);
	
	if(queue){
		audioError			= AudioQueueFlush(queue);
		REPORT_AUDIO_QUEUE_CALL(audioError, @"AudioQueueFlush");
		
		if(queueIsRunning)
			queueIsStopping		= YES;
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
	queueIsRunning		= NO;
	
	if(packetDescs)
		free(packetDescs);
	packetDescs			= NULL;
	
	packetIndex			= 0;
	packetIndexSeeking	= 0;
	seekTimeOffset		= 0.0;
	lastCurrentTime		= 0.0;
	
	status				= OALPlayerStatusUnknown;
	
	OAL_LOG_DEBUG(@"audio queue player closed");
}

- (id) initWithContentsOfURL:(NSURL *)inURL seekTime:(NSTimeInterval)inSeekTime error:(NSError **)outError
{
	self = [super init];
	if(self){
		url						= [inURL retain];
		playerType				= OALAudioPlayerTypeAudioQueueAVAssetReader;
		state					= OALPlayerStateClosed;
		status					= OALPlayerStatusUnknown;
		loopCount				= 0;
		numberOfLoops			= 0;
		trackEnded				= NO;
		queueIsRunning			= NO;
		queueIsStopping			= NO;
		volume					= 1.0f;
		pan						= 0.5f;
		asset					= nil;
		assetReader				= nil;
		assetReaderSeeking		= nil;
		assetReaderMixerOutput	= nil;
		assetReaderMixerOutputSeeking = nil;
		queue					= NULL;
		queueTimeline			= NULL;
		packetIndex				= 0;
		packetIndexSeeking		= 0;
		seekTimeOffset			= 0.0;
		lastCurrentTime			= 0.0;
		
		dataFormat = (AudioStreamBasicDescription){0};
		dataFormat.mSampleRate				= 44100.0;
		dataFormat.mFormatID				= kAudioFormatLinearPCM;
		dataFormat.mFormatFlags				= kAudioFormatFlagsCanonical;
		dataFormat.mChannelsPerFrame		= 2;
		dataFormat.mFramesPerPacket			= 1;
		dataFormat.mBitsPerChannel			= sizeof(SInt16) * 4 * dataFormat.mChannelsPerFrame; // 16-bit Signed Integer PCM
		dataFormat.mBytesPerFrame			= (dataFormat.mBitsPerChannel>>3) * dataFormat.mChannelsPerFrame;
		dataFormat.mBytesPerPacket			= dataFormat.mBytesPerFrame * dataFormat.mFramesPerPacket;
		
		if([inURL.scheme isEqualToString:@"ipod-library"] && ![OALAudioSupport sharedInstance].allowIpod){
			OAL_LOG_WARNING(@"source is iPod but iPod mixing is not allowed. Set your category to allow mixing.");
		}
		
		NSDictionary *options	= nil;//[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:AVURLAssetPreferPreciseDurationAndTimingKey];
		asset					= [[AVURLAsset alloc] initWithURL:inURL options:options];
		if(!asset){
			if(outError)
				*outError		= [NSError errorWithDomain:@"AudioQueuePlayer failed with AVURLAsset" code:-1 userInfo:nil];
			[self release];
			return nil;
		}
		
		//get duration
		CMTime assetDuration	= asset.duration;
		if(CMTIME_IS_VALID(assetDuration)){
			duration			= CMTimeGetSeconds(assetDuration);
		}else{
			OAL_LOG_ERROR(@"AVAsset duration not a valid CMTime");
		}
		
		if(outError)
			*outError			= nil;
		
		if(![self setupReader:&assetReader output:&assetReaderMixerOutput forAsset:asset error:outError]){
			[self close];
			[self release];
			return nil;
		}
		
		if(![self setupAudioQueue]){
			[self close];
			if(outError)
				*outError		= [NSError errorWithDomain:@"AudioQueuePlayer AudioQueue setup failed" code:-1 userInfo:nil];
			[self release];
			return nil;
		}

		if(![self setupDSP]){
			[self close];
			if(outError)
				*outError		= [NSError errorWithDomain:@"AudioQueuePlayer DSP setup failed" code:-1 userInfo:nil];
			[self release];
			return nil;
		}

		status			= OALPlayerStatusReadyToPlay;
		state			= OALPlayerStateStopped;
		
		//Set current time must happen after the state is set to non-closed
		self.currentTime		= inSeekTime;
		/*
		__block BOOL fetchedBuffers		= NO;
		
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, NULL), ^{
			fetchedBuffers		= [self prefetchBuffers];
		});
		
		if(!fetchedBuffers){
			[self close];
			if(outError)
				*outError		= [NSError errorWithDomain:@"AudioQueuePlayer AudioQueue setup failed" code:-1 userInfo:nil];
			[self release];
			return nil;
		}
		*/
		OAL_LOG_DEBUG(@"Asset duration: %.2f seek time: %.2f actual %.2f", CMTimeGetSeconds(asset.duration), inSeekTime, self.currentTime);
	}
	return self;
}

#pragma mark -
#pragma mark AVAssetReader

- (BOOL) setupReader:(AVAssetReader **)outReader output:(AVAssetReaderOutput **)outOutput forAsset:(AVAsset *)anAsset error:(NSError **)outError
{
	if(!anAsset || !outReader || !outOutput){
		return NO;
	}
#pragma mark AVAssetReader
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
	///////////////////////
	///// AssetReader Setup
	///////////////////////
	
	NSArray *tracks						= [anAsset tracksWithMediaType:AVMediaTypeAudio];
	
	if([tracks count] < 1){
		OAL_LOG_ERROR(@"AVAsset has no tracks");
		[pool drain];
		return NO;
	}
	
	// Create the AVAssetReader
	*outReader							= [[AVAssetReader alloc] initWithAsset:anAsset error:outError];
	
	if(!*outReader){
		NSLog(@"Error creating assetReader: %@",[*outError localizedDescription]);
		[*outReader release];
		*outReader = nil;
		*outOutput = nil;
		[pool drain];
		return NO;
	}
	
	OAL_LOG_DEBUG(@"ASBD:\n%@", [OALAudioSupport stringFromAudioStreamBasicDescription:&dataFormat]);
	
	// Create the options dictionary to initialize our AVAssetReaderOuput subclass with
	// Note: It doesn't like it when certain options are set
	// The Reader refuses to start reading if you try to specify nonInterleaved, Float, BigEndian, etc.
	// The following settings are working.
	// The alternative is to pass nil for the options which will give you the actual file data which you'd have to decode yourself.
	
	NSDictionary *optionsDictionary	=	[[NSDictionary alloc] initWithObjectsAndKeys:
											[NSNumber numberWithFloat:(float)dataFormat.mSampleRate],	AVSampleRateKey,
											[NSNumber numberWithInt:dataFormat.mFormatID],				AVFormatIDKey,
											[NSNumber numberWithBool:((dataFormat.mFormatFlags & kAudioFormatFlagIsBigEndian) == kAudioFormatFlagIsBigEndian)],				AVLinearPCMIsBigEndianKey,
											[NSNumber numberWithBool:((dataFormat.mFormatFlags & kAudioFormatFlagIsFloat) == kAudioFormatFlagIsFloat)],						AVLinearPCMIsFloatKey,
											[NSNumber numberWithBool:((dataFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == kAudioFormatFlagIsNonInterleaved)],	AVLinearPCMIsNonInterleaved,
											[NSNumber numberWithInt:dataFormat.mChannelsPerFrame],		AVNumberOfChannelsKey,
											[NSNumber numberWithInt:dataFormat.mBitsPerChannel],		AVLinearPCMBitDepthKey,
										nil];
	
	/*
	 AVAssetReaderTrackOutput does not currently support the AVAudioSettings.h keys AVSampleRateKey, AVNumberOfChannelsKey, or AVChannelLayoutKey.
	 */
	/*
	NSDictionary *optionsDictionary	=	[[NSDictionary alloc] initWithObjectsAndKeys:
//										 [NSNumber numberWithFloat:(float)dataFormat.mSampleRate],	AVSampleRateKey,
										 [NSNumber numberWithInt:dataFormat.mFormatID],				AVFormatIDKey,
										 [NSNumber numberWithBool:((dataFormat.mFormatFlags & kAudioFormatFlagIsBigEndian) == kAudioFormatFlagIsBigEndian)],				AVLinearPCMIsBigEndianKey,
										 [NSNumber numberWithBool:((dataFormat.mFormatFlags & kAudioFormatFlagIsFloat) == kAudioFormatFlagIsFloat)],						AVLinearPCMIsFloatKey,
										 [NSNumber numberWithBool:((dataFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == kAudioFormatFlagIsNonInterleaved)],	AVLinearPCMIsNonInterleaved,
//										 [NSNumber numberWithInt:dataFormat.mChannelsPerFrame],		AVNumberOfChannelsKey,
										 [NSNumber numberWithInt:dataFormat.mBitsPerChannel],		AVLinearPCMBitDepthKey,
										 nil];
	 */
	OAL_LOG_DEBUG(@"AVAssetReaderOutput Options:\n%@", [OALAudioSupport stringFromAVAudioSettingsDictionary:optionsDictionary]);
	
	// Create our AVAssetReaderOutput subclass with our options
	*outOutput						= [[AVAssetReaderAudioMixOutput alloc] initWithAudioTracks:tracks audioSettings:optionsDictionary];
//	*outOutput						= [[AVAssetReaderTrackOutput alloc] initWithTrack:[tracks objectAtIndex:0] outputSettings:optionsDictionary];
	
	[optionsDictionary release];
	
	if(!*outOutput){
		OAL_LOG_ERROR(@"Could not initialize the AVAssetReaderTrackOutput.");
		[*outReader release];
		*outReader = nil;
		[*outOutput release];
		*outOutput = nil;
		[pool drain];
		return NO;
	}
	
	if([*outReader canAddOutput:*outOutput]){
		[*outReader addOutput:*outOutput];
	}else{
		OAL_LOG_ERROR(@"Cannot add output to AVAssetReader");
		
		[*outReader release];
		*outReader = nil;
		[*outOutput release];
		*outOutput = nil;
		[pool drain];
		return NO;
	}
	
	// Should be unknown before startReading is called
	CheckReaderStatus(*outReader);
	[pool drain];
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
	if(audioError != noErr){
		REPORT_AUDIO_QUEUE_CALL(audioError, @"AudioQueueNewOutput");
		return NO;
	}
	
	audioError	= AudioQueueCreateTimeline(queue, &queueTimeline);
	if(audioError != noErr){
		REPORT_AUDIO_QUEUE_CALL(audioError, @"AudioQueueCreateTimeline");
		return NO;
	}
/*	
	UInt32 hardwarePolicy = (UInt32)kAudioQueueHardwareCodecPolicy_PreferHardware;
	audioError = AudioQueueSetProperty(queue, kAudioQueueProperty_HardwareCodecPolicy, (const void *)&hardwarePolicy, sizeof(UInt32));
	if(audioError != noErr){
		REPORT_AUDIO_QUEUE_CALL(audioError, @"AudioQueueSetProperty: HardwareCodecPolicy");
		return NO;
	}
*/	
	// for CBR data (Constant BitRate), we can simply fill each buffer with as many packets as will fit
	numPacketsToRead = OBJECTAL_CFG_AUDIO_QUEUE_BUFFER_SIZE_BYTES / dataFormat.mBytesPerPacket;
	
	// don't need packet descriptions for CBR data
	packetDescs = NULL;
	
	OAL_LOG_DEBUG(@"AudioQueue set to read %d packets", numPacketsToRead);
	
	// we want to know when the playing state changes so we can properly dispose of the audio queue when it's done
	audioError	= AudioQueueAddPropertyListener(queue, kAudioQueueProperty_IsRunning, audioQueuePropertyListenerCallback, self);
	if(audioError != noErr){
		REPORT_AUDIO_QUEUE_CALL(audioError, @"AudioQueueAddPropertyListener: IsRunning");
		return NO;
	}
	
	// allocate the play buffers
	for(int i = 0; i < OBJECTAL_CFG_AUDIO_QUEUE_NUM_BUFFERS; i++){
		audioError	= AudioQueueAllocateBuffer(queue, OBJECTAL_CFG_AUDIO_QUEUE_BUFFER_SIZE_BYTES, &buffers[i]);
		if(audioError != noErr){
			REPORT_AUDIO_QUEUE_CALL(audioError, @"AudioQueueAllocateBuffer: %d", i);
			return NO;
		}
	}
	
	return YES;
}

- (BOOL) setupDSP
{
	return YES;
}

- (BOOL) prefetchBuffers
{
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
	
	OAL_LOG_DEBUG(@"AudioQueue prefetching buffers");
	if(assetReader.status != AVAssetReaderStatusReading){
		if(![assetReader startReading]){
			OAL_LOG_ERROR(@"AVAssetReader failed to start reading: %@", [assetReader.error localizedDescription]);
			[pool drain];
			return NO;
		}
	}
	
	CompareReaderStatus(assetReader, AVAssetReaderStatusReading);
	
	for(int i = 0; i < OBJECTAL_CFG_AUDIO_QUEUE_NUM_BUFFERS; i++){
		int packetCount = [self readPacketsIntoBuffer:buffers[i]];
		
		// this might happen if the file was so short that it needed less buffers than we planned on using
		if(packetCount < 1){
			//If it is looping wrap back to beginning
			if(packetCount == 0 && loopCount < numberOfLoops){
				loopCount++;
				[self setCurrentTime:0];
				[self readPacketsIntoBuffer:buffers[i]];
			}else{
				break;
			}
		}
	}
	
	OSStatus audioError;
	
	UInt32 inNumberOfFramesToPrepare = 0;//numPacketsToRead;//0 means all
	UInt32 outNumberOfFramesPrepared;
	audioError = AudioQueuePrime(queue, inNumberOfFramesToPrepare, &outNumberOfFramesPrepared);	
	if(audioError != noErr){
		REPORT_AUDIO_QUEUE_CALL(audioError, @"play -> AudioQueuePrime");
		[pool drain];
		return NO;
	}else{
		OAL_LOG_DEBUG(@"AudioQueue inFramesToPrepare: %d outFramesPrepared: %d", inNumberOfFramesToPrepare, outNumberOfFramesPrepared);
	}
	
	OAL_LOG_DEBUG(@"Finished prefetching and priming buffers");
	[pool drain];
	return YES;
}

static void BufferCallback(void *inUserData, AudioQueueRef inAQ, AudioQueueBufferRef buffer)
{
	// redirect back to the class to handle it there instead, so we have direct access to the instance variables
	[(OALAudioPlayerAudioQueueAVAssetReader *)inUserData callbackForBuffer:buffer];
}

- (void)callbackForBuffer:(AudioQueueBufferRef)buffer
{
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
	// I guess it's possible for the callback to continue to be called since this is in another thread, so to be safe,
	// don't do anything else if the track is closed, and also don't bother reading anymore packets if the track ended
	if(suspended || state == OALPlayerStateClosed || trackEnded){
		OAL_LOG_WARNING(@"callbackForBuffer while not playing or trackEnded");
		[pool drain];
		return;
	}
	
	int readCount = [self readPacketsIntoBuffer:buffer];
	if(readCount < 0){
		OAL_LOG_ERROR(@"callbackForBuffer failed to read packets into buffer");
		[pool drain];
		return;
	}
	if(readCount == 0){
		if(loopCount < numberOfLoops){
			OAL_LOG_DEBUG(@"Reached end of buffer, but isLooping, so reset packetIndex and read more packets into buffer");
			// End Of File reached, so rewind and refill the buffer using the beginning of the file instead
			//TODO: hook into notification for looping
			loopCount++;
			self.currentTime = 0;
			[self readPacketsIntoBuffer:buffer];
			
			OAL_LOG_DEBUG(@"Looped playback %d/%d.", loopCount, numberOfLoops);
		}else{
			OAL_LOG_DEBUG(@"Reached end of buffer, not looping, so set trackEnded = YES and stop audio queue asynch so it finishes playing the remaining buffers");
			// set it to stop, but let it play to the end, where the property listener will pick up that it actually finished
			trackEnded			= YES;
			queueIsStopping		= YES;
			OSStatus audioError	= AudioQueueStop(queue, NO);
			REPORT_AUDIO_QUEUE_CALL(audioError, @"callbackForBuffer AudioQueueStop(queue, NO)");
		}
	}
	[pool drain];
}

- (int)readPacketsIntoBuffer:(AudioQueueBufferRef)buffer
{
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
	
	if(suspended){
		OAL_LOG_DEBUG(@"Not reading packets because player is suspended.");
		[pool drain];
		return -1;
	}
	
	if(state == OALPlayerStateClosed){
		OAL_LOG_ERROR(@"Not reading packets because player is closed.");
		[pool drain];
		return -1;
	}
	
	if(queueIsStopping){
		OAL_LOG_DEBUG(@"Not reading packets because audio queue is stopping.");
		[pool drain];
		return -1;
	}
	
	if(assetReaderSeeking != nil){
		OAL_LOG_DEBUG(@"Switching to seeked reader.");
		[assetReader cancelReading];
		[assetReader release];
		assetReader = nil;
		[assetReaderMixerOutput release];
		assetReaderMixerOutput = nil;
		
		assetReader = assetReaderSeeking;
		assetReaderMixerOutput = assetReaderMixerOutputSeeking;
		packetIndex	= packetIndexSeeking;
		
		assetReaderSeeking = nil;
		assetReaderMixerOutputSeeking = nil;
		packetIndexSeeking = 0;
	}
	
	if([assetReader status] == AVAssetReaderStatusCompleted){
		OAL_LOG_DEBUG(@"Stopped reading packets into buffer because reader status is completed.");
		[pool drain];
		return 0;
	}
	if([assetReader status] != AVAssetReaderStatusReading){
		OAL_LOG_ERROR(@"Attempted to read packets into buffer while asset reader is not reading.");
		[pool drain];
		return -1;
	}
	
	//OAL_LOG_DEBUG(@"Reading %d packets at %lld Time %f", numPacketsToRead, packetIndex, (float)(packetIndex/dataFormat.mSampleRate));
	
	UInt32		numBytes, numPackets;
	OSStatus	audioError = noErr;
	
#pragma mark AVAsset to audio Queue	
	CMSampleBufferRef myBuff;
	CMBlockBufferRef blockBufferOut;
	AudioBufferList buffList;
	CFAllocatorRef structAllocator = NULL;
	CFAllocatorRef memoryAllocator = NULL;
	
	myBuff = [assetReaderMixerOutput copyNextSampleBuffer];
	if(!myBuff){
		OAL_LOG_DEBUG(@"Stopped reading packets into buffer because reader returned a null buffer");
		[pool drain];
		CheckReaderStatus(assetReader);
		if([assetReader status] == AVAssetReaderStatusCompleted)
			return 0;
		else
			return -1;
	}
	
	UInt32 myFlags = kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment;
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
	//numPackets			= //CMSampleBufferGetNumSamples(myBuff)/CMSampleBufferGetDuration(myBuff);
	
	CFRelease(myBuff);
	
	if(audioError != noErr){
		OAL_LOG_ERROR(@"CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer %d", audioError);
		CFRelease(blockBufferOut);
		[pool drain];
		return -1;
	}
	
	size_t blockBufferOutLength	= CMBlockBufferGetDataLength(blockBufferOut);
	size_t dataLength			= MIN(buffer->mAudioDataBytesCapacity, blockBufferOutLength);
	
	if(dataLength < 1){
		OAL_LOG_ERROR(@"Stopped reading packets into buffer because read data length is 0. (cap: %d, len: %d)", buffer->mAudioDataBytesCapacity, blockBufferOutLength);
		CFRelease(blockBufferOut);
		[pool drain];
		return -1;
	}
	
	numBytes			= buffer->mAudioDataByteSize = dataLength;
	numPackets			= numBytes / dataFormat.mBytesPerPacket;
	audioError			= CMBlockBufferCopyDataBytes(
							blockBufferOut,
							0,
							dataLength,
							buffer->mAudioData
						   );
	CFRelease(blockBufferOut);
	
	if(audioError != noErr){
		OAL_LOG_ERROR(@"CMBlockBufferCopyDataBytes %d", audioError);
		[pool drain];
		return -1;
	}
	
	[self processSampleData:buffer numPackets:numPackets];
	
	audioError	= AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
	
	if(audioError != noErr){
		REPORT_AUDIO_QUEUE_CALL(audioError, @"AudioQueueEnqueueBuffer");
		[pool drain];
		return -1;
	}
	
	[pool drain];
	
	packetIndex += numPackets;
	
	return numPackets;
}

- (void) processSampleData:(AudioQueueBufferRef)buffer numPackets:(UInt32)numPackets
{
	
}

static void audioQueuePropertyListenerCallback(void *inUserData, AudioQueueRef queueObject, AudioQueuePropertyID propertyID)
{
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
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
	[pool drain];
}

- (void)playBackIsRunningStateChanged:(NSNumber *)isRunningN
{
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
	queueIsRunning			= [isRunningN boolValue];
	OAL_LOG_DEBUG(@"playBackIsRunningStateChanged: playing: %s and trackEnded: %s", queueIsRunning?"Y":"N", trackEnded?"Y":"N");
	if(queueIsRunning == NO){
		queueIsStopping = NO;
		//stopped
		if(trackEnded){
//			state = OALPlayerStateStopped;

//TODO: notifications
//			[self postTrackStoppedPlayingNotification:nil];
//			[self postTrackFinishedPlayingNotification:nil];
//			OAL_LOG_DEBUG(@"Closing player");
			// go ahead and close the track now
			//[self close];
			
			dispatch_async(dispatch_get_main_queue(), ^{
				[self stop];
				if([delegate respondsToSelector:@selector(audioPlayerDidFinishPlaying:successfully:)])
				{
					[delegate audioPlayerDidFinishPlaying:self successfully:YES];
				}
			});
		}
	}else{
		//started
		//systemTimeAtPlayStart	= SecondsSinceStart();
//TODO: notifications
//		[self postTrackStartedPlayingNotification:nil];
	}
	[pool drain];
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
	
	if(state == OALPlayerStatePlaying){
		OAL_LOG_DEBUG(@"Already playing");
		return YES;
	}
	
	OAL_LOG_DEBUG(@"Play: setting currentTime to lastCurrentTime: %.2f", lastCurrentTime);
	//This should guarantee a valid reader because it will create a new one if needed.
	self.currentTime = lastCurrentTime;
	
	if(assetReaderSeeking != nil){
		OAL_LOG_DEBUG(@"Switching to seeked reader.");
		[assetReader cancelReading];
		[assetReader release];
		assetReader = nil;
		[assetReaderMixerOutput release];
		assetReaderMixerOutput = nil;
		
		assetReader = assetReaderSeeking;
		assetReaderMixerOutput = assetReaderMixerOutputSeeking;
		packetIndex	= packetIndexSeeking;
		
		assetReaderSeeking = nil;
		assetReaderMixerOutputSeeking = nil;
		packetIndexSeeking = 0;
	}
	
	OAL_LOG_DEBUG(@"Play");
	CheckReaderStatus(assetReader);
	
	if([assetReader status] != AVAssetReaderStatusReading){
		OAL_LOG_DEBUG(@"AVAssetReader wasn't reading. Start reading.");
		if(![assetReader startReading]){
			OAL_LOG_ERROR(@"AVAssetReader cannot start reading. %@",[assetReader.error localizedDescription]);
			return NO;
		}
	}
	
	if(state != OALPlayerStatePaused){
		OAL_LOG_DEBUG(@"Prefetch audio queue buffers");
		if(![self prefetchBuffers]){
			OAL_LOG_ERROR(@"Failed to play because could not prefetch buffers.");
			return NO;
		}
	}
	
	loopCount = 0;
	state	= OALPlayerStatePlaying;

	OSStatus audioError;
	
	audioError = AudioQueueStart(queue, NULL);
	if(audioError != noErr){
		REPORT_AUDIO_QUEUE_CALL(audioError, @"play -> AudioQueueStart");
		return NO;
	}
	
	audioError = AudioQueueSetParameter(queue, kAudioQueueParam_Volume, volume);
	if(audioError != noErr){
		REPORT_AUDIO_QUEUE_CALL(audioError, @"play -> AudioQueueSetParameter Volume %f", volume);
	}
	/*
	audioError = AudioQueueSetParameter(queue, kAudioQueueParam_Pan, pan);
	if(audioError != noErr){
		REPORT_AUDIO_QUEUE_CALL(audioError, @"play -> AudioQueueSetParameter Pan %f", pan);
	}
	*/
	if(state == OALPlayerStatePaused){
// TODO: notifications
//		[self performSelectorOnMainThread:@selector(postTrackStartedPlayingNotification:) withObject:nil waitUntilDone:NO];
	}
	
	return YES;
}

/* play a sound some time in the future. time should be greater than deviceCurrentTime. */
- (BOOL)playAtTime:(NSTimeInterval) time
{
	//TODO
	return NO;
}

/* pauses playback, but remains ready to play. */
- (void)pause
{
	if(state != OALPlayerStatePlaying)
		return;
	
	lastCurrentTime = self.currentTime;
	
	state			= OALPlayerStatePaused;
	
	OSStatus audioError	= AudioQueuePause(queue);
	REPORT_AUDIO_QUEUE_CALL(audioError, @"AudioQueuePause");
	
// TODO: Look into this	
//	[self performSelectorOnMainThread:@selector(postTrackStoppedPlayingNotification:) withObject:nil waitUntilDone:NO];
}

/* stops playback. no longer ready to play. */
- (void)stop
{
	if(state == OALPlayerStateClosed)
		return;
	
	OAL_LOG_DEBUG(@"Stop");
	
	lastCurrentTime = self.currentTime;
	
	state			= OALPlayerStateStopped;
	
	//packetIndex	= 0;
	//seekTimeOffset = 0.0;
	//lastCurrentTime = 0.0;
	
	OSStatus audioError;
	audioError = AudioQueueSetParameter(queue, kAudioQueueParam_Volume, 0.0f);
	REPORT_AUDIO_QUEUE_CALL(audioError, @"AudioQueueSetParameter: Volume: 0");
	
	AudioQueueFlush(queue);
	if(queueIsRunning)
		queueIsStopping = YES;
	audioError = AudioQueueStop(queue, YES);
	REPORT_AUDIO_QUEUE_CALL(audioError, @"AudioQueueStop: Immediate: YES");
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
	pan = p;
	
	if(state == OALPlayerStateClosed)
		return;
	
//	OSStatus audioError	= AudioQueueSetParameter(queue, kAudioQueueParam_Pan, pan);
//	REPORT_AUDIO_QUEUE_CALL(audioError, @"AudioQueueSetParameter Pan %f", pan);
}

- (float) pan
{
	return pan;
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

- (void) setCurrentTime:(NSTimeInterval)position
{
	if(state == OALPlayerStateClosed){
		OAL_LOG_ERROR(@"Cannot set current time when player is closed.");
		return;
	}
	
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
	
	//position = floor(position);
	
	if(position < 0){
		position = 0;
	}else if(position > duration){
		position = duration-0.01;
	}
	
	OAL_LOG_DEBUG(@"Set Position: %.4f", position);
	
	//	packetIndex				= SecondsToSamples(position);
	CMTime startTime		= CMTimeMake(position*44100, 44100);
	CMTime playDuration		= kCMTimePositiveInfinity;
	CMTimeRange playRange	= CMTimeRangeMake(startTime, playDuration);
	
	if(assetReader.status == AVAssetReaderStatusUnknown){
		OAL_LOG_DEBUG(@"Reader status is unknown. Seeking directly");
		assetReader.timeRange = playRange;
		[assetReader startReading];
		position		= CMTimeGetSeconds(assetReader.timeRange.start);
		startTime		= CMTimeMake(position*44100, 44100);
	}else{
		OAL_LOG_DEBUG(@"Reader is not seekable. Using a new reader to seek.");
		
		if(assetReaderSeeking != nil){
			[assetReaderSeeking release];
			assetReaderSeeking = nil;
		}
		if(assetReaderMixerOutputSeeking != nil){
			[assetReaderMixerOutputSeeking release];
			assetReaderMixerOutputSeeking = nil;
		}
		
		NSError *error;
		if(![self setupReader:&assetReaderSeeking output:&assetReaderMixerOutputSeeking forAsset:asset error:&error]){
			NSLog(@"Failed to setup reader/output for seeking. %@", [error localizedDescription]);
			[pool drain];
			return;
		}
		assetReaderSeeking.timeRange = playRange;
		[assetReaderSeeking startReading];
		position		= CMTimeGetSeconds(assetReaderSeeking.timeRange.start);
		startTime		= CMTimeMake(position*44100, 44100);
	}
	
	packetIndexSeeking	= position*dataFormat.mSampleRate;
	
	AudioTimeStamp currentTime;
	if(queueIsRunning){
		
		Boolean outTimelineDiscontinuity;
		OSStatus audioError = AudioQueueGetCurrentTime(
														queue,
														queueTimeline,
														&currentTime,
														&outTimelineDiscontinuity
														);
		if(audioError != noErr){
			REPORT_AUDIO_QUEUE_CALL(audioError, @"AudioQueueGetCurrentTime");
			currentTime.mSampleTime = 0;
			OAL_LOG_DEBUG(@"Queue getCurrentTime ERROR. reporting queue time as ZERO");
		}
		
		//Intentionally NOT flushing buffers here to just drop them to hopefully make the timeline seemless to the next set of buffers after seeking
//		currentTime.mSampleTime = 0;
//		queueIsStopping = YES;
//		AudioQueueStop(queue, YES);
//		AudioQueueStart(queue, NULL);
	}else{
		OAL_LOG_DEBUG(@"Queue NOT running. reporting queue time as ZERO");
		currentTime.mSampleTime = 0;
	}
	
	lastCurrentTime = CMTimeGetSeconds(startTime);
	seekTimeOffset = lastCurrentTime - currentTime.mSampleTime/dataFormat.mSampleRate;
	OAL_LOG_DEBUG(@"SetCurrentTime: %.2f, SeekOffset: %.2f", lastCurrentTime, seekTimeOffset);
	[pool drain];
	return;
}

- (NSTimeInterval)currentTime
{
	if(state == OALPlayerStateClosed){
		//OAL_LOG_DEBUG(@"CurrentTime: %.2f (Player closed)", lastCurrentTime);
		return lastCurrentTime;
	}
	if(!queueIsRunning){
		//OAL_LOG_DEBUG(@"CurrentTime: %.2f (Queue not running)", lastCurrentTime);
		return lastCurrentTime;
	}
	
	AudioTimeStamp currentTime;
	Boolean outTimelineDiscontinuity;
	OSStatus audioError = AudioQueueGetCurrentTime(
													queue,
													queueTimeline,
													&currentTime,
													&outTimelineDiscontinuity
													);
	if(audioError != noErr){
		REPORT_AUDIO_QUEUE_CALL(audioError, @"AudioQueueGetCurrentTime");
		//OAL_LOG_DEBUG(@"CurrentTime: %.2f (Queue getCurrentTime error)", lastCurrentTime);
		return lastCurrentTime;
	}else{
		lastCurrentTime = seekTimeOffset + currentTime.mSampleTime / dataFormat.mSampleRate;
	}
	//OAL_LOG_DEBUG(@"CurrentTime: %.2f (Queue Time: %.2f, seekOffset: %.2f)", lastCurrentTime, (currentTime.mSampleTime / dataFormat.mSampleRate), seekTimeOffset);
	return lastCurrentTime;
}

- (NSTimeInterval) deviceCurrentTime
{
	//TODO
	[self doesNotRecognizeSelector:_cmd];
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
	UInt32 val	= (yn)?1U:0U;
	OSStatus err = AudioQueueSetProperty(queue, kAudioQueueProperty_EnableLevelMetering, &val, sizeof(UInt32));
	REPORT_AUDIO_QUEUE_CALL(err, @"AudioQueueSetProperty: EnableLevelMetering: %s", (yn)?"Y":"N");
}

- (BOOL) isMeteringEnabled
{
	UInt32 val;
	UInt32 size;
	OSStatus err = AudioQueueGetProperty(queue, kAudioQueueProperty_EnableLevelMetering, &val, &size);
	REPORT_AUDIO_QUEUE_CALL(err, @"AudioQueueGetProperty: EnableLevelMetering: %s", (val == 1)?"Y":"N");
	return (val == 1);
}

/* call to refresh meter values */
- (void)updateMeters
{
	//TODO
}

/* returns peak power in decibels for a given channel */
- (float)peakPowerForChannel:(NSUInteger)channelNumber
{
	//TODO
	return 0;
}

/* returns average power in decibels for a given channel */
- (float)averagePowerForChannel:(NSUInteger)channelNumber
{
	//TODO
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

@end
