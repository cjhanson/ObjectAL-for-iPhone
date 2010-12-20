//
//  OALAudioTrack.m
//  ObjectAL
//
//  Created by Karl Stenerud on 10-08-21.
//
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

#import "OALAudioTrack.h"
#import "mach_timing.h"
#import <AudioToolbox/AudioToolbox.h>
#import "OALAudioActions.h"
#import "OALAudioTrackManager.h"
#import "OALAudioSupport.h"
#import "OALUtilityActions.h"
#import "ObjectALMacros.h"
#import "OALAudioPlayer.h"
#import "OALAudioPlayerAVPlayer.h"
#import "OALAudioPlayerAVAudioPlayer.h"

#pragma mark Asynchronous Operations

/**
 * (INTERNAL USE) NSOperation for running an audio operation asynchronously.
 */
@interface OAL_AsyncAudioTrackOperation: NSOperation
{
	/** The audio track object to perform the operation on */
	OALAudioTrack* audioTrack;
	/** The URL of the sound file to play */
	NSURL* url;
	/** The seekTime of the sound file */
	NSTimeInterval seekTime;
	/** The target to inform when the operation completes */
	id target;
	/** The selector to call when the operation completes */
	SEL selector;
}

/** (INTERNAL USE) Create a new Asynchronous Operation.
 *
 * @param track the audio track to perform the operation on.
 * @param seekTime the position in the file to start playing at.
 * @param url the URL containing the sound file.
 * @param target the target to inform when the operation completes.
 * @param selector the selector to call when the operation completes.
 */ 
+ (id) operationWithTrack:(OALAudioTrack*) track url:(NSURL*) url seekTime:(NSTimeInterval)seekTime target:(id) target selector:(SEL) selector;

/** (INTERNAL USE) Initialize an Asynchronous Operation.
 *
 * @param track the audio track to perform the operation on.
 * @param seekTime the position in the file to start playing at.
 * @param url the URL containing the sound file.
 * @param target the target to inform when the operation completes.
 * @param selector the selector to call when the operation completes.
 */ 
- (id) initWithTrack:(OALAudioTrack*) track url:(NSURL*) url seekTime:(NSTimeInterval)seekTime target:(id) target selector:(SEL) selector;

@end

@implementation OAL_AsyncAudioTrackOperation

+ (id) operationWithTrack:(OALAudioTrack*) track url:(NSURL*) url seekTime:(NSTimeInterval)seekTime target:(id) target selector:(SEL) selector
{
	return [[[self alloc] initWithTrack:track url:url seekTime:seekTime target:target selector:selector] autorelease];
}

- (id) initWithTrack:(OALAudioTrack*) track url:(NSURL*) urlIn seekTime:(NSTimeInterval)seekTimeIn target:(id) targetIn selector:(SEL) selectorIn
{
	if(nil != (self = [super init]))
	{
		audioTrack = [track retain];
		url = [urlIn retain];
		seekTime = seekTimeIn;
		target = targetIn;
		selector = selectorIn;
	}
	return self;
}

- (void) dealloc
{
	[audioTrack release];
	[url release];
	
	[super dealloc];
}

@end


/**
 * (INTERNAL USE) NSOperation for playing an audio file asynchronously.
 */
@interface OAL_AsyncAudioTrackPlayOperation : OAL_AsyncAudioTrackOperation
{
	/** The number of times to loop during playback */
	NSInteger loops;
}

/**
 * (INTERNAL USE) Create an asynchronous play operation.
 *
 * @param track the audio track to perform the operation on.
 * @param url The URL of the file to play.
 * @param loops The number of times to loop playback (-1 = forever).
 * @param target The target to inform when playback finishes.
 * @param selector the selector to call when playback finishes.
 * @return a new operation.
 */
+ (id) operationWithTrack:(OALAudioTrack*) track url:(NSURL*) url loops:(NSInteger) loops target:(id) target selector:(SEL) selector;

