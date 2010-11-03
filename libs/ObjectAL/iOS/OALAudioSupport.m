//
//  OALAudioSupport.m
//  ObjectAL
//
//  Created by Karl Stenerud on 19/12/09.
//
// Copyright 2009 Karl Stenerud
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

#import "OALAudioSupport.h"
#import "ObjectALMacros.h"
#import <AudioToolbox/AudioToolbox.h>
#import "OALAudioTracks.h"
#import "OpenALManager.h"

NSString *const OALAudioSessionInterruptBeginNotification	= @"OALAudioSessionInterruptBeginNotification";
NSString *const OALAudioSessionInterruptEndNotification		= @"OALAudioSessionInterruptEndNotification";


#define kMaxSessionActivationRetries 40

#pragma mark Asynchronous Operations

/**
 * (INTERNAL USE) NSOperation for loading audio files asynchronously.
 */
@interface OAL_AsyncALBufferLoadOperation: NSOperation
{
	/** The URL of the sound file to play */
	NSURL* url;
	/** The target to inform when the operation completes */
	id target;
	/** The selector to call when the operation completes */
	SEL selector;
}

/** (INTERNAL USE) Create a new Asynchronous Operation.
 *
 * @param url the URL containing the sound file.
 * @param target the target to inform when the operation completes.
 * @param selector the selector to call when the operation completes.
 */ 
+ (id) operationWithUrl:(NSURL*) url target:(id) target selector:(SEL) selector;

/** (INTERNAL USE) Initialize an Asynchronous Operation.
 *
 * @param url the URL containing the sound file.
 * @param target the target to inform when the operation completes.
 * @param selector the selector to call when the operation completes.
 */ 
- (id) initWithUrl:(NSURL*) url target:(id) target selector:(SEL) selector;

@end

@implementation OAL_AsyncALBufferLoadOperation

+ (id) operationWithUrl:(NSURL*) url target:(id) target selector:(SEL) selector
{
	return [[[self alloc] initWithUrl:url target:target selector:selector] autorelease];
}

- (id) initWithUrl:(NSURL*) urlIn target:(id) targetIn selector:(SEL) selectorIn
{
	if(nil != (self = [super init]))
	{
		url = [urlIn retain];
		target = targetIn;
		selector = selectorIn;
	}
	return self;
}

- (void) dealloc
{
	[url release];
	
	[super dealloc];
}

- (void)main
{
	ALBuffer* buffer = [[OALAudioSupport sharedInstance] bufferFromUrl:url];
	[target performSelectorOnMainThread:selector withObject:buffer waitUntilDone:NO];
}

@end



#pragma mark -
#pragma mark Private Methods

/**
 * (INTERNAL USE) Private methods for OALAudioSupport. 
 */
@interface OALAudioSupport (Private)

/** (INTERNAL USE) Used by the interrupt handler to suspend audio
 * (if interrupts are enabled).
 */
@property(readwrite,assign) bool suspended;

/** (INTERNAL USE) Get an AudioSession property.
 *
 * @param property The property to get.
 * @return The property's value.
 */
- (UInt32) getIntProperty:(AudioSessionPropertyID) property;

/** (INTERNAL USE) Get an AudioSession property.
 *
 * @param property The property to get.
 * @return The property's value.
 */
- (Float32) getFloatProperty:(AudioSessionPropertyID) property;

/** (INTERNAL USE) Get an AudioSession property.
 *
 * @param property The property to get.
 * @return The property's value.
 */
- (NSString*) getStringProperty:(AudioSessionPropertyID) property;

/** (INTERNAL USE) Set an AudioSession property.
 *
 * @param property The property to set.
 * @param value The value to set this property to.
 */
- (void) setIntProperty:(AudioSessionPropertyID) property value:(UInt32) value;

/** (INTERNAL USE) Update AudioSession based on the allowIpod and honorSilentSwitch values.
 */
- (void) updateAudioMode;

/** (INTERNAL USE) Called when an interrupt begins.
 */
- (void) onInterruptBegin;

/** (INTERNAL USE) Called when an interrupt ends.
 */
- (void) onInterruptEnd;

