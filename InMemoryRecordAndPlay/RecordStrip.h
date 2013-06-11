#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#define RECORD_STRIP_BLOCKS 4096

typedef struct {
    AudioBufferList list;
    AudioTimeStamp timeStamp;
} AudioDataBlock;

typedef struct {
    AudioDataBlock blocks[RECORD_STRIP_BLOCKS];
    int blockCount;
} AudioDataBlocks;

@interface RecordStrip : NSObject
-(AudioDataBlocks *)recordStrip;
-(void)muteBufferList:(AudioBufferList *)list;
@end
