//
//  OALAudioPlayerAudioUnitAVAssetReader.m
//  ObjectAL
//
//  Created by CJ Hanson on 02-NOV-2010
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

#import "OALAudioPlayerAudioUnitAVAssetReader.h"
#import "OALAudioSupport.h"
#import "ObjectALMacros.h"
#import "aurio_helper.h"
#include <unistd.h>

#define CheckReaderStatus(__READER__) OAL_LOG_DEBUG(@"AVAssetReader Status: %@", [OALAudioSupport stringFromAVAssetReaderStatus:[(__READER__) status]]);
#define CompareReaderStatus(__READER__, __STATUS__)  OAL_LOG_DEBUG(@"AVAssetReader Status: %@, Expected %@", [OALAudioSupport stringFromAVAssetReaderStatus:[(__READER__) status]], [OALAudioSupport stringFromAVAssetReaderStatus:(__STATUS__)]);

@interface OALAudioPlayerAudioUnitAVAssetReader (PrivateMethods)

static OSStatus	PerformThru(
							void						*inRefCon, 
							AudioUnitRenderActionFlags 	*ioActionFlags, 
							const AudioTimeStamp 		*inTimeStamp, 
							UInt32 						inBusNumber, 
							UInt32 						inNumberFrames, 
							AudioBufferList 			*ioData);

static OSStatus playbackCallback(void						*inRefCon, 
								 AudioUnitRenderActionFlags	*ioActionFlags, 
								 const AudioTimeStamp		*inTimeStamp, 
								 UInt32						inBusNumber, 
								 UInt32						inNumberFrames, 
								 AudioBufferList			*ioData);

- (BOOL)prefetchBuffers;
- (void)getCurrentTime:(AudioTimeStamp *)currentTime;

- (void)close;
@end

@implementation OALAudioPlayerAudioUnitAVAssetReader

@synthesize rioUnit;
@synthesize unitIsRunning;
@synthesize unitHasBeenCreated;
@synthesize mute;
@synthesize inputProc;

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
	
	OAL_LOG_DEBUG(@"Closing AudioUnit player.");
	
	backgroundloadshouldstopflag_ = YES;
	[readerOpQueue waitUntilAllOperationsAreFinished];
	[readerOpQueue release];
	readerOpQueue			= nil;
	backgroundloadshouldstopflag_ = NO;
	
	writepos_	= 0;
	readpos_	= 0;
	dataAvailable = 0;
	
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
	// mute = NO;
	
	OSStatus audioError;
	
	if(unitHasBeenCreated){
		audioError			= AudioOutputUnitStop(rioUnit);
		REPORT_AUDIO_UNIT_CALL(audioError, @"AudioOutputUnitStop");
		
		audioError			= AudioUnitUninitialize(rioUnit);
		REPORT_AUDIO_UNIT_CALL(audioError, @"AudioUnitUninitialize");
	}
	if(readbuffer_)
		free(readbuffer_);
	readbuffer_			= NULL;
	rioUnit				= NULL;
	unitIsRunning		= NO;
	unitHasBeenCreated	= NO;
	
	packetIndex			= 0;
	packetIndexSeeking	= 0;
	seekTimeOffset		= 0.0;
	lastCurrentTime		= 0.0;
	
	status				= OALPlayerStatusUnknown;
	
	OAL_LOG_DEBUG(@"audio unit player closed");
}