/** (INTERNAL USE) System callback for interrupts.
 */
static void interruptListenerCallback(void* inUserData, UInt32 interruptionState);

@end

#pragma mark -
#pragma mark OALAudioSupport

@implementation OALAudioSupport

#pragma mark Object Management

SYNTHESIZE_SINGLETON_FOR_CLASS(OALAudioSupport);

- (id) init
{
	if(nil != (self = [super init]))
	{
		operationQueue = [[NSOperationQueue alloc] init];
		REPORT_AUDIOSESSION_CALL(AudioSessionInitialize(NULL, NULL, interruptListenerCallback, self), @"Failed to initialize audio session");

		handleInterruptions = YES;
		audioSessionDelegate = nil;
		allowIpod = YES;
		ipodDucking = NO;
		useHardwareIfAvailable = YES;
		honorSilentSwitch = YES;
		self.audioSessionActive = YES;
	}
	return self;
}

- (void) dealloc
{
	self.audioSessionActive = NO;
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[operationQueue release];
	[super dealloc];
}


#pragma mark Properties

- (UInt32) overrideAudioSessionCategory
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return overrideAudioSessionCategory;
	}
}

- (void) setOverrideAudioSessionCategory:(UInt32) value
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		overrideAudioSessionCategory = value;
		[self updateAudioMode];
	}	
}

- (bool) allowIpod
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return allowIpod;
	}
}

- (void) setAllowIpod:(bool) value
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		allowIpod = value;
		[self updateAudioMode];
	}
}

- (bool) ipodDucking
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return ipodDucking;
	}
}

- (void) setIpodDucking:(bool) value
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		ipodDucking = value;
		[self updateAudioMode];
	}
}

- (bool) useHardwareIfAvailable
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return useHardwareIfAvailable;
	}
}

- (void) setUseHardwareIfAvailable:(bool) value
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		useHardwareIfAvailable = value;
		[self updateAudioMode];
	}
}

@synthesize handleInterruptions;
@synthesize audioSessionDelegate;

- (bool) honorSilentSwitch
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return honorSilentSwitch;
	}
}

- (void) setHonorSilentSwitch:(bool) value
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		honorSilentSwitch = value;
		[self updateAudioMode];
	}
}

- (bool) ipodPlaying
{
	return 0 != [self getIntProperty:kAudioSessionProperty_OtherAudioIsPlaying];
}

- (NSString*) audioRoute
{
#if !TARGET_IPHONE_SIMULATOR
	return [self getStringProperty:kAudioSessionProperty_AudioRoute];
#else /* !TARGET_IPHONE_SIMULATOR */
	return nil;
#endif /* !TARGET_IPHONE_SIMULATOR */
}

- (float) hardwareVolume
{
	return [self getFloatProperty:kAudioSessionProperty_CurrentHardwareOutputVolume];
}

- (bool) hardwareMuted
{
	return [[self audioRoute] isEqualToString:@""];
}


#pragma mark Buffers

- (ALBuffer*) bufferFromFile:(NSString*) filePath
{
	return [self bufferFromUrl:[OALAudioSupport urlForPath:filePath]];
}

