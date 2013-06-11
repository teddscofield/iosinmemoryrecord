#import <AudioToolbox/AudioToolbox.h>
#import <AudioUnit/AudioUnit.h>
#import "CAStreamBasicDescription.h"
#import "CAXException.h"
#import "RecordSandbox.h"
#import "RecordStrip.h"

#define INPUT_BUS 1
#define OUTPUT_BUS 0
#define HWBUFF_SIZE 0.005

#define CHECK(error, operation) \
    XThrowIfError(error, operation)

// -------------------------------------------------------------------------- //

// private interface
@interface RecordSandbox() {
    AudioUnit _ioUnit;
    AudioDataBlocks *_recordStrip;
    tape_state _tapeState;
    UInt32 recordHead;
    UInt32 playbackHead;
    AudioTimeStamp timestamp;
}
@property AudioUnit ioUnit;
@end

// -------------------------------------------------------------------------- //

@implementation RecordSandbox
@synthesize ioUnit = _ioUnit,
            recordStrip = _recordStrip;
@synthesize tapeState = _tapeState;

// ----------------------------------------- //
//                                           //
//          C callback functions             //
//                                           //
// ----------------------------------------- //

// "mute" a buffer list by writing 0 values to the data buffers
void muteBufferList(AudioBufferList *list) {
    for (UInt32 i=0; i < list->mNumberBuffers; i++) {
        UInt32 sz = list->mBuffers[i].mDataByteSize;
        void *d = list->mBuffers[i].mData;
        memset(d, 0, sz);
    }
}

// Plaback callback function
//   This callback will take data out of the appication memory buffer
//   and write it to the output HW buffers.
OSStatus PlayProc(void *inRefCon,
                          AudioUnitRenderActionFlags *ioActionFlags,
                          const AudioTimeStamp *inTimeStamp,
                          UInt32 inBusNumber,
                          UInt32 inNumberFrames,
                          AudioBufferList *ioData)
{
    RecordSandbox *THIS = (__bridge RecordSandbox *)inRefCon;
    
    printf("\nPlayProc begins %f\nnumber of frames: %d\n",inTimeStamp->mSampleTime, (unsigned int)inNumberFrames);

    //printfTimeStamp(inTimeStamp);
    //printfBufferList(ioData);
    
    muteBufferList(ioData);

    if (THIS->_tapeState == record_state) {
        printf("RECORDING INPUT DATA\n");
        CHECK(AudioUnitRender(THIS->_ioUnit,
                              ioActionFlags,
                              inTimeStamp,
                              INPUT_BUS,
                              inNumberFrames,
                              ioData),
              "plabackCallback AudioUnitRender call failed");
        
        // copy ioData into the current record buffer slot
        // increment recordStrip offset (aka recordHead
        AudioDataBlocks *strip = THIS->_recordStrip;
        UInt32 offset = THIS->recordHead;
        AudioBufferList list = strip->blocks[offset].list;
        if (THIS->recordHead < RECORD_STRIP_BLOCKS) {
            for (int i = 0; i < ioData->mNumberBuffers; i++) {
                memcpy(list.mBuffers[i].mData,
                       ioData->mBuffers[i].mData,
                       ioData->mBuffers[i].mDataByteSize);
                strip->blocks[offset].timeStamp = *inTimeStamp;
                THIS->timestamp = *inTimeStamp;
                THIS->recordHead++;
            }
        }
    }
    
    if (THIS->_tapeState == playback_state) {
        printf("PLAYBACK\n");
        if (THIS->playbackHead < RECORD_STRIP_BLOCKS) {
            AudioDataBlocks *strip = THIS->_recordStrip;
            UInt32 offset = THIS->playbackHead;
            AudioBufferList list = strip->blocks[offset].list;
            printf("  PLAYING RECORDED DATA\n");
            //printfBufferList(&list);
            for (int i = 0; i < ioData->mNumberBuffers; i++) {
                memcpy(ioData->mBuffers[i].mData,
                       list.mBuffers[i].mData,
                       ioData->mBuffers[i].mDataByteSize);
            }
            THIS->timestamp = strip->blocks[offset].timeStamp;
        }

    }

    printf("playbackHead: %d\n",(unsigned int)THIS->playbackHead);
    printf("recordHead: %d\n",(unsigned int)THIS->recordHead);
    THIS->playbackHead++;
    return noErr;
}

// print debug AudioBufferList information to console
void printfBufferList(AudioBufferList *list) {
    printf("  AudioBufferList Debug\n");
    UInt32 numBuffs = list->mNumberBuffers;
    printf("    number of buffers: %d\n",(unsigned int)numBuffs);
    
    for (UInt32 i=0; i < list->mNumberBuffers; i++) {
        printf("    buffer # %d\n",(unsigned int)i);
        AudioBuffer buffer = list->mBuffers[i];
        printf("      number of channels in buffer: %d\n",(unsigned int)buffer.mNumberChannels);
        printf("      data size of buffer: %d bytes\n",(unsigned int)buffer.mDataByteSize);
    }
}

