//
//  OALAudioPlayerAudioQueueAVAssetReader.h
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

#import "OALAudioPlayer.h"

@interface OALAudioPlayerAudioQueueAVAssetReader : OALAudioPlayer {

}

@end

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <CoreMedia/CoreMedia.h>
#import <Accelerate/Accelerate.h>
#import "CJMusicPlayerProtocol.h"

typedef struct CJDSP CJDSP;

#define CJMP_NUM_QUEUE_BUFFERS	3

@interface CJAVAssetPlayer : NSObject <CJMusicPlayerProtocol> {
	E_CJMP_State					audioState;
	
	AudioStreamBasicDescription		dataFormat;
	AudioQueueRef					queue;
	AudioQueueTimelineRef			queueTimeline;
	SInt64							packetIndex;
	UInt32							numPacketsToRead;
	AudioStreamPacketDescription	*packetDescs;
	BOOL							isLooping;
	BOOL							trackClosed;
	BOOL							trackEnded;
	AudioQueueBufferRef				buffers[CJMP_NUM_QUEUE_BUFFERS];
	Float32							currentVolume;
	
	AVAssetReader					*audioReader;
	AVAssetReaderAudioMixOutput		*audioReaderMixerOutput;
	AVAsset							*audioAsset;
	
	NSTimeInterval					duration;
	
	NSTimeInterval					playbackStartTime;
	NSTimeInterval					pauseStartTime;
	NSTimeInterval					pauseDuration;
	Float64							lastCurrentTime;
	NSTimeInterval					timeOfLastCurrentTimeCheck;
	NSTimeInterval					timeOfLastEstimatedTimeCheck;
	
	BOOL							sessionWasInterrupted;
	NSTimeInterval					positionBeforeInterruption;
	
	NSTimeInterval					seekTimeOffset;
	
	BOOL							willDispatchNotifications;
	
	AudioConverterRef				audioConverter;
	AudioStreamBasicDescription		convertedFormat;
	
@public	
	void							*convertedDataRaw;
	Float32							*convertedData;
	UInt32							convertedDataLength;
	
	CJDSP							*dsp;
}

@property (nonatomic, readonly) AudioQueueRef queue;
@property (nonatomic, readonly) UInt32 numPacketsToRead;

@property (retain) AVAssetReader *audioReader;
@property (retain) AVAssetReaderAudioMixOutput *audioReaderMixerOutput;
@property (retain) AVAsset *audioAsset;

- (BOOL)prepareToPlayAsset:(AVAsset *)anAsset;

@end