- (id) initWithContentsOfURL:(NSURL *)inURL seekTime:(NSTimeInterval)inSeekTime error:(NSError **)outError
{
	self = [super init];
	if(self){
		url						= [inURL retain];
		playerType				= OALAudioPlayerTypeAudioUnitAVAssetReader;
		state					= OALPlayerStateClosed;
		status					= OALPlayerStatusUnknown;
		loopCount				= 0;
		numberOfLoops			= 0;
		trackEnded				= NO;
		unitIsRunning			= NO;
		unitHasBeenCreated		= NO;
		mute					= NO;
		volume					= 1.0f;
		pan						= 0.5f;
		asset					= nil;
		assetReader				= nil;
		assetReaderSeeking		= nil;
		assetReaderMixerOutput	= nil;
		assetReaderMixerOutputSeeking = nil;
		readerOpQueue			= nil;
		backgroundloadflag_		= NO;
		backgroundloadshouldstopflag_ = NO;
		rioUnit					= NULL;
		readbuffer_				= NULL;
		readpos_				= 0;
		writepos_				= 0;
		dataAvailable			= 0;
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
				*outError		= [NSError errorWithDomain:@"AudioUnitPlayer failed with AVURLAsset" code:-1 userInfo:nil];
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
		
		if(![self setupAudioUnit]){
			[self close];
			if(outError)
				*outError		= [NSError errorWithDomain:@"AudioUnitPlayer setupAudioUnit failed" code:-1 userInfo:nil];
			[self release];
			return nil;
		}
		
		if(![self setupDSP]){
			[self close];
			if(outError)
				*outError		= [NSError errorWithDomain:@"AudioUnitPlayer DSP setup failed" code:-1 userInfo:nil];
			[self release];
			return nil;
		}
		
		status			= OALPlayerStatusReadyToPlay;
		state			= OALPlayerStateStopped;
		
		//Set current time must happen after the state is set to non-closed
		self.currentTime		= inSeekTime;
		
		OAL_LOG_DEBUG(@"Asset duration: %.2f seek time: %.2f actual %.2f", CMTimeGetSeconds(asset.duration), inSeekTime, self.currentTime);
	}
	return self;
}

#pragma mark -
#pragma mark AVAssetReader

- (BOOL) setupReader:(AVAssetReader **)outReader output:(AVAssetReaderAudioMixOutput **)outOutput forAsset:(AVAsset *)anAsset error:(NSError **)outError
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
	/*
	 //Match settings of configured data format
	 NSDictionary *optionsDictionary	=	[[NSDictionary alloc] initWithObjectsAndKeys:
										 [NSNumber numberWithFloat:(float)dataFormat.mSampleRate],	AVSampleRateKey,
										 [NSNumber numberWithInt:dataFormat.mFormatID],				AVFormatIDKey,
										 [NSNumber numberWithBool:((dataFormat.mFormatFlags & kAudioFormatFlagIsBigEndian) == kAudioFormatFlagIsBigEndian)],				AVLinearPCMIsBigEndianKey,
										 [NSNumber numberWithBool:((dataFormat.mFormatFlags & kAudioFormatFlagIsFloat) == kAudioFormatFlagIsFloat)],						AVLinearPCMIsFloatKey,
										 [NSNumber numberWithBool:((dataFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == kAudioFormatFlagIsNonInterleaved)],	AVLinearPCMIsNonInterleaved,
										 [NSNumber numberWithInt:dataFormat.mChannelsPerFrame],		AVNumberOfChannelsKey,
										 [NSNumber numberWithInt:dataFormat.mBitsPerChannel],		AVLinearPCMBitDepthKey,
										 nil];
	*/
	//Force 32bit float
	AudioChannelLayout *channelLayout = (AudioChannelLayout *)calloc(1, sizeof(AudioChannelLayout));
	channelLayout->mChannelLayoutTag = kAudioChannelLayoutTag_Stereo;
	NSData *channelLayoutData		= [NSData dataWithBytesNoCopy:channelLayout length:sizeof(AudioChannelLayout) freeWhenDone:YES];
	
	NSDictionary *optionsDictionary = [[NSDictionary alloc] initWithObjectsAndKeys:
										  [NSNumber numberWithFloat:44100.0f],	AVSampleRateKey,
										  [NSNumber numberWithInt:2],			AVNumberOfChannelsKey,
										  [NSNumber numberWithInt:32],			AVLinearPCMBitDepthKey,
										  [NSNumber numberWithInt:kAudioFormatLinearPCM], AVFormatIDKey,
										  [NSNumber numberWithBool:YES],		AVLinearPCMIsFloatKey,
										  [NSNumber numberWithBool:NO],			AVLinearPCMIsBigEndianKey,
										  [NSNumber numberWithBool:NO],			AVLinearPCMIsNonInterleaved,
										  channelLayoutData,					AVChannelLayoutKey,
									   nil];
	
	OAL_LOG_DEBUG(@"AVAssetReaderAudioMixOutput Options:\n%@", [OALAudioSupport stringFromAVAudioSettingsDictionary:optionsDictionary]);
	
	// Create our AVAssetReaderOutput subclass with our options
	*outOutput						= [[AVAssetReaderAudioMixOutput alloc] initWithAudioTracks:tracks audioSettings:optionsDictionary];
	
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
#pragma mark Audio Unit