/**
 * (INTERNAL USE) Initialize an asynchronous play operation.
 *
 * @param track the audio track to perform the operation on.
 * @param url The URL of the file to play.
 * @param loops The number of times to loop playback (-1 = forever).
 * @param target The target to inform when playback finishes.
 * @param selector the selector to call when playback finishes.
 * @return The initialized operation.
 */
- (id) initWithTrack:(OALAudioTrack*) track url:(NSURL*) url loops:(NSInteger) loops target:(id) target selector:(SEL) selector;

@end


@implementation OAL_AsyncAudioTrackPlayOperation

+ (id) operationWithTrack:(OALAudioTrack*) track url:(NSURL*) url loops:(NSInteger) loops target:(id) target selector:(SEL) selector
{
	return [[[self alloc] initWithTrack:track url:url loops:loops target:target selector:selector] autorelease];
}

- (id) initWithTrack:(OALAudioTrack*) track url:(NSURL*) urlIn loops:(NSInteger) loopsIn target:(id) targetIn selector:(SEL) selectorIn
{
	if(nil != (self = [super initWithTrack:track url:urlIn seekTime:0 target:targetIn selector:selectorIn]))
	{
		loops = loopsIn;
	}
	return self;
}

- (id) initWithTrack:(OALAudioTrack*) track url:(NSURL*) urlIn target:(id) targetIn selector:(SEL) selectorIn
{
	return [self initWithTrack:track url:urlIn loops:0 target:targetIn selector:selectorIn];
}

- (void)main
{
	[audioTrack playUrl:url loops:loops];
	[target performSelectorOnMainThread:selector withObject:audioTrack waitUntilDone:NO];
}

@end


/**
 * (INTERNAL USE) NSOperation for preloading an audio file asynchronously.
 */
@interface OAL_AsyncAudioTrackPreloadOperation : OAL_AsyncAudioTrackOperation
{
}

@end


@implementation OAL_AsyncAudioTrackPreloadOperation

- (void)main
{
	[audioTrack preloadUrl:url seekTime:seekTime];
	[target performSelectorOnMainThread:selector withObject:audioTrack waitUntilDone:NO];
}

@end

#pragma mark -
#pragma mark Private Methods

/**
 * (INTERNAL USE) Private interface to AudioTrack.
 */
@interface OALAudioTrack (Private)

#if TARGET_IPHONE_SIMULATOR && OBJECTAL_CFG_SIMULATOR_BUG_WORKAROUND

/** If the background music playback on the simulator ends (or is stopped), it mutes
 * OpenAL audio.  This method works around the issue by putting the player into looped
 * playback mode with volume set to 0 until the next instruction is received.
 */
- (void) simulatorBugWorkaroundHoldPlayer;

/** Part of the simulator bug workaround
 */
- (void) simulatorBugWorkaroundRestorePlayer;


#define SIMULATOR_BUG_WORKAROUND_PREPARE_PLAYBACK() [self simulatorBugWorkaroundRestorePlayer]
#define SIMULATOR_BUG_WORKAROUND_END_PLAYBACK() [self simulatorBugWorkaroundHoldPlayer]

#else /* TARGET_IPHONE_SIMULATOR && OBJECTAL_CFG_SIMULATOR_BUG_WORKAROUND */

#define SIMULATOR_BUG_WORKAROUND_PREPARE_PLAYBACK()
#define SIMULATOR_BUG_WORKAROUND_END_PLAYBACK()

#endif /* TARGET_IPHONE_SIMULATOR && OBJECTAL_CFG_SIMULATOR_BUG_WORKAROUND */

@end

#pragma mark -
#pragma mark AudioTrack

@implementation OALAudioTrack

#pragma mark Object Management

static Class preferredPlayerClass = nil;
+ (void) setPreferredPlayerClass:(Class)aPlayerClass
{
	preferredPlayerClass = aPlayerClass;
}

+ (Class) preferredPlayerClass
{
	return preferredPlayerClass;
}

+ (id) track
{
	return [[[self alloc] init] autorelease];
}