// print debug AudioTimeStamp information to consol
void printfTimeStamp(const AudioTimeStamp *timeStamp)
{
    UInt32 flags = timeStamp->mFlags;
    printf("  AudioTimeStamp Debug\n");
    printf("    flags: %d\n",(unsigned int)flags);
    
    if (kAudioTimeStampSampleTimeValid & flags) {
        printf("    Sample Time: %f\n",timeStamp->mSampleTime);
    }
    if (kAudioTimeStampHostTimeValid & flags) {
        printf("    Host Time  : %lld\n",timeStamp->mHostTime);
    }
    if (kAudioTimeStampRateScalarValid & flags) {
        printf("    Rate Scalar: %f\n",timeStamp->mRateScalar);
    }
    if (kAudioTimeStampWordClockTimeValid & flags) {
        printf("    Word Clock Time: %lld\n",timeStamp->mWordClockTime);
    }
    if (kAudioTimeStampSMPTETimeValid & flags) {
        printf("    SMPTE Time: available\n");
        //TODO: print full SMPTE structure
    }
}

// ----------------------------------------- //
//                                           //
//            Objective-C methods            //
//                                           //
// ----------------------------------------- //

-(id)init {
    self.tapeState = stopped_state;
    playbackHead = 0;
    recordHead = 0;
    RecordStrip *s = [[RecordStrip alloc] init];
    self.recordStrip = s.recordStrip;
    timestamp = {0};

    [self setupSession];
    [self createIoObject];
    [self enableInputBus];
    [self setIoStreamDescriptions];
    [self setOutputRenderCallback];
    
    return self;
}

-(void)record
{
    playbackHead = 0;
    recordHead = 0;
    self.tapeState = record_state;
    
    // "erase" everything prior to recording
    AudioDataBlocks *strip = self.recordStrip;
    for (int x = 0; x < RECORD_STRIP_BLOCKS; x++) {
        AudioBufferList list = strip->blocks[x].list;
        [self muteBufferList:&list];
    }
    
    CHECK(AudioSessionSetActive(true),
          "Could not activate the AudioSession");
    
    CHECK(AudioOutputUnitStart(_ioUnit),
          "couldn't start the remote I/O unit");
}

-(void)play
{
    playbackHead = 0;
    recordHead = 0;
    self.tapeState = playback_state;

    CHECK(AudioSessionSetActive(true),
          "Could not activate the AudioSession");
    
    CHECK(AudioOutputUnitStart(_ioUnit),
          "couldn't start the remote I/O unit");
}

-(void)stop
{
    self.tapeState = stopped_state;
    AudioSessionSetActive(false);
    //      "Could not activate the AudioSession");
    
    CHECK(AudioOutputUnitStop(_ioUnit),
          "couldn't stop the remote I/O unit");
}

// ------------------------- //
//      setup methods        //
// ------------------------- //

// set up the AudioSession in record and play, set
// the (preferred) HW buffer size and finally activate
// the session.
-(void)setupSession {

    // Initialize the audio session
    CHECK(
          AudioSessionInitialize(NULL,
                                 NULL,
                                 NULL,
                                 (__bridge void*)self),
          "Could not initialize AudioSession");
    
    // set the Play & Record category
    UInt32 category = kAudioSessionCategory_PlayAndRecord;
    CHECK(
          AudioSessionSetProperty(kAudioSessionProperty_AudioCategory,
                                  sizeof(category),
                                  &category),
          "Could not set the AudioSession category");
    
    // set the preferred buffer size
    Float32 preferredBufferSize = HWBUFF_SIZE;
    CHECK(
          AudioSessionSetProperty(kAudioSessionProperty_PreferredHardwareIOBufferDuration,
                                  sizeof(preferredBufferSize),
                                  &preferredBufferSize),
          "couldn't set i/o buffer duration");

    // activate the audio session
    CHECK(
          AudioSessionSetActive(true),
          "Could not activate the AudioSession");

    // test to see if the mic gain can be controlled
    UInt32 ui32propSize = sizeof(UInt32);
    UInt32 inputGainAvailable = 0;
    CHECK(AudioSessionGetProperty(kAudioSessionProperty_InputGainAvailable,
                                  &ui32propSize,
                                  &inputGainAvailable),
          "error getting input gain availability");
    NSLog(@"is input gain available? %d",(unsigned int)inputGainAvailable);
    
}

// create a remoteIO unit object
-(void)createIoObject
{
    AudioComponentDescription acDesc;
    AudioComponent comp;
    
    // describe a remoteIO unit
    acDesc.componentType = kAudioUnitType_Output;
    acDesc.componentSubType = kAudioUnitSubType_RemoteIO;
    acDesc.componentManufacturer = kAudioUnitManufacturer_Apple;
    acDesc.componentFlags = 0;
    acDesc.componentFlagsMask = 0;
    comp = AudioComponentFindNext(NULL, &acDesc);
    
    // and fetch an instance
    CHECK(
          AudioComponentInstanceNew(comp, &_ioUnit),
          "couldn't create new remote I/O unit");
}