- (ALBuffer*) bufferFromUrl:(NSURL*) url
{
	if(nil == url)
	{
		OAL_LOG_ERROR(@"Cannot open NULL file / url");
		return nil;
	}
	
	// Holds any errors that occur.
	OSStatus error;
	
	// Handle to the file we'll be reading from.
	ExtAudioFileRef fileHandle = nil;
	
	// This will hold the data we'll be passing to the OpenAL buffer.
	void* streamData = nil;
	
	// This is the buffer object we'll be returning to the caller.
	ALBuffer* alBuffer = nil;
	
	// Local variables that will be used later on.
	// They need to be pre-declared so that the compiler doesn't throw a hissy fit
	// over the goto statements if you compile as Objective-C++.
	SInt64 numFrames;
	UInt32 numFramesSize = sizeof(numFrames);
	
	AudioStreamBasicDescription audioStreamDescription;
	UInt32 descriptionSize = sizeof(audioStreamDescription);
	
	UInt32 streamSizeInBytes;
	AudioBufferList bufferList;
	UInt32 numFramesToRead;
	ALenum audioFormat;
	
	
	// Open the file
	if(noErr != (error = ExtAudioFileOpenURL((CFURLRef)url, &fileHandle)))
	{
		REPORT_EXTAUDIO_CALL(error, @"Could not open url %@", url);
		goto done;
	}
	
	// Find out how many frames there are
	if(noErr != (error = ExtAudioFileGetProperty(fileHandle,
												 kExtAudioFileProperty_FileLengthFrames,
												 &numFramesSize,
												 &numFrames)))
	{
		REPORT_EXTAUDIO_CALL(error, @"Could not get frame count for url %@", url);
		goto done;
	}
	
	// Get the audio format
	if(noErr != (error = ExtAudioFileGetProperty(fileHandle,
												 kExtAudioFileProperty_FileDataFormat,
												 &descriptionSize,
												 &audioStreamDescription)))
	{
		REPORT_EXTAUDIO_CALL(error, @"Could not get audio format for url %@", url);
		goto done;
	}
	
	// Specify the new audio format (anything not changed remains the same)
	audioStreamDescription.mFormatID = kAudioFormatLinearPCM;
	audioStreamDescription.mFormatFlags = kAudioFormatFlagsNativeEndian |
	kAudioFormatFlagIsSignedInteger |
	kAudioFormatFlagIsPacked;
	audioStreamDescription.mBitsPerChannel = 16;
	if(audioStreamDescription.mChannelsPerFrame > 2)
	{
		// Don't allow more than 2 channels (stereo)
		OAL_LOG_WARNING(@"Audio stream for url %@ contains %d channels. Capping at 2.", url, audioStreamDescription.mChannelsPerFrame);
		audioStreamDescription.mChannelsPerFrame = 2;
	}
	audioStreamDescription.mBytesPerFrame = audioStreamDescription.mChannelsPerFrame * audioStreamDescription.mBitsPerChannel / 8;
	audioStreamDescription.mFramesPerPacket = 1;
	audioStreamDescription.mBytesPerPacket = audioStreamDescription.mBytesPerFrame * audioStreamDescription.mFramesPerPacket;
	
	// Set the new audio format
	if(noErr != (error = ExtAudioFileSetProperty(fileHandle,
												 kExtAudioFileProperty_ClientDataFormat,
												 descriptionSize,
												 &audioStreamDescription)))
	{
		REPORT_EXTAUDIO_CALL(error, @"Could not set new audio format for url %@", url);
		goto done;
	}
	
	// Allocate some memory to hold the data
	streamSizeInBytes = audioStreamDescription.mBytesPerFrame * (SInt32)numFrames;
	streamData = malloc(streamSizeInBytes);
	if(nil == streamData)
	{
		OAL_LOG_ERROR(@"Could not allocate %d bytes for url %@", streamSizeInBytes, url);
		goto done;
	}
	
	// Read the data from the file to our buffer, in the new format
	bufferList.mNumberBuffers = 1;
	bufferList.mBuffers[0].mNumberChannels = audioStreamDescription.mChannelsPerFrame;
	bufferList.mBuffers[0].mDataByteSize = streamSizeInBytes;
	bufferList.mBuffers[0].mData = streamData;
	
	numFramesToRead = (UInt32)numFrames;
	if(noErr != (error = ExtAudioFileRead(fileHandle, &numFramesToRead, &bufferList)))
	{
		REPORT_EXTAUDIO_CALL(error, @"Could not read audio data from url %@", url);
		goto done;
	}
	
	if(1 == audioStreamDescription.mChannelsPerFrame)
	{
		if(8 == audioStreamDescription.mBitsPerChannel)
		{
			audioFormat = AL_FORMAT_MONO8;
		}
		else
		{
			audioFormat = AL_FORMAT_MONO16;
		}
	}
	else
	{
		if(8 == audioStreamDescription.mBitsPerChannel)
		{
			audioFormat = AL_FORMAT_STEREO8;
		}
		else
		{
			audioFormat = AL_FORMAT_STEREO16;
		}
	}
	
	alBuffer = [ALBuffer bufferWithName:[url absoluteString]
								   data:streamData
								   size:streamSizeInBytes
								 format:audioFormat
							  frequency:(ALsizei)audioStreamDescription.mSampleRate];
	// ALBuffer is maintaining this memory now.  Make sure we don't free() it.
	streamData = nil;
	
done:
	if(nil != fileHandle)
	{
		REPORT_EXTAUDIO_CALL(ExtAudioFileDispose(fileHandle), @"Error closing audio file");
	}
	if(nil != streamData)
	{
		free(streamData);
	}
	return alBuffer;
}