- (id) init
{
	if(nil != (self = [super init]))
	{
		OAL_LOG_DEBUG(@"%@: Init", self);
		// Make sure OALAudioTrackManager is initialized.
		[OALAudioTrackManager sharedInstance];
		
		operationQueue = [[NSOperationQueue alloc] init];
		operationQueue.maxConcurrentOperationCount = 1;
		
		meteringEnabled = false;
		player = nil;
		currentlyLoadedUrl = nil;
		paused = false;
		muted = false;
		gain = 1.0f;
		pan = 0.5f;
		numberOfLoops = 0;
		delegate = nil;
		simulatorPlayerRef = nil;
		playing =  false;
		currentTime = 0.0;
		gainAction	= nil;
		panAction = nil;
		suspendLock = [[SuspendLock lockWithTarget:self
									  lockSelector:@selector(onSuspend)
									unlockSelector:@selector(onUnsuspend)] retain];
		
		[[OALAudioTrackManager sharedInstance] notifyTrackInitializing:self];
	}
	return self;
}

- (void) dealloc
{
	OAL_LOG_DEBUG(@"%@: Dealloc", self);
	[[OALAudioTrackManager sharedInstance] notifyTrackDeallocating:self];

	[operationQueue release];
	[currentlyLoadedUrl release];
	[player release];
	[simulatorPlayerRef release];
	[gainAction stopAction];
	[gainAction release];
	[panAction stopAction];
	[panAction release];
	[suspendLock release];
	[super dealloc];
}

- (NSString*) description
{
	return [NSString stringWithFormat:@"<%@: %p: %@>", [self class], self, [currentlyLoadedUrl lastPathComponent]];
}

#pragma mark Properties

@synthesize currentlyLoadedUrl;

- (id<OALAudioPlayerDelegate>) delegate
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return delegate;
	}
}

- (void) setDelegate:(id<OALAudioPlayerDelegate>) value
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		delegate = value;
	}
}

- (float) pan
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return pan;
	}
}

- (void) setPan:(float) value
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		pan = value;
		player.pan = pan;
	}
}

- (float) volume
{
	return self.gain;
}

- (float) gain
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return gain;
	}
}

- (void) setVolume:(float) value
{
	self.gain = value;
}

- (void) setGain:(float) value
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		gain = value;
		if(muted)
		{
			value = 0;
		}
		if(player)
			player.volume = value;
	}
}

- (bool) muted
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return muted;
	}
}

- (void) setMuted:(bool) value
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		muted = value;
		if(muted)
		{
			[self stopActions];
		}
		float resultingGain = muted ? 0 : gain;
		player.volume = resultingGain;
	}
}

- (NSInteger) numberOfLoops
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return numberOfLoops;
	}
}

- (void) setNumberOfLoops:(NSInteger) value
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		player.numberOfLoops = numberOfLoops = value;
	}
}

- (bool) paused
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return paused;
	}
}

- (void) setPaused:(bool) value
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(paused != value)
		{
			paused = value;
			
			if(paused)
			{
				OAL_LOG_DEBUG(@"%@: Pause", self);
				[player pause];
				if(playing)
				{
					[[NSNotificationCenter defaultCenter] performSelectorOnMainThread:@selector(postNotification:)
																		   withObject:[NSNotification notificationWithName:OALAudioTrackStoppedPlayingNotification object:self] waitUntilDone:NO];
				}
			}
			else if(playing)
			{
				OAL_LOG_DEBUG(@"%@: Unpause", self);
				playing = [player play];
				if(playing)
				{
					[[NSNotificationCenter defaultCenter] performSelectorOnMainThread:@selector(postNotification:)
																		   withObject:[NSNotification notificationWithName:OALAudioTrackStartedPlayingNotification object:self] waitUntilDone:NO];
				}
			}
		}
	}
}

@synthesize player;

@synthesize playing;

- (bool)playing
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return (playing==YES && paused==NO);
	}
}

- (NSTimeInterval) currentTime
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return (nil == player) ? currentTime : player.currentTime;
	}
}

- (void) setCurrentTime:(NSTimeInterval) value
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		currentTime = value;
		if(nil != player)
		{
			player.currentTime = currentTime;
		}
	}
}

