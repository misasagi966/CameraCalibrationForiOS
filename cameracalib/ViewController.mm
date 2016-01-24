#import "ViewController.h"
#import "AVFoundationUtil.h"
#import "MonochromeFilter.h"
#import "CameraCalibUtil.h"

@interface ViewController () <AVCaptureVideoDataOutputSampleBufferDelegate>

@property (strong, nonatomic) AVCaptureVideoDataOutput *videoDataOutput;
@property (strong, nonatomic) AVCaptureSession *session;
@property (assign, nonatomic) BOOL isUsingFrontFacingCamera;
@property (nonatomic) dispatch_queue_t videoDataOutputQueue;
@property (strong, nonatomic) CALayer *previewLayer;
//cameracalibutil
@property (atomic) CameraCalibUtil *cameracalib;
@property (atomic) int CalibDataCount;

@end

@implementation ViewController

#pragma mark - UIViewController lifecycle methods

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // プレビュー表示用レイヤー
    self.previewLayer = [CALayer layer];
    self.previewLayer.frame = self.view.bounds;
    [self.view.layer addSublayer:self.previewLayer];
    
    // 撮影ボタンを配置したツールバーを生成
    UIToolbar *toolbar = [[UIToolbar alloc]
                          initWithFrame:CGRectMake(0.0f,
                                                   self.view.bounds.size.height - 44.0f,
                                                   self.view.bounds.size.width,
                                                   44.0f)];
    
    UIBarButtonItem *flexibleSpace = [[UIBarButtonItem alloc]
                                      initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                      target:nil
                                      action:nil];
    
    UIBarButtonItem *takePhotoButton = [[UIBarButtonItem alloc]
                                        initWithBarButtonSystemItem:UIBarButtonSystemItemCamera
                                        target:self
                                        action:@selector(takePhoto:)];
    
    toolbar.items = @[flexibleSpace, takePhotoButton, flexibleSpace];
    [self.view addSubview:toolbar];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    // 撮影開始
    [self setupAVCapture];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    
    // 撮影終了
    [self teardownAVCapture];
}

#pragma mark - Action methods

- (void)takePhoto:(id)sender
{
    
    // シャッター音を鳴らす
    AudioServicesPlaySystemSound(1108);
    // プレビュー表示中のレイヤーを画像にして保存する
    UIGraphicsBeginImageContext(self.previewLayer.bounds.size);
    [self.previewLayer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    UIImage *processedImage = [CameraCalibUtil FindAndDrawChessBoardCorner :image];
    //NULLなら保存せず，そうでなければ画像を追加
    if(processedImage == NULL) return;
    [self.cameracalib SaveUIImageToArray :image];
    self.CalibDataCount++;
    
    
    if(self.CalibDataCount == 25){
        [self.cameracalib CameraCalibration];
    }
    
}

#pragma mark - Private methods

- (void)setupAVCapture
{
    // 入力と出力からキャプチャーセッションを作成
    self.session = [[AVCaptureSession alloc] init];
    
    
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        self.session.sessionPreset = AVCaptureSessionPreset640x480;
    } else {
        self.session.sessionPreset = AVCaptureSessionPresetPhoto;
    }
    
    // カメラからの入力を作成
    AVCaptureDevice *device;
    self.isUsingFrontFacingCamera = NO;
    device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    
    
    // カメラからの入力を作成
    NSError *error = nil;
    AVCaptureDeviceInput *deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    
    if (error) {
        UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Failed with error %d", (int)[error code]]
                                            message:[error localizedDescription]

                                     preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"Dismiss"
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        
        [self presentViewController:alert animated:YES completion:nil];
        [self teardownAVCapture];
        return;
    }
    
    // キャプチャーセッションに追加
    if ([self.session canAddInput:deviceInput]) {
        [self.session addInput:deviceInput];
    }
    
    // 画像への出力を作成
    self.videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    
    // 遅れてきたフレームは無視する
    self.videoDataOutput.alwaysDiscardsLateVideoFrames = YES;
    
    // ビデオへの出力の画像は、BGRAで出力
    self.videoDataOutput.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA)};
    
    // ビデオ出力のキャプチャの画像情報のキューを設定
    self.videoDataOutputQueue = dispatch_queue_create("VideoDataOutputQueue", DISPATCH_QUEUE_SERIAL);
    [self.videoDataOutput setSampleBufferDelegate:self queue:self.videoDataOutputQueue];
    
    // キャプチャーセッションに追加
    if ([self.session canAddOutput:self.videoDataOutput]) {
        [self.session addOutput:self.videoDataOutput];
    }
    
    // ビデオ入力のAVCaptureConnectionを取得
    AVCaptureConnection *videoConnection = [self.videoDataOutput connectionWithMediaType:AVMediaTypeVideo];
    videoConnection.videoOrientation = [AVFoundationUtil videoOrientationFromDeviceOrientation:[UIDevice currentDevice].orientation];
    

    // デバイスをロック
    if ([device lockForConfiguration:&error]) {
        // フレームレートを設定
        device.activeVideoMinFrameDuration  = CMTimeMake(1, 15);
        
        //デバイスロックを解除
        [device unlockForConfiguration];
    }
    
    //cameracalibutil
    self.cameracalib = [[CameraCalibUtil alloc] init];
    //空の配列を生成
    self.cameracalib.imageList = [NSMutableArray array];
    self.CalibDataCount =0;
    
    // 開始
    [self.session startRunning];
}

// キャプチャー情報をクリーンアップ
- (void)teardownAVCapture
{
    self.videoDataOutput = nil;
    if (self.videoDataOutputQueue) {
#if __IPHONE_OS_VERSION_MIN_REQUIRED < 60000
        dispatch_release(self.videoDataOutputQueue);
#endif
    }
}

// 画像の加工処理
- (void)process:(UIImage *)image
{
    self.previewLayer.contents = (__bridge id)(image.CGImage);
    
    // フロントカメラの場合は左右反転
    if (self.isUsingFrontFacingCamera) {
        self.previewLayer.affineTransform = CGAffineTransformMakeScale(-1.0f, 1.0f);
    }
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate methods

// AVCaptureVideoDataOutputSampleBufferDelegateプロトコルのメソッド。
// 新しいキャプチャの情報が追加されたときに呼び出される。
- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection
{
    // キャプチャしたフレームからCGImageを作成
    UIImage *image = [AVFoundationUtil imageFromSampleBuffer:sampleBuffer];
    
    // 画像を画面に表示
    dispatch_async(dispatch_get_main_queue(), ^{
        [self process:image];
    });
}

@end