- (NSString*) bufferAsyncFromFile:(NSString*) filePath target:(id) target selector:(SEL) selector
{
	return [self bufferAsyncFromUrl:[OALAudioSupport urlForPath:filePath] target:target selector:selector];
}

- (NSString*) bufferAsyncFromUrl:(NSURL*) url target:(id) target selector:(SEL) selector
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		[operationQueue addOperation:[OAL_AsyncALBufferLoadOperation operationWithUrl:url target:target selector:selector]];
	}
	return [url absoluteString];
}


#pragma mark Audio Error Utility

NSString *GetNSStringFromAudioSessionError(OSStatus errorCode)
{
	switch (errorCode) {
		case kAudioSessionNoError:
			return nil;
			break;
		case kAudioSessionNotInitialized:
			return @"Session not initialized";
			break;
		case kAudioSessionAlreadyInitialized:
			return @"Session already initialized";
			break;
		case kAudioSessionInitializationError:
			return @"Sesion initialization error";
			break;
		case kAudioSessionUnsupportedPropertyError:
			return @"Unsupported session property";
			break;
		case kAudioSessionBadPropertySizeError:
			return @"Bad session property size";
			break;
		case kAudioSessionNotActiveError:
			return @"Session is not active";
			break;
#if 0 // Documented but not implemented on iOS
		case kAudioServicesNoHardwareError:
			return @"Hardware not available for session";
			break;
#endif
#ifdef __IPHONE_3_1
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_3_1
		case kAudioSessionNoCategorySet:
			return @"No session category set";
			break;
		case kAudioSessionIncompatibleCategory:
			return @"Incompatible session category";
			break;
#endif /* __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_3_1 */
#endif /* __IPHONE_3_1 */
		default:
			return [NSString stringWithFormat:@"Unknown error %d", errorCode];
			break;
	}
}

+ (void) logAudioSessionError:(OSStatus)errorCode function:(const char*) function description:(NSString*) description, ...
{
	if(noErr != errorCode)
	{
		NSString* errorString = GetNSStringFromAudioSessionError(errorCode);
		if(nil != errorString)
		{
			va_list args;
			va_start(args, description);
			description = [[[NSString alloc] initWithFormat:description arguments:args] autorelease];
			va_end(args);
			OAL_LOG_ERROR_CONTEXT(function, @"%@ (error code 0x%08x: %@)", description, errorCode, errorString);
		}
	}
}

NSString *GetNSStringFromExtAudioFileError(OSStatus errorCode)
{
	switch (errorCode) {
		case noErr:
			return nil;
			break;
#ifdef __IPHONE_3_1
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_3_1
		case kExtAudioFileError_CodecUnavailableInputConsumed:
			return @"Write function interrupted - last buffer written";
			break;
		case kExtAudioFileError_CodecUnavailableInputNotConsumed:
			return @"Write function interrupted - last buffer not written";
			break;
#endif /* __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_3_1 */
#endif /* __IPHONE_3_1 */
		case kExtAudioFileError_InvalidProperty:
			return @"Invalid property";
			break;
		case kExtAudioFileError_InvalidPropertySize:
			return @"Invalid property size";
			break;
		case kExtAudioFileError_NonPCMClientFormat:
			return @"Non-PCM client format";
			break;
		case kExtAudioFileError_InvalidChannelMap:
			return @"Wrong number of channels for format";
			break;
		case kExtAudioFileError_InvalidOperationOrder:
			return @"Invalid operation order";
			break;
		case kExtAudioFileError_InvalidDataFormat:
			return @"Invalid data format";
			break;
		case kExtAudioFileError_MaxPacketSizeUnknown:
			return @"Max packet size unknown";
			break;
		case kExtAudioFileError_InvalidSeek:
			return @"Seek offset out of bounds";
			break;
		case kExtAudioFileError_AsyncWriteTooLarge:
			return @"Async write too large";
			break;
		case kExtAudioFileError_AsyncWriteBufferOverflow:
			return @"Async write could not be completed in time";
			break;
		default:
			return [NSString stringWithFormat:@"Unknown error %d", errorCode];
			break;
	}
}