- (NSTimeInterval) deviceCurrentTime
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(nil != player)
		{
			return player.deviceCurrentTime;
		}
		return -1;
	}
}

- (NSTimeInterval) duration
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return player.duration;
	}
}

- (NSUInteger) numberOfChannels
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return player.numberOfChannels;
	}
}

/** Called by SuspendLock to suspend this object.
 */
- (void) onSuspend
{
	OAL_LOG_DEBUG(@"Track suspended.");
	
	//Just aborting actions
	if(gainAction){
		[self stopFade];
	}
	
	if(panAction){
		[self stopPan];
	}
	
	playerStateBeforeSuspension = player.state;
	player.suspended = YES;
	playing = player.isPlaying;
	paused = (player.state == OALPlayerStatePaused);
	
	OAL_LOG_DEBUG(@"Player state before: %d now: %d. Playing: %s, Paused: %s", playerStateBeforeSuspension, player.state, playing?"Y":"N", paused?"Y":"N");
	
	if((playerStateBeforeSuspension == OALPlayerStatePlaying) && (player.state != OALPlayerStatePlaying)){
		OAL_LOG_DEBUG(@"Dispatching stopped playing notification");
		[[NSNotificationCenter defaultCenter] performSelectorOnMainThread:@selector(postNotification:) withObject:[NSNotification notificationWithName:OALAudioTrackStoppedPlayingNotification object:self] waitUntilDone:NO];
	}
	/*
	 if(playing && !paused)
	 {
	 OAL_LOG_DEBUG(@"Pausing player");
	 currentTime = player.currentTime;
	 [player pause];
	 }
	 */
}

/** Called by SuspendLock to unsuspend this object.
 */
- (void) onUnsuspend
{
	OAL_LOG_DEBUG(@"Track Unsuspended.");
//	OALPlayerState playerStateBeforeUnsuspension = player.state;
	player.suspended = NO;
	
	if(playerStateBeforeSuspension != player.state){
		OAL_LOG_DEBUG(@"Player state before: %d now: %d. Playing: %s, Paused: %s", playerStateBeforeSuspension, player.state, playing?"Y":"N", paused?"Y":"N");
		bool startPlayback = NO;
		bool stopPlayback = NO;
		bool pausePlayback = NO;
		switch(playerStateBeforeSuspension){
			case OALPlayerStateClosed:
				break;
			case OALPlayerStateNotReady:
				break;
			case OALPlayerStateStopped:
				stopPlayback = YES;
				break;
			case OALPlayerStatePlaying:
				startPlayback = YES;
				break;
			case OALPlayerStatePaused:
				startPlayback = YES;
				pausePlayback = YES;
				break;
			case OALPlayerStateSeeking:
				//just tell it to play
				if(player.state != OALPlayerStatePlaying){
					startPlayback = YES;
				}
				break;
			default:
				//Undefined state
				break;
		}
		
		bool didStopPlayback = NO;
		bool didStartPlayback = NO;
		
		if(startPlayback){
			OAL_LOG_DEBUG(@"Telling player to play");
			didStartPlayback = (!playing || paused);
			playing = [player play];
			paused = NO;
		}else if(stopPlayback){
			OAL_LOG_DEBUG(@"Telling player to stop");
			didStopPlayback = (playing && !paused);
			[player stop];
			playing = NO;
			paused = NO;
		}else if(pausePlayback){
			OAL_LOG_DEBUG(@"Telling player to play then pause");
			didStopPlayback = (playing && !paused);
			playing = [player play];
			paused = YES;
			[player pause];
		}
		
		if(didStopPlayback){
			OAL_LOG_DEBUG(@"Dispatching stopped playing notification");
			[[NSNotificationCenter defaultCenter] performSelectorOnMainThread:@selector(postNotification:) withObject:[NSNotification notificationWithName:OALAudioTrackStoppedPlayingNotification object:self] waitUntilDone:NO];
		}else if(didStartPlayback){
			OAL_LOG_DEBUG(@"Dispatching started playing notification");
			[[NSNotificationCenter defaultCenter] performSelectorOnMainThread:@selector(postNotification:) withObject:[NSNotification notificationWithName:OALAudioTrackStartedPlayingNotification object:self] waitUntilDone:NO];
		}
	}
	/*
	if(playing && !paused)
	{
		OAL_LOG_DEBUG(@"Playing player");
		player.currentTime = currentTime;
		[player play];
	}
	 */
}

