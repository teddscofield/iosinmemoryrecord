#import <AudioToolbox/AudioToolbox.h>
#import "RecordStrip.h"

@interface RecordStrip() {
    AudioDataBlocks *recordStrip;
}
@end

@implementation RecordStrip

-(id)init
{
    [self initBuffers];
    return self;
}

-(void) initBuffers
{
    AudioDataBlock list[RECORD_STRIP_BLOCKS];
    
    for (int i = 0; i < RECORD_STRIP_BLOCKS; i++ ) {
        
        AudioBuffer *buffer = malloc(sizeof(AudioBuffer));
        buffer->mNumberChannels = 1;
        buffer->mDataByteSize = sizeof(SInt16)*512;
        buffer->mData = malloc(sizeof(SInt16)*512);
        
        AudioBufferList *aList = malloc(sizeof(AudioBufferList));
        aList->mNumberBuffers = 1;
        aList->mBuffers[0] = *buffer;
        
        [self muteBufferList:aList];

        AudioTimeStamp *timeStamp = malloc(sizeof(AudioTimeStamp));
        timeStamp->mFlags = 0;
        timeStamp->mHostTime = 0;
        timeStamp->mSampleTime = 0;
        
        AudioDataBlock *block = malloc(sizeof(AudioDataBlock));
        block->list = *aList;
        block->timeStamp = *timeStamp;
        
        list[i] = *block;
        
    }
    
    AudioDataBlocks *blocks = malloc(sizeof(AudioDataBlocks));
    for (int j = 0; j < RECORD_STRIP_BLOCKS; j++) {
        blocks->blocks[j] = list[j];
    }
    blocks->blockCount = RECORD_STRIP_BLOCKS;
    
    recordStrip = blocks;
}

-(AudioDataBlocks *)recordStrip
{
    return recordStrip;
}
-(void)muteBufferList:(AudioBufferList *)list
{
    for (UInt32 i=0; i < list->mNumberBuffers; i++) {
        UInt32 sz = list->mBuffers[i].mDataByteSize;
        void *d = list->mBuffers[i].mData;
        memset(d, 0, sz);
    }
}
@end