+ (void) logExtAudioError:(OSStatus)errorCode function:(const char*) function description:(NSString*) description, ...
{
	if(noErr != errorCode)
	{
		NSString* errorString = GetNSStringFromExtAudioFileError(errorCode);
		if(nil != errorString)
		{
			va_list args;
			va_start(args, description);
			description = [[[NSString alloc] initWithFormat:description arguments:args] autorelease];
			va_end(args);
			OAL_LOG_ERROR_CONTEXT(function, @"%@ (error code 0x%08x: %@)", description, errorCode, errorString);
		}
	}
}

NSString *GetNSStringFromAudioQueueError(OSStatus errorCode)
{
	switch (errorCode) {
		case noErr:
			return nil;
			break;
		case kAudioQueueErr_InvalidBuffer:
			return @"The specified audio queue buffer does not belong to the specified audio queue.";
			break;
		case kAudioQueueErr_BufferEmpty:
			return @"The audio queue buffer is empty (that is, the mAudioDataByteSize field = 0).";
			break;
		case kAudioQueueErr_DisposalPending:
			return @"The function cannot act on the audio queue because it is being asynchronously disposed of.";
			break;
		case kAudioQueueErr_InvalidProperty:
			return @"The specified property ID is invalid.";
			break;
		case kAudioQueueErr_InvalidPropertySize:
			return @"The size of the specified property is invalid.";
			break;
		case kAudioQueueErr_InvalidParameter:
			return @"The specified parameter ID is invalid.";
			break;
		case kAudioQueueErr_CannotStart:
			return @"The audio queue has encountered a problem and cannot start.";
			break;
		case kAudioQueueErr_InvalidDevice:
			return @"The specified audio hardware device could not be located.";
			break;
		case kAudioQueueErr_BufferInQueue:
			return @"The audio queue buffer cannot be disposed of when it is enqueued.";
			break;
		case kAudioQueueErr_InvalidRunState:
			return @"The queue is running but the function can only operate on the queue when it is stopped, or vice versa.";
			break;
		case kAudioQueueErr_InvalidQueueType:
			return @"The queue is an input queue but the function can only operate on an output queue, or vice versa.";
			break;
		case kAudioQueueErr_Permissions:
			return @"You do not have the required permissions to call the function.";
			break;
		case kAudioQueueErr_InvalidPropertyValue:
			return @"The property value used is not valid.";
			break;
		case kAudioQueueErr_PrimeTimedOut:
			return @"During a call to the AudioQueuePrime function, the audio queue's audio converter failed to convert the requested number of sample frames.";
			break;
		case kAudioQueueErr_CodecNotFound:
			return @"The requested codec was not found.";
			break;
		case kAudioQueueErr_InvalidCodecAccess:
			return @"The codec could not be accessed.";
			break;
		case kAudioQueueErr_QueueInvalidated:
			return @"In iOS, the audio server has exited, causing the audio queue to become invalid.";
			break;
		case kAudioQueueErr_EnqueueDuringReset:
			return @"During a call to the AudioQueueReset, AudioQueueStop, or AudioQueueDispose functions, the system does not allow you to enqueue buffers.";
			break;
#ifdef __IPHONE_3_1
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_3_1
		case kAudioQueueErr_InvalidOfflineMode:
			return @"The operation requires the audio queue to be in offline mode but it isn’t, or vice versa.\nTo use offline mode or to return to normal mode, use the AudioQueueSetOfflineRenderFormat function.";
			break;
		case kAudioFormatUnsupportedDataFormatError:
			return @"The playback data format is unsupported (declared in AudioFormat.h).";
			break;
#endif /* __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_3_1 */
#endif /* __IPHONE_3_1 */
		default:
			return [NSString stringWithFormat:@"Unknown error %d", errorCode];
			break;
	}
}