- (bool) suspended
{
	// No need to synchronize since SuspendLock does that already.
	return suspendLock.suspendLock;
}

- (void) setSuspended:(bool) value
{
	// No need to synchronize since SuspendLock does that already.
	suspendLock.suspendLock = value;
}

- (bool) interrupted
{
	// No need to synchronize since SuspendLock does that already.
	return suspendLock.interruptLock;
}

- (void) setInterrupted:(bool) value
{
	// No need to synchronize since SuspendLock does that already.
	suspendLock.interruptLock = value;
}


#pragma mark Playback

- (bool) preloadUrl:(NSURL*) url
{
	return [self preloadUrl:url seekTime:0];
}

- (bool) preloadUrl:(NSURL*) url seekTime:(NSTimeInterval)seekTime
{
	if(nil == url)
	{
		OAL_LOG_ERROR(@"%@: Cannot open NULL file / url", self);
		return NO;
	}
	
	OPTIONALLY_SYNCHRONIZED(self)
	{
		bool alreadyLoaded = (currentlyLoadedUrl && [[url absoluteString] isEqualToString:[currentlyLoadedUrl absoluteString]]);
		OAL_LOG_DEBUG_COND(alreadyLoaded, @"%@: %@: URL already preloaded", self, url);

		// Mimic a successful load
		if(alreadyLoaded)
		{
			[self performSelector:@selector(postTrackSourceChangedNotification:) withObject:nil afterDelay:0.01];
			return YES;
		}
		
		[self clear];
		
		/*
		[self stopActions];
		
		SIMULATOR_BUG_WORKAROUND_PREPARE_PLAYBACK();
		if(playing || paused)
		{
			[player stop];
		}
		[player release];
		player = nil;
		if(playing)
		{
			[[NSNotificationCenter defaultCenter] performSelectorOnMainThread:@selector(postNotification:) withObject:[NSNotification notificationWithName:OALAudioTrackStoppedPlayingNotification object:self] waitUntilDone:NO];
		}
		*/
		NSError* error;
		Class playerClass = (preferredPlayerClass)?preferredPlayerClass:[OALAudioPlayer getClassForPlayerType:OALAudioPlayerTypeDefault];
		if(!playerClass)
		{
			OAL_LOG_ERROR(@"Could not get class of preferred type: %@", preferredPlayerClass);
			return NO;
		}
		
		player = (OALAudioPlayer *)[[playerClass alloc] initWithContentsOfURL:url seekTime:seekTime error:&error];
		
		if(player == nil)
		{
			OAL_LOG_ERROR(@"Could not load URL %@: %@", url, [error localizedDescription]);
			return NO;
		}
		
		player.volume = muted ? 0 : gain;
		player.numberOfLoops = numberOfLoops;
		player.meteringEnabled = meteringEnabled;
		player.delegate = self;
		player.pan = pan;
		
		[currentlyLoadedUrl release];
		currentlyLoadedUrl = [url retain];
		
		//Seek is not guaranteed to hit the exact requested time, so store whatever it ended up at
		currentTime	= player.currentTime;
		playing = NO;
		paused = NO;
		
		if(player.status == OALPlayerStatusReadyToPlay){
			OAL_LOG_DEBUG(@"Player is ready to play delaying post ready by 0.01");
			[self performSelector:@selector(postTrackSourceChangedNotification:) withObject:nil afterDelay:0.01];
		}else{
			OAL_LOG_DEBUG(@"Player is NOT ready to play watching for internal ready to play notification");
			[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(postTrackSourceChangedNotification:) name:@"OALAudioPlayerReadyToPlay" object:nil];
		}
		return YES;
	}
}