- (BOOL) setupAudioUnit
{
	if(unitHasBeenCreated){
		OAL_LOG_WARNING(@"Audio Unit was already setup. Closing first.");
		[self close];
	}
	inputProc.inputProc			= playbackCallback;
	inputProc.inputProcRefCon	= self;
	
	UInt32 size;
	try {
		// Initialize and configure the audio session
		XThrowIfError(SetupRemoteIO(rioUnit, inputProc, dataFormat), "couldn't setup remote i/o unit");
		unitHasBeenCreated		= true;
		
		//enough for 2 seconds of stereo data
		buffersize_				= (int) (2 * dataFormat.mSampleRate * dataFormat.mChannelsPerFrame);
		readbuffer_				= (float *)calloc(buffersize_, sizeof(float));
		
		size = sizeof(maxFPS);
		XThrowIfError(AudioUnitGetProperty(rioUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFPS, &size), "couldn't get the remote I/O unit's max frames per slice");
		
		OAL_LOG_DEBUG(@"Max Frames per slice: %d", maxFPS);
		/*
		 
		fftBufferManager = new FFTBufferManager(maxFPS);
		l_fftData = new int32_t[maxFPS/2];
		
		oscilLine = (GLfloat*)malloc(drawBufferLen * 2 * sizeof(GLfloat));
		*/
		XThrowIfError(AudioOutputUnitStart(rioUnit), "couldn't start remote i/o unit");
		
		size = sizeof(dataFormat);
		XThrowIfError(AudioUnitGetProperty(rioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &dataFormat, &size), "couldn't get the remote I/O unit's output client format");
		
		unitIsRunning = 1;
	}
	catch (CAXException &e) {
		char buf[256];
		OAL_LOG_ERROR(@"Error: %s (%s)\n", e.mOperation, e.FormatError(buf));
		unitIsRunning = 0;
	}
	catch (...) {
		OAL_LOG_ERROR(@"Unknown Error");
		unitIsRunning = 0;
	}
	
	return unitIsRunning;
}

- (BOOL) setupDSP
{
	return YES;
}

- (BOOL) prefetchBuffers
{
	if(backgroundloadflag_ == YES)
	{
		OAL_LOG_WARNING(@"Attempted to prefetch buffers when they are already being fetched.");
		return YES;
	}
	
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
	
	OAL_LOG_DEBUG(@"AudioUnit prefetching buffers");
	if(assetReader.status != AVAssetReaderStatusReading){
		if(![assetReader startReading]){
			OAL_LOG_ERROR(@"AVAssetReader failed to start reading: %@", [assetReader.error localizedDescription]);
			[pool drain];
			return NO;
		}
	}
	
	CompareReaderStatus(assetReader, AVAssetReaderStatusReading);
	
	if(readerOpQueue != nil){
		backgroundloadshouldstopflag_ = YES;
		[readerOpQueue waitUntilAllOperationsAreFinished];
		[readerOpQueue release];
		readerOpQueue			= nil;
		backgroundloadshouldstopflag_ = NO;
	}
	
	readerOpQueue			= [[NSOperationQueue alloc] init];
	NSOperation *readOp		= [[NSInvocationOperation alloc] initWithTarget:self selector:@selector(readPacketsIntoBuffer) object:nil];
	[readerOpQueue addOperation:readOp];
	[readOp release];
	
	[pool drain];
	return YES;
}

/* Parameters on entry to this function are :-
 
 *inRefCon - used to store whatever you want, can use it to pass in a reference to an objectiveC class
 i do this below to get at the InMemoryAudioFile object, the line below :
 callbackStruct.inputProcRefCon = self;
 in the initialiseAudio method sets this to "self" (i.e. this instantiation of RemoteIOPlayer).
 This is a way to bridge between objectiveC and the straight C callback mechanism, another way
 would be to use an "evil" global variable by just specifying one in theis file and setting it
 to point to inMemoryAudiofile whenever it is set.
 
 *inTimeStamp - the sample time stamp, can use it to find out sample time (the sound card time), or the host time
 
 inBusnumber - the audio bus number, we are only using 1 so it is always 0 
 
 inNumberFrames - the number of frames we need to fill. In this example, because of the way audioformat is
 initialised below, a frame is a 32 bit number, comprised of two signed 16 bit samples.
 
 
 
 *ioData - holds information about the number of audio buffers we need to fill as well as the audio buffers themselves */
