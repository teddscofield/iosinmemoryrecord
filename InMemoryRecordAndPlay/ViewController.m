#import "ViewController.h"
#import "RecordStrip.h"
#import "RecordSandbox.h"

@interface ViewController ()
- (IBAction)stopButtonClick:(id)sender;
- (IBAction)recordButtonClick:(id)sender;
- (IBAction)playButtonClick:(id)sender;

@property (weak, nonatomic) IBOutlet UILabel *statevalLabel;
@property (weak, nonatomic) IBOutlet UILabel *timevalLabel;

@property (weak, nonatomic) IBOutlet UILabel *playposvalLabel;
@property (weak, nonatomic) IBOutlet UILabel *recposvalLabel;

@property RecordSandbox *recordSandbox;
@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.recordSandbox = [[RecordSandbox alloc] init];

    [NSTimer
     scheduledTimerWithTimeInterval:(1./30.)
     target:self
     selector:@selector(refresh)
     userInfo:nil
     repeats:YES
     ];
}

-(void)refresh
{
    // plackback head "position" (offset in the buffer really)
    UInt32 p = [self.recordSandbox getPlayHeadValue];
    NSString *str = [NSString stringWithFormat: @"%u", (unsigned int)p];
    self.playposvalLabel.text = str;
    
    // record head "position" (offset in the buffer really)
    UInt32 r = [self.recordSandbox getRecordHeadValue];
    NSString *strR = [NSString stringWithFormat: @"%u", (unsigned int)r];
    self.recposvalLabel.text = strR;
    
    // friendly timestamp display with (fake) SMPTE frames
    AudioTimeStamp t = [self.recordSandbox getTimestamp];
    NSTimeInterval ti = t.mSampleTime / [self.recordSandbox hardwareSampleRate];
    NSInteger v = (NSInteger)ti;
    NSInteger seconds = v % 60;
    NSInteger minutes = (v / 60) % 60;
    NSTimeInterval ms = ti - minutes - seconds;
    NSString *hmm = [NSString stringWithFormat:@"%02i:%02i.%02i", minutes, seconds,(int)(ms*1000/30)];
    self.timevalLabel.text = hmm;
    
    // current transport state
    NSString *strTS = @"unknown tape state";
    tape_state ts = self.recordSandbox.tapeState;
    switch (ts) {
        case record_state:
            strTS = @"recording";
            break;
        case playback_state:
            strTS = @"playing back";
            break;
        case stopped_state:
            strTS = @"stopped";
            break;
    }
    self.statevalLabel.text = strTS;
    
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

- (IBAction)stopButtonClick:(id)sender {
    [self.recordSandbox stop];
}

- (IBAction)recordButtonClick:(id)sender {
    [self.recordSandbox record];
}

- (IBAction)playButtonClick:(id)sender {
    [self.recordSandbox play];
}
@end