- (void) postTrackSourceChangedNotification:(NSNotification *)notification
{	
	[[NSNotificationCenter defaultCenter] removeObserver:self name:@"OALAudioPlayerReadyToPlay" object:nil];
	
	[[NSNotificationCenter defaultCenter] performSelectorOnMainThread:@selector(postNotification:) withObject:[NSNotification notificationWithName:OALAudioTrackSourceChangedNotification object:self] waitUntilDone:NO];
}

- (bool) preloadFile:(NSString*) path
{
	return [self preloadFile:path seekTime:0];
}

- (bool) preloadFile:(NSString*) path seekTime:(NSTimeInterval)seekTime
{
	return [self preloadUrl:[OALAudioSupport urlForPath:path] seekTime:seekTime];
}

- (bool) preloadUrlAsync:(NSURL*) url target:(id) target selector:(SEL) selector
{
	return [self preloadUrlAsync:url seekTime:0 target:target selector:selector];
}

- (bool) preloadUrlAsync:(NSURL*) url seekTime:(NSTimeInterval)seekTime target:(id) target selector:(SEL) selector
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		[operationQueue addOperation:[OAL_AsyncAudioTrackPreloadOperation operationWithTrack:self url:url seekTime:seekTime target:target selector:selector]];
		return NO;
	}
}

- (bool) preloadFileAsync:(NSString*) path target:(id) target selector:(SEL) selector
{
	return [self preloadFileAsync:path seekTime:0 target:target selector:selector];
}

- (bool) preloadFileAsync:(NSString*) path seekTime:(NSTimeInterval)seekTime target:(id) target selector:(SEL) selector
{
	return [self preloadUrlAsync:[OALAudioSupport urlForPath:path] seekTime:seekTime target:target selector:selector];
}

- (bool) playUrl:(NSURL*) url
{
	return [self playUrl:url loops:0];
}

- (bool) playUrl:(NSURL*) url loops:(NSInteger) loops
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if([self preloadUrl:url])
		{
			self.numberOfLoops = loops;
			return [self play];
		}
		return NO;
	}
}

- (bool) playFile:(NSString*) path
{
	return [self playUrl:[OALAudioSupport urlForPath:path]];
}

- (bool) playFile:(NSString*) path loops:(NSInteger) loops
{
	return [self playUrl:[OALAudioSupport urlForPath:path] loops:loops];
}

- (void) playUrlAsync:(NSURL*) url target:(id) target selector:(SEL) selector
{
	[self playUrlAsync:url loops:0 target:target selector:selector];
}

- (void) playUrlAsync:(NSURL*) url loops:(NSInteger) loops target:(id) target selector:(SEL) selector
{
	[operationQueue addOperation:[OAL_AsyncAudioTrackPlayOperation operationWithTrack:self url:url loops:loops target:target selector:selector]];
}

- (void) playFileAsync:(NSString*) path target:(id) target selector:(SEL) selector
{
	[self playFileAsync:path loops:0 target:target selector:selector];
}

- (void) playFileAsync:(NSString*) path loops:(NSInteger) loops target:(id) target selector:(SEL) selector
{
	[self playUrlAsync:[OALAudioSupport urlForPath:path] loops:loops target:target selector:selector];
}

- (bool) play
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		[self stopActions];
		SIMULATOR_BUG_WORKAROUND_PREPARE_PLAYBACK();
		
		if(paused){
			playing = YES;
			self.paused = NO;
			return playing;
		}
		OAL_LOG_DEBUG(@"Restoring currentTime");
		player.currentTime = currentTime;
		player.volume = muted ? 0 : gain;
		player.numberOfLoops = numberOfLoops;
		paused = NO;
		playing = [player play];
		if(playing)
		{
			[[NSNotificationCenter defaultCenter] performSelectorOnMainThread:@selector(postNotification:) withObject:[NSNotification notificationWithName:OALAudioTrackStartedPlayingNotification object:self] waitUntilDone:NO];
		}
		return playing;
	}
}