static OSStatus playbackCallback(void *inRefCon, 
								 AudioUnitRenderActionFlags *ioActionFlags, 
								 const AudioTimeStamp *inTimeStamp, 
								 UInt32 inBusNumber, 
								 UInt32 inNumberFrames, 
								 AudioBufferList *ioData)
{
	//get a copy of the objectiveC class "self" we need this to get the next sample to fill the buffer
	OALAudioPlayerAudioUnitAVAssetReader *THIS = (OALAudioPlayerAudioUnitAVAssetReader *)inRefCon;
	
	uint i; 
	if(THIS->state == OALPlayerStatePlaying && THIS->dataAvailable >= inNumberFrames && !THIS->mute && !THIS->suspended)
	{
		THIS->dataAvailable -= inNumberFrames;
		
		float *tempbuf = THIS->tempbuf;
		
		//loop through all the buffers that need to be filled
		for(i = 0 ; i < ioData->mNumberBuffers; i++){
			//get the buffer to be filled
			AudioBuffer buffer = ioData->mBuffers[i];
			
			short signed int *frameBuffer = (short signed int *)buffer.mData;
			
			//safety first
			inNumberFrames	= inNumberFrames<4000?inNumberFrames:4000; 
			int pos			= THIS->readpos_;
			int size		= THIS->buffersize_; 
			float *source	= THIS->readbuffer_; 
			
			float mult		= THIS->volume*32000.0f; //just alllow a little leeway for limiter errors 32767.0; 
			uint j;
			
			//loop through the buffer and fill the frames
			for(j = 0; j < 2*inNumberFrames; j++){
				tempbuf[j]	= source[pos];
				pos			= (pos+1)%size;
			}
			
			THIS->readpos_ = pos; 
			
			//converts to int
			for(uint j = 0; j < 2*inNumberFrames; j++)
				frameBuffer[j] = mult*(tempbuf[j]);
		}
	}
	else
	{
		SilenceData(ioData);
	}
    return noErr;
}

static OSStatus	PerformThru(
							void						*inRefCon, 
							AudioUnitRenderActionFlags 	*ioActionFlags, 
							const AudioTimeStamp 		*inTimeStamp, 
							UInt32 						inBusNumber, 
							UInt32 						inNumberFrames, 
							AudioBufferList 			*ioData)
{
	OALAudioPlayerAudioUnitAVAssetReader *THIS = (OALAudioPlayerAudioUnitAVAssetReader *)inRefCon;
	OSStatus err = AudioUnitRender(THIS->rioUnit, ioActionFlags, inTimeStamp, 1, inNumberFrames, ioData);

	REPORT_AUDIO_UNIT_CALL(err, @"AudioUnitRender");
	
	if (err) { return err; }
/*	
	// Remove DC component
	for(UInt32 i = 0; i < ioData->mNumberBuffers; ++i)
		THIS->dcFilter[i].InplaceFilter((SInt32*)(ioData->mBuffers[i].mData), inNumberFrames, 1);
	
	if (THIS->displayMode == aurioTouchDisplayModeOscilloscopeWaveform)
	{
		// The draw buffer is used to hold a copy of the most recent PCM data to be drawn on the oscilloscope
		if (drawBufferLen != drawBufferLen_alloced)
		{
			int drawBuffer_i;
			
			// Allocate our draw buffer if needed
			if (drawBufferLen_alloced == 0)
				for (drawBuffer_i=0; drawBuffer_i<kNumDrawBuffers; drawBuffer_i++)
					drawBuffers[drawBuffer_i] = NULL;
			
			// Fill the first element in the draw buffer with PCM data
			for (drawBuffer_i=0; drawBuffer_i<kNumDrawBuffers; drawBuffer_i++)
			{
				drawBuffers[drawBuffer_i] = (SInt8 *)realloc(drawBuffers[drawBuffer_i], drawBufferLen);
				bzero(drawBuffers[drawBuffer_i], drawBufferLen);
			}
			
			drawBufferLen_alloced = drawBufferLen;
		}
		
		int i;
		
		SInt8 *data_ptr = (SInt8 *)(ioData->mBuffers[0].mData);
		for (i=0; i<inNumberFrames; i++)
		{
			if ((i+drawBufferIdx) >= drawBufferLen)
			{
				cycleOscilloscopeLines();
				drawBufferIdx = -i;
			}
			drawBuffers[0][i + drawBufferIdx] = data_ptr[2];
			data_ptr += 4;
		}
		drawBufferIdx += inNumberFrames;
	}
	
	else if ((THIS->displayMode == aurioTouchDisplayModeSpectrum) || (THIS->displayMode == aurioTouchDisplayModeOscilloscopeFFT))
	{
		if (THIS->fftBufferManager == NULL) return noErr;
		
		if (THIS->fftBufferManager->NeedsNewAudioData())
		{
			THIS->fftBufferManager->GrabAudioData(ioData); 
		}
		
	}
 */
	if (THIS->mute == YES) { SilenceData(ioData); }	
	return err;
}