+ (void) logAudioQueueError:(OSStatus)errorCode function:(const char*) function description:(NSString*) description, ...
{
	if(noErr != errorCode)
	{
		NSString* errorString = GetNSStringFromAudioQueueError(errorCode);
		if(nil != errorString)
		{
			va_list args;
			va_start(args, description);
			description = [[[NSString alloc] initWithFormat:description arguments:args] autorelease];
			va_end(args);
			OAL_LOG_ERROR_CONTEXT(function, @"%@ (error code 0x%08x: %@)", description, errorCode, errorString);
		}
	}
}

#pragma mark AudioStreamBasicDescription

NSString *GetNSStringFrom4CharCode(unsigned long code)
{
	char c[5];
	c[0]	= code >> 24;
	c[1]	= (code >> 16) & 0xff;
	c[2]	= (code >> 8) & 0xff;
	c[3]	= code & 0xff;
	c[4]	= '\0';
	
	return [NSString stringWithCString:c encoding:NSASCIIStringEncoding];
}

+ (NSString *) stringFromAudioStreamBasicDescription:(const AudioStreamBasicDescription *)absd
{
	if(!absd)
		return nil;
	
	return [NSString stringWithFormat:@"\n"
			"  Sample Rate:        %f\n"
			"  Format ID:          %@\n"
			"  Format Flags:       %08X, BigEndian: %s, IsFloat: %s, IsNonInterleaved: %s\n"
			"  Bytes per Packet:   %d\n"
			"  Frames per Packet:  %d\n"
			"  Bytes per Frame:    %d\n"
			"  Channels per Frame: %d\n"
			"  Bits per Channel:   %d",
			absd->mSampleRate,
			GetNSStringFrom4CharCode(absd->mFormatID),
			absd->mFormatFlags,
			((absd->mFormatFlags & kAudioFormatFlagIsBigEndian) == kAudioFormatFlagIsBigEndian)?"Y":"N",
			((absd->mFormatFlags & kAudioFormatFlagIsFloat) == kAudioFormatFlagIsFloat)?"Y":"N",
			((absd->mFormatFlags & kAudioFormatFlagIsNonInterleaved) == kAudioFormatFlagIsNonInterleaved)?"Y":"N",
			absd->mBytesPerPacket,
			absd->mFramesPerPacket,
			absd->mBytesPerFrame,
			absd->mChannelsPerFrame,
			absd->mBitsPerChannel
			];
}

+ (NSString *) stringFromAVAudioSettingsDictionary:(NSDictionary *)optionsDictionary
{
	if(!optionsDictionary)
		return nil;
	
	return [NSString stringWithFormat:@"\n"
			"  Sample Rate:        %f\n"
			"  Format ID:          %@\n"
			"  Format Flags:       BigEndian: %s, IsFloat: %s, IsNonInterleaved: %s\n"
			"  Channels per Frame: %d\n"
			"  Bits per Channel:   %d",
			[[optionsDictionary objectForKey:AVSampleRateKey] floatValue],
			GetNSStringFrom4CharCode([[optionsDictionary objectForKey:AVFormatIDKey] intValue]),
			[[optionsDictionary objectForKey:AVLinearPCMIsBigEndianKey] boolValue]?"Y":"N",
			[[optionsDictionary objectForKey:AVLinearPCMIsFloatKey] boolValue]?"Y":"N",
			[[optionsDictionary objectForKey:AVLinearPCMIsNonInterleaved] boolValue]?"Y":"N",
			[[optionsDictionary objectForKey:AVNumberOfChannelsKey] intValue],
			[[optionsDictionary objectForKey:AVLinearPCMBitDepthKey] intValue]
			];
}