- (bool) playAtTime:(NSTimeInterval) time
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		[self stopActions];
		SIMULATOR_BUG_WORKAROUND_PREPARE_PLAYBACK();
		player.currentTime = currentTime;
		player.volume = muted ? 0 : gain;
		player.numberOfLoops = numberOfLoops;
		paused = NO;
		playing = [player playAtTime:time];
		if(playing)
		{
			[[NSNotificationCenter defaultCenter] performSelectorOnMainThread:@selector(postNotification:) withObject:[NSNotification notificationWithName:OALAudioTrackStartedPlayingNotification object:self] waitUntilDone:NO];
		}
		return playing;
	}
}


- (void) pause
{
	if(paused)
		return;
	self.paused = YES;
}

- (void) resume
{
	if(!paused)
	{
		[self play];
		return;
	}
	self.paused = NO;
}

- (void) stop
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		[self stopActions];
		OAL_LOG_DEBUG(@"Storing player currentTime");
		currentTime = player.currentTime;
		[player stop];
		if(playing && !paused)
		{
			[[NSNotificationCenter defaultCenter] performSelectorOnMainThread:@selector(postNotification:) withObject:[NSNotification notificationWithName:OALAudioTrackStoppedPlayingNotification object:self] waitUntilDone:NO];
		}
		
//		self.currentTime = 0;
//		player.currentTime = 0;
		SIMULATOR_BUG_WORKAROUND_END_PLAYBACK();
		paused = NO;
		playing = NO;
	}
}

- (void) stopActions
{
	[self stopFade];
	[self stopPan];
}


- (void) fadeTo:(float) value
	   duration:(float) duration
		 target:(id) target
	   selector:(SEL) selector
{
	// Must always be synchronized
	@synchronized(self)
	{
		if(self.suspended)
			return;
		
		[self stopFade];
		gainAction = [[OALSequentialActions actions:
					   [OALGainAction actionWithDuration:duration endValue:value],
					   [OALCallAction actionWithCallTarget:target selector:selector withObject:self],
					   nil] retain];
		[gainAction runWithTarget:self];
	}
}

- (void) stopFade
{
	// Must always be synchronized
	@synchronized(self)
	{
		if(nil != gainAction)
		{
			self.volume = ((OALGainAction *)[((OALSequentialActions *)gainAction).actions objectAtIndex:0]).endValue;
			
			OAL_LOG_DEBUG(@"Stop fade, setting volume to end value of fade in progress %.2f.", self.volume);
			
			[gainAction stopAction];
			[gainAction release];
			gainAction = nil;
		}
	}
}

- (void) panTo:(float) value
	  duration:(float) duration
		target:(id) target
	  selector:(SEL) selector
{
	// Must always be synchronized
	@synchronized(self)
	{
		if(self.suspended)
			return;
		
		[self stopPan];
		panAction = [[OALSequentialActions actions:
					  [OALPanAction actionWithDuration:duration endValue:value],
					  [OALCallAction actionWithCallTarget:target selector:selector withObject:self],
					  nil] retain];
		[panAction runWithTarget:self];
	}
}

- (void) stopPan
{
	// Must always be synchronized
	@synchronized(self)
	{
		if(nil != panAction)
		{
			self.pan = ((OALPanAction *)[((OALSequentialActions *)panAction).actions objectAtIndex:0]).endValue;
			
			[panAction stopAction];
			[panAction release];
			panAction = nil;
		}
	}
}

- (void) close
{
	[self clear];
}

- (void) clear
{
	@synchronized(self)
	{
		[[NSNotificationCenter defaultCenter] removeObserver:self name:@"OALAudioPlayerReadyToPlay" object:nil];
		
		[self stopActions];
		[currentlyLoadedUrl release];
		currentlyLoadedUrl = nil;
		
		[player stop];
		
		paused = NO;
		muted = NO;

		if(playing)
		{
			playing = NO;
			[[NSNotificationCenter defaultCenter] performSelectorOnMainThread:@selector(postNotification:) withObject:[NSNotification notificationWithName:OALAudioTrackStoppedPlayingNotification object:self] waitUntilDone:NO];
		}
		
		//This must come after the notification
		//dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100000000), dispatch_get_main_queue(), ^{
			OAL_LOG_DEBUG(@"Releasing player implementation");
			[player release];
		//});
		player = nil;
		
		[NSThread sleepForTimeInterval:0.01];
		
		//This should come after the player is nil
		self.currentTime = 0;
	}
}


