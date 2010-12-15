//
//  OALAudioPlayerAudioUnitAVAssetReader.h
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

#import "ObjectALConfig.h"
#import "OALAudioPlayer.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreMedia/CoreMedia.h>
#import <AudioUnit/AudioUnit.h>
#import "aurio_helper.h"
#import "CAStreamBasicDescription.h"

@interface OALAudioPlayerAudioUnitAVAssetReader : OALAudioPlayer {
	NSURL							*url;
	float							volume;
	float							pan;
	NSInteger						loopCount;
	NSInteger						numberOfLoops;
	
	CAStreamBasicDescription		dataFormat;
	BOOL							mute;
	AudioUnit						rioUnit;
	BOOL							unitIsRunning;
	BOOL							unitHasBeenCreated;
	AURenderCallbackStruct			inputProc;
	float							tempbuf[8000];
	float							*readbuffer_;
	int								readpos_;
	int								writepos_;
	int								buffersize_;
	UInt32							maxFPS;
	UInt32							dataAvailable;
	
	SInt64							packetIndex;
	SInt64							packetIndexSeeking;
	BOOL							trackEnded;
	
	AVAssetReader					*assetReader;
	AVAssetReader					*assetReaderSeeking;
	AVAssetReaderAudioMixOutput		*assetReaderMixerOutput;
	AVAssetReaderAudioMixOutput		*assetReaderMixerOutputSeeking;
	AVURLAsset						*asset;
	
	NSOperationQueue				*readerOpQueue;
	BOOL							backgroundloadflag_;
	BOOL							backgroundloadshouldstopflag_;
	
	NSTimeInterval					seekTimeOffset;
	NSTimeInterval					lastCurrentTime;
	
	NSTimeInterval					duration;
}

@property (nonatomic, assign)	AudioUnit				rioUnit;
@property (nonatomic, assign)	BOOL					unitIsRunning;
@property (nonatomic, assign)	BOOL					unitHasBeenCreated;
@property (nonatomic, assign)	BOOL					mute;
@property (nonatomic, assign)	AURenderCallbackStruct	inputProc;

- (BOOL) setupReader:(AVAssetReader **)outReader output:(AVAssetReaderAudioMixOutput **)outOutput forAsset:(AVAsset *)anAsset error:(NSError **)outError;
- (BOOL) setupAudioUnit;
- (BOOL) setupDSP;
- (void) close;
- (void) processSampleDataForNumPackets:(UInt32)numPackets;

@end