+ (NSString *) stringFromAVAssetReaderStatus:(AVAssetReaderStatus)status
{
	switch(status){
		case AVAssetReaderStatusUnknown:
			return @"Unknown";
			break;
		case AVAssetReaderStatusReading:
			return @"Reading";
			break;
		case AVAssetReaderStatusCompleted:
			return @"Completed";
			break;
		case AVAssetReaderStatusFailed:
			return @"Failed";
			break;
		case AVAssetReaderStatusCancelled:
			return @"Cancelled";
			break;
		default:
			return nil;
			break;
	}
}

#pragma mark Utility

+ (NSURL*) urlForPath:(NSString*) path
{
	if(nil == path)
	{
		return nil;
	}
	
	NSString* fullPath = path;
	
	NSRange urlCharRange = [fullPath rangeOfString:@":"];
	if(urlCharRange.length > 0)
	{
		return [NSURL URLWithString:fullPath];
	}
	
	
	if([fullPath characterAtIndex:0] != '/')
	{
		fullPath = [[NSBundle mainBundle] pathForResource:[[path pathComponents] lastObject] ofType:nil];
		if(nil == fullPath)
		{
			OAL_LOG_ERROR(@"Could not find full path of file %@", path);
			return nil;
		}
	}
	
	return [NSURL fileURLWithPath:fullPath];
}


#pragma mark Internal Use

- (UInt32) getIntProperty:(AudioSessionPropertyID) property
{
	UInt32 value = 0;
	UInt32 size = sizeof(value);
	OSStatus result;
	OPTIONALLY_SYNCHRONIZED(self)
	{
		result = AudioSessionGetProperty(property, &size, &value);
	}
	REPORT_AUDIOSESSION_CALL(result, @"Failed to get int property %08x", property);
	return value;
}

- (Float32) getFloatProperty:(AudioSessionPropertyID) property
{
	Float32 value = 0;
	UInt32 size = sizeof(value);
	OSStatus result;
	OPTIONALLY_SYNCHRONIZED(self)
	{
		result = AudioSessionGetProperty(property, &size, &value);
	}
	REPORT_AUDIOSESSION_CALL(result, @"Failed to get float property %08x", property);
	return value;
}

- (NSString*) getStringProperty:(AudioSessionPropertyID) property
{
	CFStringRef value;
	UInt32 size = sizeof(value);
	OSStatus result;
	OPTIONALLY_SYNCHRONIZED(self)
	{
		result = AudioSessionGetProperty(property, &size, &value);
	}
	REPORT_AUDIOSESSION_CALL(result, @"Failed to get string property %08x", property);
	if(noErr == result)
	{
		[(NSString*)value autorelease];
		return (NSString*)value;
	}
	return nil;
}

- (void) setIntProperty:(AudioSessionPropertyID) property value:(UInt32) value
{
	OSStatus result;
	OPTIONALLY_SYNCHRONIZED(self)
	{
		result = AudioSessionSetProperty(property, sizeof(value), &value);
	}
	REPORT_AUDIOSESSION_CALL(result, @"Failed to get int property %08x", property);
}

- (void) updateAudioMode
{
	// Simulator doesn't support setting the audio category.
#if !TARGET_IPHONE_SIMULATOR
	
	if(0 != overrideAudioSessionCategory)
	{
		[self setIntProperty:kAudioSessionProperty_AudioCategory value:overrideAudioSessionCategory];
	}
	else
	{
		if(honorSilentSwitch)
		{
			if(allowIpod && (self.ipodPlaying || !useHardwareIfAvailable))
			{
				// AmbientSound uses software codec.
				[self setIntProperty:kAudioSessionProperty_AudioCategory
							   value:kAudioSessionCategory_AmbientSound];
				[self setIntProperty:kAudioSessionProperty_OtherMixableAudioShouldDuck
							   value:ipodDucking];
			}
			else
			{
				// SoloAmbientSound uses hardware codec.
				[self setIntProperty:kAudioSessionProperty_AudioCategory
							   value:kAudioSessionCategory_SoloAmbientSound];
			}
		}
		else
		{
			// MediaPlayback also allows audio to continue playing when backgrounded.
			[self setIntProperty:kAudioSessionProperty_AudioCategory
						   value:kAudioSessionCategory_MediaPlayback];

			if(allowIpod && (self.ipodPlaying || !useHardwareIfAvailable))
			{
				// Mixing uses software codec.
				[self setIntProperty:kAudioSessionProperty_OverrideCategoryMixWithOthers
							   value:TRUE];
				[self setIntProperty:kAudioSessionProperty_OtherMixableAudioShouldDuck
							   value:ipodDucking];
			}
			else
			{
				// Non-mixing uses hardware codec, if available.
				[self setIntProperty:kAudioSessionProperty_OverrideCategoryMixWithOthers
							   value:FALSE];
			}
		}
	}
	
#endif /* !TARGET_IPHONE_SIMULATOR */
}