#pragma mark Metering

- (bool) meteringEnabled
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return meteringEnabled;
	}
}

- (void) setMeteringEnabled:(bool) value
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		meteringEnabled = value;
		player.meteringEnabled = meteringEnabled;
	}
}

- (void) updateMeters
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		[player updateMeters];
	}
}

- (float) averagePowerForChannel:(NSUInteger)channelNumber
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return [player averagePowerForChannel:channelNumber];
	}
}

- (float) peakPowerForChannel:(NSUInteger)channelNumber
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		return [player peakPowerForChannel:channelNumber];
	}
}


#pragma mark -
#pragma mark OALAudioPlayerDelegate

#if TARGET_OS_IPHONE
- (void) audioPlayerBeginInterruption:(OALAudioPlayer*) playerIn
{
	if([delegate respondsToSelector:@selector(audioPlayerBeginInterruption:)])
	{
		[delegate audioPlayerBeginInterruption:playerIn];
	}
}

#if defined(__MAC_10_7) || defined(__IPHONE_4_0)
- (void)audioPlayerEndInterruption:(OALAudioPlayer *)playerIn withFlags:(NSUInteger)flags
{
	if([delegate respondsToSelector:@selector(audioPlayerEndInterruption:withFlags:)])
	{
		[delegate audioPlayerEndInterruption:playerIn withFlags:flags];
	}
}
#endif

- (void) audioPlayerEndInterruption:(OALAudioPlayer*) playerIn
{
	if([delegate respondsToSelector:@selector(audioPlayerEndInterruption:)])
	{
		[delegate audioPlayerEndInterruption:playerIn];
	}
}
#endif //TARGET_OS_IPHONE

- (void) audioPlayerDecodeErrorDidOccur:(OALAudioPlayer*) playerIn error:(NSError*) error
{
	if([delegate respondsToSelector:@selector(audioPlayerDecodeErrorDidOccur:error:)])
	{
		[delegate audioPlayerDecodeErrorDidOccur:playerIn error:error];
	}
}

- (void) audioPlayerDidFinishPlaying:(OALAudioPlayer*) playerIn successfully:(BOOL) flag
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		playing = NO;
		paused = NO;
		SIMULATOR_BUG_WORKAROUND_END_PLAYBACK();
	}
	if([delegate respondsToSelector:@selector(audioPlayerDidFinishPlaying:successfully:)])
	{
		[delegate audioPlayerDidFinishPlaying:playerIn successfully:flag];
	}
	
	[[NSNotificationCenter defaultCenter] performSelectorOnMainThread:@selector(postNotification:) withObject:[NSNotification notificationWithName:OALAudioTrackStoppedPlayingNotification object:self] waitUntilDone:NO];
	[[NSNotificationCenter defaultCenter] performSelectorOnMainThread:@selector(postNotification:) withObject:[NSNotification notificationWithName:OALAudioTrackFinishedPlayingNotification object:self] waitUntilDone:NO];
}

#pragma mark -
#pragma mark Simulator playback bug handler

#if TARGET_IPHONE_SIMULATOR && OBJECTAL_CFG_SIMULATOR_BUG_WORKAROUND

- (void) simulatorBugWorkaroundRestorePlayer
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(nil != simulatorPlayerRef)
		{
			player = simulatorPlayerRef;
			simulatorPlayerRef = nil;
			[player stop];
			player.numberOfLoops = numberOfLoops;
			player.volume = gain;
		}
	}
}

- (void) simulatorBugWorkaroundHoldPlayer
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		if(nil != player)
		{
			player.volume = 0;
			player.numberOfLoops = -1;
			[player play];
			simulatorPlayerRef = player;
			player = nil;
		}
	}
}

#endif /* TARGET_IPHONE_SIMULATOR && OBJECTAL_CFG_SIMULATOR_BUG_WORKAROUND */

@end