#pragma mark -
#pragma mark Read from AVAsset on bg thread to fill up buffers

- (void)readPacketsIntoBuffer
{
	backgroundloadflag_		= YES;
	while(backgroundloadshouldstopflag_ == NO)
	{
		NSAutoreleasePool *pool = [NSAutoreleasePool new];
		
		if(suspended){
			OAL_LOG_DEBUG(@"Not reading packets because player is suspended.");
			usleep(1000);
			[pool drain];
			continue;
		}
		
		if(state == OALPlayerStateClosed){
			OAL_LOG_ERROR(@"Not reading packets because player is closed.");
			backgroundloadflag_ = NO;
			[pool drain];
			return;
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
			//TODO need to handle loop/complete here too?
			backgroundloadflag_ = NO;
			[pool drain];
			return;
		}
		if([assetReader status] != AVAssetReaderStatusReading){
			OAL_LOG_ERROR(@"Attempted to read packets into buffer while asset reader is not reading.");
			backgroundloadflag_ = NO;
			[pool drain];
			return;
		}
		
		OSStatus audioError	= noErr;
		
#pragma mark AVAsset to audio buffer	
		CMSampleBufferRef myBuff;
		CMBlockBufferRef blockBufferOut;
		AudioBufferList buffList;
		CFAllocatorRef structAllocator = NULL;
		CFAllocatorRef memoryAllocator = NULL;
		
		
		//test where readpos_ is; while within 2 seconds (half of buffer) must continue to fill up
		int diff = readpos_<=writepos_?(writepos_- readpos_):(writepos_+buffersize_ - readpos_); 
		
		if((diff < (buffersize_/2)) && (backgroundloadshouldstopflag_ == NO))
		{
			OAL_LOG_DEBUG(@"Reading at %d", readpos_);
			
			myBuff = [assetReaderMixerOutput copyNextSampleBuffer];
			if(!myBuff)
			{
				OAL_LOG_DEBUG(@"Stopped reading packets into buffer because reader returned a null buffer");
				//TODO Looping and end of track handling (Because I will arrive here before the track plays to this point how do I mark this position so it can trigger an end of track notice from the playback callback?
				backgroundloadshouldstopflag_ = YES;
			}
			else
			{
				if(!CMSampleBufferDataIsReady(myBuff)){
					OAL_LOG_ERROR(@"AVAssetReaderMixerOutput returned a sample buffer with data that is not ready.");
					CFRelease(myBuff);
					backgroundloadflag_ = NO;
					[pool drain];
					return;
				}
				
				CMItemCount countsamp= CMSampleBufferGetNumSamples(myBuff); 	
				
				//CMTime timestamp = CMSampleBufferGetPresentationTimeStamp(myBuff); 
				
				UInt32 frameCount = countsamp;
				
				UInt32 myFlags = 0;
				size_t sizeNeeded;
				audioError = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
																					 myBuff,
																					 &sizeNeeded,
																					 &buffList,
																					 sizeof(buffList),
																					 structAllocator,
																					 memoryAllocator,
																					 myFlags,
																					 &blockBufferOut);
				
				
				Float32 *buffer = (Float32 *)buffList.mBuffers[0].mData; 
				
				//int bytesize = audioBufferList.mBuffers[0].mNumberChannels;
				//int numchannels = audioBufferList.mBuffers[0].mDataByteSize;
				//int numbuffers = audioBufferList.mNumberBuffers; 
				
				for(uint j=0; j<2*frameCount; ++j)
				{	
					readbuffer_[writepos_]	= buffer[j];	
					writepos_				= (writepos_ + 1)%buffersize_;
				}
				
				CFRelease(myBuff);
				CFRelease(blockBufferOut);
				
				dataAvailable += frameCount;
				
				// If no frames were returned, conversion is finished
				if(0 == frameCount)
				{
					backgroundloadshouldstopflag_ = YES;
				}
			}
		}
		
		[pool drain];
		usleep(100); //1000 = 1 msec
		
		/*
		packetIndex += numPackets;
		
		// this might happen if the file was so short that it needed less buffers than we planned on using
		if(packetCount < 1){
			//If it is looping wrap back to beginning
			if(packetCount == 0 && loopCount < numberOfLoops){
				loopCount++;
				[self setCurrentTime:0];
				[self readPacketsIntoBuffer];
			}
		}
		 */
	}
	
	backgroundloadshouldstopflag_ = NO;
	backgroundloadflag_ = NO;
}

