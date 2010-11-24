//
//  OALAudioTrackManager.m
//  ObjectAL
//
//  Created by Karl Stenerud on 10-09-18.
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

#import "OALAudioTrackManager.h"
#import "NSMutableArray+WeakReferences.h"
#import "ObjectALMacros.h"
#import "OALAudioSupport.h"
#import "OALInterruptAPI.h"


ADD_INTERRUPT_API(OALAudioTrack);


#pragma mark OALAudioTrackManager

@implementation OALAudioTrackManager

#pragma mark Object Management

SYNTHESIZE_SINGLETON_FOR_CLASS(OALAudioTrackManager);

- (id) init
{
	if(nil != (self = [super init]))
	{
		OAL_LOG_DEBUG(@"%@: Init", self);
		// Make sure OALAudioSupport is initialized.
		[OALAudioSupport sharedInstance];

		tracks = [[NSMutableArray mutableArrayUsingWeakReferencesWithCapacity:10] retain];
		suspendLock = [[SuspendLock lockWithTarget:nil
									  lockSelector:nil
									unlockSelector:nil] retain];
	}
	return self;
}

- (void) dealloc
{
	OAL_LOG_DEBUG(@"%@: Dealloc", self);
	[tracks release];
	[suspendLock release];
	
	[super dealloc];
}


#pragma mark Properties

@synthesize tracks;

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
		if(suspendLock.locked)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return;
		}
		
		paused = value;
		for(OALAudioTrack* track in tracks)
		{
			track.paused = paused;
		}
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
		if(suspendLock.locked)
		{
			OAL_LOG_DEBUG(@"%@: Called mutator on suspended object", self);
			return;
		}
		
		muted = value;
		for(OALAudioTrack* track in tracks)
		{
			track.muted = muted;
		}
	}
}

- (bool) suspended
{
	// No need to synchronize since SuspendLock does that already.
	return suspendLock.suspendLock;
}

- (void) setSuspended:(bool) value
{
	// Ensure setting/resetting occurs in opposing order
	if(value)
	{
		for(OALAudioTrack* track in tracks)
		{
			track.suspended = value;
		}
	}

	// No need to synchronize since SuspendLock does that already.
	suspendLock.suspendLock = value;

	// Ensure setting/resetting occurs in opposing order
	if(!value)
	{
		for(OALAudioTrack* track in tracks)
		{
			track.suspended = value;
		}
	}
}

- (bool) interrupted
{
	// No need to synchronize since SuspendLock does that already.
	return suspendLock.interruptLock;
}

- (void) setInterrupted:(bool) value
{
	// Ensure setting/resetting occurs in opposing order
	if(value)
	{
		for(OALAudioTrack* track in tracks)
		{
			track.interrupted = value;
		}
	}

	// No need to synchronize since SuspendLock does that already.
	suspendLock.interruptLock = value;

	// Ensure setting/resetting occurs in opposing order
	if(!value)
	{
		for(OALAudioTrack* track in tracks)
		{
			track.interrupted = value;
		}
	}
}


#pragma mark Internal Use

- (void) notifyTrackInitializing:(OALAudioTrack*) track
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		[tracks addObject:track];
	}
}

- (void) notifyTrackDeallocating:(OALAudioTrack*) track
{
	OPTIONALLY_SYNCHRONIZED(self)
	{
		[tracks removeObject:track];
	}
}

@end