- (bool) audioSessionActive
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return audioSessionActive;
	}
}

/** Work around for iOS4 bug that causes the session to not activate on the first few attempts
 * in certain situations.
 *
 * @param currentRetryCount The retry attempt number.  It will give up after too many attempts.
 */ 
- (void) activateAudioSession:(int) currentRetryCount
{
	if(currentRetryCount >= kMaxSessionActivationRetries)
	{
		OAL_LOG_ERROR(@"Could not activate session after %d retries.", currentRetryCount);
		return;
	}
	
	OSStatus result = AudioSessionSetActive(YES);
	REPORT_AUDIOSESSION_CALL(result, @"Error activating audio session");
	if(noErr != result)
	{
		[NSThread sleepForTimeInterval:0.2];
		[self activateAudioSession:currentRetryCount + 1];
	}
}

- (void) setAudioSessionActive:(bool) value
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(value != audioSessionActive)
		{
			audioSessionActive = value;
			
			if(audioSessionActive)
			{
				[self updateAudioMode];
				[self activateAudioSession:0];
				self.suspended = NO;
			}
			else
			{
				REPORT_AUDIOSESSION_CALL(AudioSessionSetActive(NO), @"Error deactivating audio session");
				self.suspended = YES;
			}
		}
	}
}

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
		if(value != suspended)
		{
			suspended = value;
			if(suspended)
			{
				backgroundAudioWasSuspended = [OALAudioTracks sharedInstance].suspended;
				objectALWasSuspended = [OpenALManager sharedInstance].suspended;
				[OpenALManager sharedInstance].suspended = YES;
				[OALAudioTracks sharedInstance].suspended = YES;
			}
			else
			{
				if(!backgroundAudioWasSuspended)
				{
					[OALAudioTracks sharedInstance].suspended = NO;
				}
				if(!objectALWasSuspended)
				{
					[OpenALManager sharedInstance].suspended = NO;
				}
			}
		}
	}
}

- (void) onInterruptBegin
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		audioSessionWasActive = audioSessionActive;
		
		if(handleInterruptions && audioSessionWasActive)
		{
			self.audioSessionActive = NO;
		}
		
		if(audioSessionDelegate && [audioSessionDelegate respondsToSelector:@selector(beginInterruption)])
		{
			[audioSessionDelegate beginInterruption];
		}
		
		[[NSNotificationCenter defaultCenter] postNotificationName:OALAudioSessionInterruptBeginNotification object:nil];
	}
}

- (void) onInterruptEnd
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(handleInterruptions && audioSessionWasActive)
		{
			self.audioSessionActive = YES;
		}
		
		if(audioSessionDelegate){
			if([audioSessionDelegate respondsToSelector:@selector(endInterruptionWithFlags:)])
			{
				[audioSessionDelegate endInterruptionWithFlags:AVAudioSessionInterruptionFlags_ShouldResume];
			}
			else if([audioSessionDelegate respondsToSelector:@selector(endInterruption)])
			{
				[audioSessionDelegate endInterruption];
			}
		}
		
		[[NSNotificationCenter defaultCenter] postNotificationName:OALAudioSessionInterruptEndNotification object:nil];
	}
}

static void interruptListenerCallback(void* inUserData, UInt32 interruptionState)
{
	OALAudioSupport* handler = (OALAudioSupport*) inUserData;
	switch(interruptionState)
	{
		case kAudioSessionBeginInterruption:
			[handler onInterruptBegin];
			break;
		case kAudioSessionEndInterruption:
			[handler onInterruptEnd];
			break;
	}
}

@end
