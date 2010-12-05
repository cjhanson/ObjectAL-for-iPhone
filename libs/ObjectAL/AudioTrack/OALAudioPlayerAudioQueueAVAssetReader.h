//
//  OALAudioPlayerAudioQueueAVAssetReader.h
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

#import "ObjectALConfig.h"
#import "OALAudioPlayer.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreMedia/CoreMedia.h>

@interface OALAudioPlayerAudioQueueAVAssetReader : OALAudioPlayer {
	
	NSURL							*url;
	float							volume;
	float							pan;
	NSInteger						loopCount;
	NSInteger						numberOfLoops;
	OALPlayerStatus					status;
	OALPlayerState					state;
	
	AudioQueueBufferRef				buffers[OBJECTAL_CFG_AUDIO_QUEUE_NUM_BUFFERS];
	AudioStreamBasicDescription		dataFormat;
	AudioQueueRef					queue;
	AudioQueueTimelineRef			queueTimeline;
	AudioStreamPacketDescription	*packetDescs;
	SInt64							packetIndex;
	SInt64							packetIndexSeeking;
	UInt32							numPacketsToRead;
	BOOL							queueIsRunning;
	BOOL							trackEnded;
	
	AVAssetReader					*assetReader;
	AVAssetReader					*assetReaderSeeking;
	AVAssetReaderAudioMixOutput		*assetReaderMixerOutput;
	AVAssetReaderAudioMixOutput		*assetReaderMixerOutputSeeking;
	AVURLAsset						*asset;
	
	NSTimeInterval					seekTimeOffset;
	NSTimeInterval					lastCurrentTime;
	
	NSTimeInterval					positionBeforeInterruption;
	
	NSTimeInterval					duration;
}

- (BOOL) setupReader:(AVAssetReader **)outReader output:(AVAssetReaderAudioMixOutput **)outOutput forAsset:(AVAsset *)anAsset error:(NSError **)outError;
- (BOOL)setupAudioQueue;
- (BOOL) setupDSP;
- (void)close;
- (void) processSampleData:(AudioQueueBufferRef)buffer numPackets:(UInt32)numPackets;

@end