- (void) processSampleDataForNumPackets:(UInt32)numPackets
{
	
}

//TODO Detect loops and end of playback.

#pragma mark -
#pragma mark Interruption/Suspension

- (void) setSuspended:(bool) value
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(suspended != value)
		{
			suspended = value;
			if(suspended)
			{
				if(unitHasBeenCreated && unitIsRunning)
				{
					AudioOutputUnitStop(rioUnit);
					//unitIsRunning = NO;
				}
			}
			else
			{
				if(unitHasBeenCreated && unitIsRunning)
				{
					AudioOutputUnitStart(rioUnit);
					//unitIsRunning = YES;
				}
			}
		}
	}
}

#pragma mark -
#pragma mark Custom implementation of abstract super class

/* sound is played asynchronously. */
- (BOOL)play
{
	if(state == OALPlayerStateClosed){
		OAL_LOG_WARNING(@"Attempted to play a closed AudioUnitPlayer.");
		return NO;
	}
	
	if(state == OALPlayerStatePlaying){
		OAL_LOG_DEBUG(@"Already playing");
		return YES;
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
	
	OAL_LOG_DEBUG(@"Play");
	CheckReaderStatus(assetReader);
	
	if([assetReader status] != AVAssetReaderStatusReading){
		OAL_LOG_DEBUG(@"AVAssetReader wasn't reading. Start reading.");
		if(![assetReader startReading]){
			OAL_LOG_ERROR(@"AVAssetReader cannot start reading. %@",[assetReader.error localizedDescription]);
			return NO;
		}
		
		OAL_LOG_DEBUG(@"Prefetch audio buffers");
		if(![self prefetchBuffers]){
			OAL_LOG_ERROR(@"Failed to play because could not prefetch buffers.");
			return NO;
		}
		
	}
	
	loopCount	= 0;
	state		= OALPlayerStatePlaying;
	
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
}

/* stops playback. no longer ready to play. */
- (void)stop
{
	if(state == OALPlayerStateClosed)
		return;
	
	state			= OALPlayerStateStopped;
	
	packetIndex	= 0;
	seekTimeOffset = 0.0;
	lastCurrentTime = 0.0;
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
	}
	
	packetIndexSeeking	= position*dataFormat.mSampleRate;
	
	lastCurrentTime = position;
//	seekTimeOffset = lastCurrentTime - currentTime.mSampleTime/dataFormat.mSampleRate;
	
	//TODO fix set current time
	
	[pool drain];
	return;
}

- (NSTimeInterval)currentTime
{
	if(state == OALPlayerStateClosed)
		return 0;
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
	//TODO metering
}

- (BOOL) isMeteringEnabled
{
	//TODO
	return NO;
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
