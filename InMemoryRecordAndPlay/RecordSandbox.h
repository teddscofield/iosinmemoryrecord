#import <Foundation/Foundation.h>
#import "RecordStrip.h"

typedef enum  {
    stopped_state = 0,
    record_state = 1,
    playback_state = 2    
} tape_state;

@interface RecordSandbox : NSObject
-(id)init;
-(void)record;
-(void)play;
-(void)stop;
-(UInt32)getRecordHeadValue;
-(UInt32)getPlayHeadValue;
-(AudioTimeStamp) getTimestamp;

-(Float64)hardwareSampleRate;
-(Float64)hardwareIOBufferDuration;
@property tape_state tapeState;
@property AudioDataBlocks *recordStrip;
@end