// enable the input bus (off by default)
-(void)enableInputBus
{
    UInt32 one = 1;
    CHECK(
          AudioUnitSetProperty(_ioUnit,
                               kAudioOutputUnitProperty_EnableIO,
                               kAudioUnitScope_Input,
                               INPUT_BUS,
                               &one,
                               sizeof(one)),
          "couldn't enable input on the remote I/O unit");
}

// setup the stream format on the input and output busses
-(void)setIoStreamDescriptions
{
    Float64 hwSampleRate = [self hardwareSampleRate];
    
    AudioStreamBasicDescription audioFormat = {0};
   	memset (&audioFormat, 0, sizeof (audioFormat)); // redundant?
    
    // define the sample
    audioFormat.mFormatID			= kAudioFormatLinearPCM;
    audioFormat.mFormatFlags		= kAudioFormatFlagIsPacked | kAudioFormatFlagIsSignedInteger;
    audioFormat.mSampleRate			= hwSampleRate;
	audioFormat.mBitsPerChannel		= 16;

    // define the frame
	audioFormat.mChannelsPerFrame	= 1;
	audioFormat.mBytesPerFrame		= 2;

    // define the packet
	audioFormat.mFramesPerPacket	= 1;
	audioFormat.mBytesPerPacket		= 2;

    CHECK(
          AudioUnitSetProperty(_ioUnit,
                               kAudioUnitProperty_StreamFormat,
                               kAudioUnitScope_Input,
                               OUTPUT_BUS,
                               &audioFormat,
                               sizeof(audioFormat)),
          "couldn't set the stream format on the output bus, input scope");
    
    
    CHECK(
          AudioUnitSetProperty(_ioUnit,
                               kAudioUnitProperty_StreamFormat,
                               kAudioUnitScope_Output,
                               INPUT_BUS,
                               &audioFormat,
                               sizeof(audioFormat)),
          "couldn't set the stream format on the input bus, output scope");
}

// setup the render callback function on the ouput scope of
// element 0 (aka the output bus)
-(void)setOutputRenderCallback
{    
    AURenderCallbackStruct cb;
    cb.inputProc = PlayProc;
    cb.inputProcRefCon = (__bridge void*)self;
    
    CHECK(AudioUnitSetProperty(_ioUnit,
                               kAudioUnitProperty_SetRenderCallback,
                               kAudioUnitScope_Global,
                               OUTPUT_BUS,
                               &cb, sizeof(cb)),
          "couldn't set remote i/o render callback");
    
    UInt32 flag = 1;
    CHECK(AudioUnitSetProperty(_ioUnit,
                               kAudioOutputUnitProperty_StartTimestampsAtZero,
                               kAudioUnitScope_Global,
                               OUTPUT_BUS,
                               &flag, sizeof(flag)),
          "couldn't set remote i/o start timestamp at zero");
}

// ------------------------- //
//       helper methods      //
// ------------------------- //

// get the actual hardware sample rate.
-(Float64)hardwareSampleRate
{
    Float64 hardwareSampleRate;
	UInt32 propSize = sizeof (hardwareSampleRate);
    
	CHECK(
          AudioSessionGetProperty(kAudioSessionProperty_CurrentHardwareSampleRate,
                                  &propSize,
                                  &hardwareSampleRate),
          "Couldn't get hardwareSampleRate");
    
    return hardwareSampleRate;
}

// get the duration in seconds of the hardware IO buffers
-(Float64)hardwareIOBufferDuration
{
    Float64 hardwareSampleRate = [self hardwareSampleRate];
    Float32 audioBufferSize;
    UInt32 sz = sizeof (audioBufferSize);
    AudioSessionGetProperty(kAudioSessionProperty_CurrentHardwareIOBufferDuration,
                                  &sz,
                                  &audioBufferSize);
    
    Float64 secondsPerSample = 1/hardwareSampleRate;
    Float32 samplesPerBuffer = audioBufferSize/secondsPerSample;
    
    NSLog(@"audio buffer size  : %f", audioBufferSize);
	NSLog(@"hardwareSampleRate : %f", hardwareSampleRate);
    NSLog(@"seconds per sample : %f", secondsPerSample);
    NSLog(@"samples per buffer : %f", samplesPerBuffer);
    
    return audioBufferSize;
}

//    kAudioSessionProperty_CurrentHardwareIOBufferDuration
-(void)printfBufferList:(AudioBufferList *)list
{
    printfBufferList(list);
}

-(void)printfTimeStamp:(const AudioTimeStamp *)timeStamp
{
    printfTimeStamp(timeStamp);
}

-(void)muteBufferList:(AudioBufferList *)list
{
    muteBufferList(list);
}

-(UInt32)getRecordHeadValue
{
    return recordHead;
}

-(UInt32)getPlayHeadValue
{
    return playbackHead;
}

-(AudioTimeStamp) getTimestamp
{
    return timestamp;
}

@end
// NOTES:
//
// A sample - is a single value at a given position in a waveform
// A channel - refers to data associated with a particular audio stream, ie, left/right channel for stereo, a single channel for mono, etc.
// A frame - contains the samples for all channels for a given position in a waveform
// A packet - contains one or more frames
