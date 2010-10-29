//
//  OALAudioTrackNotifications.h
//
//  Created by CJ Hanson on 10/16/10.
//

#import <Foundation/Foundation.h>

extern NSString *const OALAudioTrackSourceChangedNotification;
extern NSString	*const OALAudioTrackStartedPlayingNotification;
extern NSString	*const OALAudioTrackStoppedPlayingNotification;
extern NSString	*const OALAudioTrackFinishedPlayingNotification;
extern NSString	*const OALAudioTrackLoopedNotification;

@class OALAudioPlayer;
/* A protocol for delegates of OALAudioPlayer that mimics and expands upon AVAudioPlayer so that it can be used for all types of underlying players (AVPlayer, AVAudioPlayer, whatever) */
@protocol OALAudioPlayerDelegate <NSObject>
@optional 
/* audioPlayerDidFinishPlaying:successfully: is called when a sound has finished playing. This method is NOT called if the player is stopped due to an interruption. */
- (void)audioPlayerDidFinishPlaying:(OALAudioPlayer *)player successfully:(BOOL)flag;

/* if an error occurs while decoding it will be reported to the delegate. */
- (void)audioPlayerDecodeErrorDidOccur:(OALAudioPlayer *)player error:(NSError *)error;

#if TARGET_OS_IPHONE
/* audioPlayerBeginInterruption: is called when the audio session has been interrupted while the player was playing. The player will have been paused. */
- (void)audioPlayerBeginInterruption:(OALAudioPlayer *)player;

/* audioPlayerEndInterruption:withFlags: is called when the audio session interruption has ended and this player had been interrupted while playing. */
/* Currently the only flag is AVAudioSessionInterruptionFlags_ShouldResume. */
#if defined(__MAC_10_7) || defined(__IPHONE_4_0)
- (void)audioPlayerEndInterruption:(OALAudioPlayer *)player withFlags:(NSUInteger)flags
__OSX_AVAILABLE_STARTING(__MAC_NA,__IPHONE_4_0);
#endif

/* audioPlayerEndInterruption: is called when the preferred method, audioPlayerEndInterruption:withFlags:, is not implemented. */
- (void)audioPlayerEndInterruption:(OALAudioPlayer *)player;
#endif
@end