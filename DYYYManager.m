// DYYYManager.m
#import "DYYYManager.h"
#import <Photos/Photos.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <ImageIO/ImageIO.h>
#import <MobileCoreServices/UTCoreTypes.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <CoreMedia/CMMetadata.h>
#import <CoreAudioTypes/CoreAudioTypes.h>


// 自定义进度条视图类
@interface DYYYManager(){
    AVAssetExportSession *session;    // 资源导出会话
    AVURLAsset *asset;                // 媒体资源
    AVAssetReader *reader;            // 媒体读取器
    AVAssetWriter *writer;            // 媒体写入器
    dispatch_queue_t queue;           // 异步队列
    dispatch_group_t group;           // 调度组
}
// 添加 fileLinks 属性声明
@property (nonatomic, strong, readwrite) NSMutableDictionary<NSString *, NSDictionary *> *fileLinks;
@end


@interface DYYYDownloadProgressView : UIView
@property (nonatomic, strong) UIView *containerView;          // 容器视图
@property (nonatomic, strong) UIView *progressBarBackground;  // 进度条背景
@property (nonatomic, strong) UIView *progressBar;            // 进度条
@property (nonatomic, strong) UILabel *progressLabel;         // 进度文本标签
@property (nonatomic, strong) UIButton *cancelButton;         // 取消按钮
@property (nonatomic, copy) void (^cancelBlock)(void);        // 取消回调
@property (nonatomic, assign) BOOL isCancelled;               // 取消标志

- (instancetype)initWithFrame:(CGRect)frame;
- (void)setProgress:(float)progress;     // 设置进度
- (void)show;                           // 显示进度视图
- (void)dismiss;                        // 隐藏进度视图

@end

@implementation DYYYDownloadProgressView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.isCancelled = NO;
        
        // 创建容器视图，减小尺寸
        _containerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 240, 140)];
        _containerView.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
        _containerView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
        _containerView.layer.cornerRadius = 12;
        _containerView.clipsToBounds = YES;
        [self addSubview:_containerView];
        
        // 创建进度条背景
        _progressBarBackground = [[UIView alloc] initWithFrame:CGRectMake(20, 50, CGRectGetWidth(_containerView.frame) - 40, 8)];
        _progressBarBackground.backgroundColor = [UIColor colorWithWhite:0.3 alpha:1.0];
        _progressBarBackground.layer.cornerRadius = 4;
        [_containerView addSubview:_progressBarBackground];
        
        // 创建进度条
        _progressBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, CGRectGetHeight(_progressBarBackground.frame))];
        _progressBar.backgroundColor = [UIColor colorWithRed:0.0 green:0.7 blue:1.0 alpha:1.0];
        _progressBar.layer.cornerRadius = 4;
        [_progressBarBackground addSubview:_progressBar];
        
        // 创建进度标签
        _progressLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, CGRectGetMaxY(_progressBarBackground.frame) + 12, CGRectGetWidth(_containerView.frame), 20)];
        _progressLabel.textAlignment = NSTextAlignmentCenter;
        _progressLabel.textColor = [UIColor whiteColor];
        _progressLabel.font = [UIFont systemFontOfSize:14];
        _progressLabel.text = @"0%";
        [_containerView addSubview:_progressLabel];
        
        // 创建取消按钮
        _cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _cancelButton.frame = CGRectMake((CGRectGetWidth(_containerView.frame) - 80) / 2, CGRectGetMaxY(_progressLabel.frame) + 10, 80, 32);
        _cancelButton.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
        [_cancelButton setTitle:@"取消" forState:UIControlStateNormal];
        [_cancelButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        _cancelButton.layer.cornerRadius = 16;
        [_cancelButton addTarget:self action:@selector(cancelButtonTapped) forControlEvents:UIControlEventTouchUpInside];
        [_containerView addSubview:_cancelButton];
        
        // 添加标题标签
        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 15, CGRectGetWidth(_containerView.frame), 20)];
        titleLabel.textAlignment = NSTextAlignmentCenter;
        titleLabel.textColor = [UIColor whiteColor];
        titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        titleLabel.text = @"正在下载";
        [_containerView addSubview:titleLabel];
        
        // 设置初始透明度为0，以便动画显示
        self.alpha = 0;
    }
    return self;
}

// 设置进度值，更新进度条和百分比文本
- (void)setProgress:(float)progress {
    // 确保在主线程中更新UI
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setProgress:progress];
        });
        return;
    }
    
    // 进度值限制在0到1之间
    progress = MAX(0.0, MIN(1.0, progress));
    
    // 设置进度条长度
    CGRect progressFrame = _progressBar.frame;
    progressFrame.size.width = progress * CGRectGetWidth(_progressBarBackground.frame);
    _progressBar.frame = progressFrame;
    
    // 更新进度百分比
    int percentage = (int)(progress * 100);
    _progressLabel.text = [NSString stringWithFormat:@"%d%%", percentage];
}

// 显示进度视图
- (void)show {
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    if (!window) return;
    
    [window addSubview:self];
    
    [UIView animateWithDuration:0.3 animations:^{
        self.alpha = 1.0;
    }];
}

// 隐藏并移除进度视图
- (void)dismiss {
    [UIView animateWithDuration:0.3 animations:^{
        self.alpha = 0;
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
    }];
}

// 取消按钮点击
- (void)cancelButtonTapped {
    self.isCancelled = YES; // 设置取消标志
    if (self.cancelBlock) {
        self.cancelBlock();
    }
    [self dismiss];
}

@end

@interface DYYYManager() <NSURLSessionDownloadDelegate>
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSURLSessionDownloadTask *> *downloadTasks;  // 下载任务字典
@property (nonatomic, strong) NSMutableDictionary<NSString *, DYYYDownloadProgressView *> *progressViews;  // 进度视图字典
@property (nonatomic, strong) NSOperationQueue *downloadQueue;                                            // 下载队列
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *taskProgressMap;               // 任务进度映射
@property (nonatomic, strong) NSMutableDictionary<NSString *, void (^)(BOOL success, NSURL *fileURL)> *completionBlocks; // 完成回调存储
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *mediaTypeMap;                  // 媒体类型映射

// 批量下载相关属性
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *downloadToBatchMap;            // 下载ID到批量ID的映射
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *batchCompletedCountMap;        // 批量ID到已完成数量的映射
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *batchSuccessCountMap;          // 批量ID到成功数量的映射
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *batchTotalCountMap;            // 批量ID到总数量的映射
@property (nonatomic, strong) NSMutableDictionary<NSString *, void (^)(NSInteger current, NSInteger total)> *batchProgressBlocks; // 批量进度回调
@property (nonatomic, strong) NSMutableDictionary<NSString *, void (^)(NSInteger successCount, NSInteger totalCount)> *batchCompletionBlocks; // 批量完成回调

// 类方法声明
+ (void)downloadAllImagesWithProgress:(NSMutableArray *)imageURLs
                             progress:(void (^)(NSInteger current, NSInteger total))progressBlock
                           completion:(void (^)(NSInteger successCount, NSInteger totalCount))completion;

// 实例方法声明
- (void)setCompletionBlock:(void (^)(BOOL success, NSURL *fileURL))completion
             forDownloadID:(NSString *)downloadID;

- (void)setMediaType:(MediaType)mediaType
       forDownloadID:(NSString *)downloadID;

// 添加 iOS 14 兼容保存方法声明
- (void)saveLivePhotoComponentsForIOS14:(NSString *)imagePath videoPath:(NSString *)videoPath;

// 串行保存图片到相册
+ (void)saveImagesSerially:(NSArray<NSURL *> *)imageURLs mediaTypes:(NSArray<NSNumber *> *)mediaTypes completion:(void (^)(NSInteger successCount, NSInteger totalCount))completion;

// 添加串行保存实况照片方法声明
+ (void)saveLivePhotosSerially:(NSArray<NSDictionary *> *)livePhotoArray completion:(void (^)(NSInteger successCount, NSInteger totalCount))completion;

@end

@implementation DYYYManager

+ (instancetype)shared {
    static DYYYManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

// 初始化方法
- (instancetype)init {
    self = [super init];
    if (self) {
        _fileLinks = [NSMutableDictionary dictionary];
        _downloadTasks = [NSMutableDictionary dictionary];
        _progressViews = [NSMutableDictionary dictionary];
        _downloadQueue = [[NSOperationQueue alloc] init];
        _downloadQueue.maxConcurrentOperationCount = 10;
        _taskProgressMap = [NSMutableDictionary dictionary];
        _completionBlocks = [NSMutableDictionary dictionary];
        _mediaTypeMap = [NSMutableDictionary dictionary];
        
        // 初始化批量下载相关字典
        _downloadToBatchMap = [NSMutableDictionary dictionary];
        _batchCompletedCountMap = [NSMutableDictionary dictionary];
        _batchSuccessCountMap = [NSMutableDictionary dictionary];
        _batchTotalCountMap = [NSMutableDictionary dictionary];
        _batchProgressBlocks = [NSMutableDictionary dictionary];
        _batchCompletionBlocks = [NSMutableDictionary dictionary];
    }
    return self;
}

// 获取当前活跃窗口
+ (UIWindow *)getActiveWindow {
    if (@available(iOS 15.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                    if (w.isKeyWindow) return w;
                }
            }
        }
        // 兼容 iOS 13/14
        if (@available(iOS 13.0, *)) {
             for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                 if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                     return ((UIWindowScene *)scene).windows.firstObject;
                 }
             }
        }
        // iOS 13 之前
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        return [UIApplication sharedApplication].keyWindow ?: [UIApplication sharedApplication].windows.firstObject;
        #pragma clang diagnostic pop

    } else {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        return [UIApplication sharedApplication].keyWindow ?: [UIApplication sharedApplication].windows.firstObject;
        #pragma clang diagnostic pop
    }
    return nil; // 添加默认返回值
}

// 获取当前顶层视图控制器
+ (UIViewController *)getActiveTopController {
    UIWindow *window = [self getActiveWindow];
    if (!window) return nil;
    
    UIViewController *topController = window.rootViewController;
    while (topController.presentedViewController) {
        topController = topController.presentedViewController;
    }
    
    return topController;
}

// 从十六进制字符串创建颜色
+ (UIColor *)colorWithHexString:(NSString *)hexString {
    // 处理随机颜色的情况
    if ([hexString.lowercaseString isEqualToString:@"random"] || [hexString.lowercaseString isEqualToString:@"#random"]) {
        return [UIColor colorWithRed:(CGFloat)arc4random_uniform(256)/255.0 
                              green:(CGFloat)arc4random_uniform(256)/255.0 
                               blue:(CGFloat)arc4random_uniform(256)/255.0 
                              alpha:1.0];
    }
    
    // 去掉"#"前缀并转为大写
    NSString *colorString = [[hexString stringByReplacingOccurrencesOfString:@"#" withString:@""] uppercaseString];
    CGFloat alpha = 1.0;
    CGFloat red = 0.0;
    CGFloat green = 0.0;
    CGFloat blue = 0.0;
    
    if (colorString.length == 8) {
        // 8位十六进制：AARRGGBB，前两位为透明度
        NSScanner *scanner = [NSScanner scannerWithString:[colorString substringWithRange:NSMakeRange(0, 2)]];
        unsigned int alphaValue;
        [scanner scanHexInt:&alphaValue];
        alpha = (CGFloat)alphaValue / 255.0;
        
        scanner = [NSScanner scannerWithString:[colorString substringWithRange:NSMakeRange(2, 2)]];
        unsigned int redValue;
        [scanner scanHexInt:&redValue];
        red = (CGFloat)redValue / 255.0;
        
        scanner = [NSScanner scannerWithString:[colorString substringWithRange:NSMakeRange(4, 2)]];
        unsigned int greenValue;
        [scanner scanHexInt:&greenValue];
        green = (CGFloat)greenValue / 255.0;
        
        scanner = [NSScanner scannerWithString:[colorString substringWithRange:NSMakeRange(6, 2)]];
        unsigned int blueValue;
        [scanner scanHexInt:&blueValue];
        blue = (CGFloat)blueValue / 255.0;
    } else {
        // 处理常规6位十六进制：RRGGBB
        NSScanner *scanner = nil;
        unsigned int hexValue = 0;
        
        if (colorString.length == 6) {
            scanner = [NSScanner scannerWithString:colorString];
        } else if (colorString.length == 3) {
            // 3位简写格式：RGB
            NSString *r = [colorString substringWithRange:NSMakeRange(0, 1)];
            NSString *g = [colorString substringWithRange:NSMakeRange(1, 1)];
            NSString *b = [colorString substringWithRange:NSMakeRange(2, 1)];
            colorString = [NSString stringWithFormat:@"%@%@%@%@%@%@", r, r, g, g, b, b];
            scanner = [NSScanner scannerWithString:colorString];
        }
        
        if (scanner && [scanner scanHexInt:&hexValue]) {
            red = ((hexValue & 0xFF0000) >> 16) / 255.0;
            green = ((hexValue & 0x00FF00) >> 8) / 255.0;
            blue = (hexValue & 0x0000FF) / 255.0;
        }
    }
    
    return [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
}

// 显示Toast提示
+ (void)showToast:(NSString *)text {
    Class toastClass = NSClassFromString(@"DUXToast");
    if (toastClass && [toastClass respondsToSelector:@selector(showText:)]) {
        [toastClass performSelector:@selector(showText:) withObject:text];
    }
}

// 保存媒体文件到相册
+ (void)saveMedia:(NSURL *)mediaURL mediaType:(MediaType)mediaType completion:(void (^)(void))completion {
    if (mediaType == MediaTypeAudio) {
        return;
    }

    // 检查权限
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        if (status == PHAuthorizationStatusAuthorized) {
            // 如果是表情包类型，先检查实际格式
            if (mediaType == MediaTypeHeic) {
                // 检测文件的实际格式
                NSString *actualFormat = [self detectFileFormat:mediaURL];
                
                if ([actualFormat isEqualToString:@"webp"]) {
                    // WebP格式处理
                    [self convertWebpToGifSafely:mediaURL completion:^(NSURL *gifURL, BOOL success) {
                        if (success && gifURL) {
                            [self saveGifToPhotoLibrary:gifURL mediaType:mediaType completion:^{
                                // 清理原始文件
                                [[NSFileManager defaultManager] removeItemAtPath:mediaURL.path error:nil];
                                if (completion) {
                                    completion();
                                }
                            }];
                        } else {
                            [self showToast:@"转换失败"];
                            // 清理临时文件
                            [[NSFileManager defaultManager] removeItemAtPath:mediaURL.path error:nil];
                            if (completion) {
                                completion();
                            }
                        }
                    }];
                } else if ([actualFormat isEqualToString:@"heic"] || [actualFormat isEqualToString:@"heif"]) {
                    // HEIC/HEIF格式处理
                    [self convertHeicToGif:mediaURL completion:^(NSURL *gifURL, BOOL success) {
                        if (success && gifURL) {
                            [self saveGifToPhotoLibrary:gifURL mediaType:mediaType completion:^{
                                // 清理原始文件
                                [[NSFileManager defaultManager] removeItemAtPath:mediaURL.path error:nil];
                                if (completion) {
                                    completion();
                                }
                            }];
                        } else {
                            [self showToast:@"转换失败"];
                            // 清理临时文件
                            [[NSFileManager defaultManager] removeItemAtPath:mediaURL.path error:nil];
                            if (completion) {
                                completion();
                            }
                        }
                    }];
                } else if ([actualFormat isEqualToString:@"gif"]) {
                    // 已经是GIF格式，直接保存
                    [self saveGifToPhotoLibrary:mediaURL mediaType:mediaType completion:completion];
                } else {
                    // 其他格式，尝试作为普通图像保存
                    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                        UIImage *image = [UIImage imageWithContentsOfFile:mediaURL.path];
                        if (image) {
                            [PHAssetChangeRequest creationRequestForAssetFromImage:image];
                        }
                    } completionHandler:^(BOOL success, NSError * _Nullable error) {
                        if (success) {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                [self showToast:[NSString stringWithFormat:@"%@已保存到相册", [self getMediaTypeDescription:mediaType]]];
                            });
                            
                            if (completion) {
                                completion();
                            }
                        } else {
                            [self showToast:@"保存失败"];
                        }
                        // 不管成功失败都清理临时文件
                        [[NSFileManager defaultManager] removeItemAtPath:mediaURL.path error:nil];
                    }];
                }
            } else {
                // 非表情包类型的正常保存流程
                [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                    if (mediaType == MediaTypeVideo) {
                        [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:mediaURL];
                    } else {
                        UIImage *image = [UIImage imageWithContentsOfFile:mediaURL.path];
                        if (image) {
                            [PHAssetChangeRequest creationRequestForAssetFromImage:image];
                        }
                    }
                } completionHandler:^(BOOL success, NSError * _Nullable error) {
                    if (success) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self showToast:[NSString stringWithFormat:@"%@已保存到相册", [self getMediaTypeDescription:mediaType]]];
                        });
                        
                        if (completion) {
                            completion();
                        }
                    } else {
                        [self showToast:@"保存失败"];
                    }
                    // 不管成功失败都清理临时文件
                    [[NSFileManager defaultManager] removeItemAtPath:mediaURL.path error:nil];
                }];
            }
        }
    }];
}

// 检测文件格式的方法
+ (NSString *)detectFileFormat:(NSURL *)fileURL {
    // 读取文件的整个数据或足够的字节用于识别
    NSData *fileData = [NSData dataWithContentsOfURL:fileURL options:NSDataReadingMappedIfSafe error:nil];
    if (!fileData || fileData.length < 12) {
        return @"unknown";
    }
    
    // 转换为字节数组以便检查
    const unsigned char *bytes = [fileData bytes];
    
    // 检查WebP格式："RIFF" + 4字节 + "WEBP"
    if (bytes[0] == 'R' && bytes[1] == 'I' && bytes[2] == 'F' && bytes[3] == 'F' &&
        bytes[8] == 'W' && bytes[9] == 'E' && bytes[10] == 'B' && bytes[11] == 'P') {
        return @"webp";
    }
    
    // 检查HEIF/HEIC格式："ftyp" 在第4-7字节位置
    if (bytes[4] == 'f' && bytes[5] == 't' && bytes[6] == 'y' && bytes[7] == 'p') {
        if (fileData.length >= 16) {
            // 检查HEIC品牌
            if (bytes[8] == 'h' && bytes[9] == 'e' && bytes[10] == 'i' && bytes[11] == 'c') {
                return @"heic";
            }
            // 检查HEIF品牌
            if (bytes[8] == 'h' && bytes[9] == 'e' && bytes[10] == 'i' && bytes[11] == 'f') {
                return @"heif";
            }
            // 可能是其他HEIF变体
            return @"heif";
        }
    }
    
    // 检查GIF格式："GIF87a"或"GIF89a"
    if (bytes[0] == 'G' && bytes[1] == 'I' && bytes[2] == 'F') {
        return @"gif";
    }
    
    // 检查PNG格式
    if (bytes[0] == 0x89 && bytes[1] == 'P' && bytes[2] == 'N' && bytes[3] == 'G') {
        return @"png";
    }
    
    // 检查JPEG格式
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
        return @"jpeg";
    }
    
    return @"unknown";
}

// 保存GIF到相册的方法
+ (void)saveGifToPhotoLibrary:(NSURL *)gifURL mediaType:(MediaType)mediaType completion:(void (^)(void))completion {
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        //获取GIF数据
        NSData *gifData = [NSData dataWithContentsOfURL:gifURL];
        //创建相册资源
        PHAssetCreationRequest *request = [PHAssetCreationRequest creationRequestForAsset];
        //实例相册类资源参数
        PHAssetResourceCreationOptions *options = [[PHAssetResourceCreationOptions alloc] init];
        //定义GIF参数
        options.uniformTypeIdentifier = @"com.compuserve.gif"; 
        //保存GIF图片
        [request addResourceWithType:PHAssetResourceTypePhoto data:gifData options:options];  
    } completionHandler:^(BOOL success, NSError * _Nullable error) {
        if (success) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showToast:[NSString stringWithFormat:@"%@已保存到相册", [self getMediaTypeDescription:mediaType]]];
            });
            
            if (completion) {
                completion();
            }
        } else {
            [self showToast:@"保存失败"];
        }
        // 不管成功失败都清理临时文件
        [[NSFileManager defaultManager] removeItemAtPath:gifURL.path error:nil];
    }];
}

// 使用原生 ImageIO 将 WebP 转换为 GIF的方法
+ (void)convertWebpToGifSafely:(NSURL *)webpURL completion:(void (^)(NSURL *gifURL, BOOL success))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // 创建GIF文件路径
        NSString *gifFileName = [[webpURL.lastPathComponent stringByDeletingPathExtension] stringByAppendingPathExtension:@"gif"];
        NSURL *gifURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:gifFileName]];

        // 读取WebP文件数据
        NSData *webpData = [NSData dataWithContentsOfURL:webpURL];
        if (!webpData) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(nil, NO);
                }
            });
            return;
        }

        // iOS 14+ 支持 UIImage 直接解码 WebP
        UIImage *image = [UIImage imageWithData:webpData];
        if (!image) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(nil, NO);
                }
            });
            return;
        }

        // 检查是否为动画 WebP（多帧），这里只处理静态 WebP
        if (image.images && image.images.count > 1) {
            // 动画 WebP 不支持，直接失败
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(nil, NO);
                }
            });
            return;
        }

        // 写入 GIF
        CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)gifURL, kUTTypeGIF, 1, NULL);
        if (!destination) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(nil, NO);
                }
            });
            return;
        }

        NSDictionary *gifProperties = @{
            (__bridge NSString *)kCGImagePropertyGIFDictionary: @{
                (__bridge NSString *)kCGImagePropertyGIFLoopCount: @0,
            }
        };
        CGImageDestinationSetProperties(destination, (__bridge CFDictionaryRef)gifProperties);

        NSDictionary *frameProperties = @{
            (__bridge NSString *)kCGImagePropertyGIFDictionary: @{
                (__bridge NSString *)kCGImagePropertyGIFDelayTime: @0.1f,
            }
        };

        CGImageDestinationAddImage(destination, image.CGImage, (__bridge CFDictionaryRef)frameProperties);
        BOOL success = CGImageDestinationFinalize(destination);
        CFRelease(destination);

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(gifURL, success);
            }
        });
    });
}

// 将HEIC转换为GIF的方法
+ (void)convertHeicToGif:(NSURL *)heicURL completion:(void (^)(NSURL *gifURL, BOOL success))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // 创建HEIC图像源
        CGImageSourceRef heicSource = CGImageSourceCreateWithURL((__bridge CFURLRef)heicURL, NULL);
        if (!heicSource) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(nil, NO);
                }
            });
            return;
        }
        
        // 获取HEIC图像数量
        size_t count = CGImageSourceGetCount(heicSource);
        BOOL isAnimated = (count > 1);
        
        // 创建GIF文件路径
        NSString *gifFileName = [[heicURL.lastPathComponent stringByDeletingPathExtension] stringByAppendingPathExtension:@"gif"];
        NSURL *gifURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:gifFileName]];
        
        // 设置GIF属性
        NSDictionary *gifProperties = @{
            (__bridge NSString *)kCGImagePropertyGIFDictionary: @{
                (__bridge NSString *)kCGImagePropertyGIFLoopCount: @0, // 0表示无限循环
            }
        };
        
        // 创建GIF图像目标
        CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)gifURL, kUTTypeGIF, isAnimated ? count : 1, NULL);
        if (!destination) {
            CFRelease(heicSource);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(nil, NO);
                }
            });
            return;
        }
        
        // 设置GIF属性
        CGImageDestinationSetProperties(destination, (__bridge CFDictionaryRef)gifProperties);
        
        if (isAnimated) {
            // 处理动画HEIC，提取所有帧并添加到GIF
            for (size_t i = 0; i < count; i++) {
                // 获取当前帧
                CGImageRef imageRef = CGImageSourceCreateImageAtIndex(heicSource, i, NULL);
                if (!imageRef) {
                    continue;
                }
                
                // 获取帧属性
                CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(heicSource, i, NULL);
                
                // 获取延迟时间
                float delayTime = 0.1f;
                if (properties) {
                    // 检查多个可能包含延迟时间的字典
                    CFDictionaryRef heicsProperties = CFDictionaryGetValue(properties, kCGImagePropertyHEICSDictionary);
                    if (heicsProperties) {
                        // 注意：使用通用的GIF延迟时间常量
                        CFNumberRef delayTimeRef = CFDictionaryGetValue(heicsProperties, kCGImagePropertyGIFDelayTime);
                        if (delayTimeRef) {
                            CFNumberGetValue(delayTimeRef, kCFNumberFloatType, &delayTime);
                        }
                        
                        // 尝试未压缩延迟时间
                        if (delayTime == 0.1f) {
                            CFNumberRef unclampedDelayTimeRef = CFDictionaryGetValue(heicsProperties, kCGImagePropertyGIFUnclampedDelayTime);
                            if (unclampedDelayTimeRef) {
                                CFNumberGetValue(unclampedDelayTimeRef, kCFNumberFloatType, &delayTime);
                            }
                        }
                    }
                    
                    if (delayTime == 0.1f) {
                        CFDictionaryRef heifProperties = CFDictionaryGetValue(properties, kCGImagePropertyHEIFDictionary);
                        if (heifProperties) {
                            // HEIF没有特定的延迟时间常量，使用GIF的常量尝试获取
                            CFNumberRef delayTimeRef = CFDictionaryGetValue(heifProperties, kCGImagePropertyGIFDelayTime);
                            if (delayTimeRef) {
                                CFNumberGetValue(delayTimeRef, kCFNumberFloatType, &delayTime);
                            }
                        }
                    }
                    
                    if (delayTime == 0.1f) {
                        CFDictionaryRef gifProperties = CFDictionaryGetValue(properties, kCGImagePropertyGIFDictionary);
                        if (gifProperties) {
                            CFNumberRef gifDelayTimeRef = CFDictionaryGetValue(gifProperties, kCGImagePropertyGIFDelayTime);
                            if (gifDelayTimeRef) {
                                CFNumberGetValue(gifDelayTimeRef, kCFNumberFloatType, &delayTime);
                            }
                            
                            if (delayTime == 0.1f) {
                                CFNumberRef unclampedDelayTimeRef = CFDictionaryGetValue(gifProperties, kCGImagePropertyGIFUnclampedDelayTime);
                                if (unclampedDelayTimeRef) {
                                    CFNumberGetValue(unclampedDelayTimeRef, kCFNumberFloatType, &delayTime);
                                }
                            }
                        }
                    }
                    
                    if (delayTime <= 0.01f || delayTime > 10.0f) {
                        delayTime = 0.1f;
                    }
                }
                
                // 创建帧属性
                NSDictionary *frameProperties = @{
                    (__bridge NSString *)kCGImagePropertyGIFDictionary: @{
                        (__bridge NSString *)kCGImagePropertyGIFDelayTime: @(delayTime),
                    }
                };
                
                // 添加帧到GIF
                CGImageDestinationAddImage(destination, imageRef, (__bridge CFDictionaryRef)frameProperties);
                
                // 释放资源
                CGImageRelease(imageRef);
                if (properties) {
                    CFRelease(properties);
                }
            }
        } else {
            // 处理静态HEIC，创建单帧GIF
            CGImageRef imageRef = CGImageSourceCreateImageAtIndex(heicSource, 0, NULL);
            if (imageRef) {
                // 创建帧属性
                NSDictionary *frameProperties = @{
                    (__bridge NSString *)kCGImagePropertyGIFDictionary: @{
                        (__bridge NSString *)kCGImagePropertyGIFDelayTime: @0.1f,
                    }
                };
                
                // 添加帧到GIF
                CGImageDestinationAddImage(destination, imageRef, (__bridge CFDictionaryRef)frameProperties);
                
                // 释放资源
                CGImageRelease(imageRef);
            }
        }
        
        // 完成GIF生成
        BOOL success = CGImageDestinationFinalize(destination);
        
        // 释放资源
        CFRelease(heicSource);
        CFRelease(destination);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(gifURL, success);
            }
        });
    });
}

//保存实况的方法，下载图片和下载视频
+ (void)downloadLivePhoto:(NSURL *)imageURL videoURL:(NSURL *)videoURL completion:(void (^)(void))completion {
    // 获取共享实例，确保FileLinks字典存在
    DYYYManager *manager = [DYYYManager shared];
    if (!manager.fileLinks) {
        [manager.fileLinks removeAllObjects]; // 正确：清空内容
    }
    
    // 为图片和视频URL创建唯一的键
    NSString *uniqueKey = [NSString stringWithFormat:@"%@_%@", imageURL.absoluteString, videoURL.absoluteString];
    
    // 检查是否已经存在此下载任务
    NSDictionary *existingPaths = manager.fileLinks[uniqueKey];
    if (existingPaths) {
        NSString *imagePath = existingPaths[@"image"];
        NSString *videoPath = existingPaths[@"video"];
        
        // 使用异步检查以避免主线程阻塞
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            BOOL imageExists = [[NSFileManager defaultManager] fileExistsAtPath:imagePath];
            BOOL videoExists = [[NSFileManager defaultManager] fileExistsAtPath:videoPath];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if (imageExists && videoExists) {
                    [[DYYYManager shared] saveLivePhoto:imagePath videoUrl:videoPath];
                    if (completion) {
                        completion();
                    }
                    return;
                } else {
                    // 文件不完整，需要重新下载
                    [self startDownloadLivePhotoProcess:imageURL videoURL:videoURL uniqueKey:uniqueKey completion:completion];
                }
            });
        });
    } else {
        // 没有缓存，直接开始下载
        [self startDownloadLivePhotoProcess:imageURL videoURL:videoURL uniqueKey:uniqueKey completion:completion];
    }
}

+ (void)startDownloadLivePhotoProcess:(NSURL *)imageURL videoURL:(NSURL *)videoURL uniqueKey:(NSString *)uniqueKey completion:(void (^)(void))completion {
    // 创建临时目录（如果不存在）
    NSString *livePhotoPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject 
                              stringByAppendingPathComponent:@"LivePhoto"];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:livePhotoPath]) {
        [fileManager createDirectoryAtPath:livePhotoPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    // 生成唯一标识符，防止多次调用时文件冲突
    NSString *uniqueID = [NSUUID UUID].UUIDString;
    NSString *imagePath = [livePhotoPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.heic", uniqueID]];
    NSString *videoPath = [livePhotoPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.mp4", uniqueID]];
    
    // 存储文件路径，以便下次下载相同的URL时可以复用
    DYYYManager *manager = [DYYYManager shared];
    [manager.fileLinks setObject:@{@"image": imagePath, @"video": videoPath} forKey:uniqueKey];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // 创建进度视图
        CGRect screenBounds = [UIScreen mainScreen].bounds;
        DYYYDownloadProgressView *progressView = [[DYYYDownloadProgressView alloc] initWithFrame:screenBounds];
        progressView.progressLabel.text = @"准备下载实况照片...";
        [progressView show];
        
        // 优化会话配置
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        configuration.timeoutIntervalForRequest = 60.0;  // 增加超时时间
        configuration.timeoutIntervalForResource = 60.0;
        configuration.HTTPMaximumConnectionsPerHost = 10; // 增加并发连接数
        configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData; // 强制从网络重新下载
        
        // 使用共享委托的session以节省资源
        NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration 
                                                             delegate:[DYYYManager shared] 
                                                        delegateQueue:[NSOperationQueue mainQueue]];
        
        dispatch_group_t group = dispatch_group_create();
        __block BOOL imageDownloaded = NO;
        __block BOOL videoDownloaded = NO;
        __block float imageProgress = 0.0;
        __block float videoProgress = 0.0;
        
        // 设置单独的下载观察者ID用于进度跟踪
        NSString *imageDownloadID = [NSString stringWithFormat:@"image_%@", uniqueID];
        NSString *videoDownloadID = [NSString stringWithFormat:@"video_%@", uniqueID];
        
        // 更新合并进度的定时器
        __block NSTimer *progressTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer * _Nonnull timer) {
            float totalProgress = (imageProgress + videoProgress) / 2.0;
            [progressView setProgress:totalProgress];
            
            // 更新进度文字
            NSString *statusText = @"正在下载实况照片...";
            if (imageDownloaded && !videoDownloaded) {
                statusText = @"图片下载完成，等待视频...";
            } else if (!imageDownloaded && videoDownloaded) {
                statusText = @"视频下载完成，等待图片...";
            } else if (imageDownloaded && videoDownloaded) {
                statusText = @"下载完成，准备保存...";
                [timer invalidate]; // 全部完成时停止定时器
            }
            progressView.progressLabel.text = statusText;
        }];
        
        // 下载图片
        dispatch_group_enter(group);
        NSURLRequest *imageRequest = [NSURLRequest requestWithURL:imageURL];
        NSURLSessionDataTask *imageTask = [session dataTaskWithRequest:imageRequest completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            if (!error && data) {
                // 直接写入文件，避免临时文件移动操作
                if ([data writeToFile:imagePath atomically:YES]) {
                    imageDownloaded = YES;
                    imageProgress = 1.0;
                }
            }
            dispatch_group_leave(group);
        }];
        
        // 设置图片下载进度观察
        if ([imageTask respondsToSelector:@selector(taskIdentifier)]) {
            [[manager taskProgressMap] setObject:@(0.0) forKey:imageDownloadID];
            
            // 使用系统API观察进度 (iOS 11+)
            if (@available(iOS 11.0, *)) {
                [imageTask.progress addObserver:manager 
                                     forKeyPath:@"fractionCompleted" 
                                        options:NSKeyValueObservingOptionNew 
                                        context:(__bridge void *)(imageDownloadID)];
            }
        }
        
        // 下载视频
        dispatch_group_enter(group);
        NSURLRequest *videoRequest = [NSURLRequest requestWithURL:videoURL];
        NSURLSessionDataTask *videoTask = [session dataTaskWithRequest:videoRequest completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            if (!error && data) {
                // 直接写入文件，避免临时文件移动操作
                if ([data writeToFile:videoPath atomically:YES]) {
                    videoDownloaded = YES;
                    videoProgress = 1.0;
                }
            }
            dispatch_group_leave(group);
        }];
        
        // 设置视频下载进度观察
        if ([videoTask respondsToSelector:@selector(taskIdentifier)]) {
            [[manager taskProgressMap] setObject:@(0.0) forKey:videoDownloadID];
            
            // 使用系统API观察进度 (iOS 11+)
            if (@available(iOS 11.0, *)) {
                [videoTask.progress addObserver:manager 
                                     forKeyPath:@"fractionCompleted" 
                                        options:NSKeyValueObservingOptionNew 
                                        context:(__bridge void *)(videoDownloadID)];
            }
        }
        
        // 设置取消按钮事件
        progressView.cancelBlock = ^{
            [progressTimer invalidate];
            [imageTask cancel];
            [videoTask cancel];
            
            // 移除文件，释放资源
            [[NSFileManager defaultManager] removeItemAtPath:imagePath error:nil];
            [[NSFileManager defaultManager] removeItemAtPath:videoPath error:nil];
            [manager.fileLinks removeObjectForKey:uniqueKey];
            
            // 移除进度观察
            if (@available(iOS 11.0, *)) {
                if ([imageTask respondsToSelector:@selector(progress)]) {
                    [imageTask.progress removeObserver:manager forKeyPath:@"fractionCompleted"];
                }
                if ([videoTask respondsToSelector:@selector(progress)]) {
                    [videoTask.progress removeObserver:manager forKeyPath:@"fractionCompleted"];
                }
            }
            
            if (completion) {
                completion();
            }
        };
        
        // 启动下载任务
        [imageTask resume];
        [videoTask resume];
        
        // 当两个下载都完成后，保存实况照片
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            // 停止进度定时器
            [progressTimer invalidate];
            
            // 移除进度观察
            if (@available(iOS 11.0, *)) {
                if ([imageTask respondsToSelector:@selector(progress)]) {
                    [imageTask.progress removeObserver:manager forKeyPath:@"fractionCompleted"];
                }
                if ([videoTask respondsToSelector:@selector(progress)]) {
                    [videoTask.progress removeObserver:manager forKeyPath:@"fractionCompleted"];
                }
            }
            
            // 检查文件是否真的存在
            BOOL imageExists = [[NSFileManager defaultManager] fileExistsAtPath:imagePath];
            BOOL videoExists = [[NSFileManager defaultManager] fileExistsAtPath:videoPath];
            
            // 隐藏进度视图
            [progressView dismiss];
            
            if (imageExists && videoExists) {
                @try {
                    // 添加iOS版本检查
                    if (@available(iOS 15.0, *)) {
                        [[DYYYManager shared] saveLivePhoto:imagePath videoUrl:videoPath];
                    } else {
                        // iOS 14兼容处理
                        [[DYYYManager shared] saveLivePhotoComponentsForIOS14:imagePath videoPath:videoPath];
                    }
                } @catch (NSException *exception) {
                    // 删除失败的文件
                    [[NSFileManager defaultManager] removeItemAtPath:imagePath error:nil];
                    [[NSFileManager defaultManager] removeItemAtPath:videoPath error:nil];
                    [manager.fileLinks removeObjectForKey:uniqueKey];
                    [DYYYManager showToast:@"保存实况照片失败"];
                }
            } else {
                // 清理不完整的文件
                if (imageExists) [[NSFileManager defaultManager] removeItemAtPath:imagePath error:nil];
                if (videoExists) [[NSFileManager defaultManager] removeItemAtPath:videoPath error:nil];
                [manager.fileLinks removeObjectForKey:uniqueKey];
                [DYYYManager showToast:@"下载实况照片失败"];
            }
            
            if (completion) {
                completion();
            }
        });
    });
}

// ======================================
#pragma mark - 性能优化相关

/// 性能优化：图片解码加速（异步解码，减少主线程卡顿）
+ (UIImage *)decodedImageWithData:(NSData *)data {
    if (!data) return nil;
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!source) return nil;
    CGImageRef imageRef = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    UIImage *image = imageRef ? [UIImage imageWithCGImage:imageRef scale:[UIScreen mainScreen].scale orientation:UIImageOrientationUp] : nil;
    if (imageRef) CGImageRelease(imageRef);
    if (source) CFRelease(source);
    return image;
}

/// 性能优化：批量图片异步预加载
+ (void)preloadImagesWithURLs:(NSArray<NSURL *> *)urls completion:(void (^)(NSArray<UIImage *> *images))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSMutableArray *results = [NSMutableArray arrayWithCapacity:urls.count];
        for (NSURL *url in urls) {
            NSData *data = [NSData dataWithContentsOfURL:url];
            UIImage *img = [self decodedImageWithData:data];
            if (img) [results addObject:img];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(results);
        });
    });
}

#pragma mark - UI动画工具

/// UI动画：弹簧缩放动画
+ (void)animateSpringScale:(UIView *)view {
    view.transform = CGAffineTransformMakeScale(0.8, 0.8);
    [UIView animateWithDuration:0.5
                          delay:0
         usingSpringWithDamping:0.5
          initialSpringVelocity:1.0
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{
        view.transform = CGAffineTransformIdentity;
    } completion:nil];
}

/// UI动画：渐变闪烁
+ (void)animateBlink:(UIView *)view {
    CABasicAnimation *blink = [CABasicAnimation animationWithKeyPath:@"opacity"];
    blink.fromValue = @1.0;
    blink.toValue = @0.2;
    blink.duration = 0.5;
    blink.autoreverses = YES;
    blink.repeatCount = 3;
    [view.layer addAnimation:blink forKey:@"blink"];
}

#pragma mark - 全面格式识别

/// 全面识别图片/视频/动图/表情包/实况等格式，返回格式字符串
+ (NSString *)detectMediaFormat:(NSURL *)fileURL {
    NSData *fileData = [NSData dataWithContentsOfURL:fileURL options:NSDataReadingMappedIfSafe error:nil];
    if (!fileData || fileData.length < 12) return @"unknown";
    const unsigned char *bytes = [fileData bytes];

    // WebP
    if (bytes[0] == 'R' && bytes[1] == 'I' && bytes[2] == 'F' && bytes[3] == 'F' &&
        bytes[8] == 'W' && bytes[9] == 'E' && bytes[10] == 'B' && bytes[11] == 'P') return @"webp";
    // HEIC/HEIF
    if (bytes[4] == 'f' && bytes[5] == 't' && bytes[6] == 'y' && bytes[7] == 'p') {
        if ((bytes[8] == 'h' && bytes[9] == 'e' && bytes[10] == 'i' && bytes[11] == 'c') ||
            (bytes[8] == 'h' && bytes[9] == 'e' && bytes[10] == 'i' && bytes[11] == 'x') ||
            (bytes[8] == 'h' && bytes[9] == 'e' && bytes[10] == 'v' && bytes[11] == 'c') ||
            (bytes[8] == 'h' && bytes[9] == 'e' && bytes[10] == 'v' && bytes[11] == 'x')) return @"heic";
        if ((bytes[8] == 'm' && bytes[9] == 'i' && bytes[10] == 'f' && bytes[11] == '1') ||
            (bytes[8] == 'm' && bytes[9] == 's' && bytes[10] == 'f' && bytes[11] == '1')) return @"heif";
        // MOV/MP4/QuickTime
        if ((bytes[8] == 'q' && bytes[9] == 't' && bytes[10] == ' ' && bytes[11] == ' ')) return @"mov";
        if ((bytes[8] == 'i' && bytes[9] == 's' && bytes[10] == 'o' && bytes[11] == 'm')) return @"mp4";
    }
    // GIF
    if (bytes[0] == 'G' && bytes[1] == 'I' && bytes[2] == 'F') return @"gif";
    // PNG
    if (bytes[0] == 0x89 && bytes[1] == 'P' && bytes[2] == 'N' && bytes[3] == 'G') return @"png";
    // JPEG
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) return @"jpeg";
    // BMP
    if (bytes[0] == 'B' && bytes[1] == 'M') return @"bmp";
    // TIFF
    if ((bytes[0] == 'I' && bytes[1] == 'I') || (bytes[0] == 'M' && bytes[1] == 'M')) return @"tiff";
    // APNG
    if (bytes[0] == 0x89 && bytes[1] == 'P' && bytes[2] == 'N' && bytes[3] == 'G') {
        NSString *dataStr = [[NSString alloc] initWithData:fileData encoding:NSISOLatin1StringEncoding];
        if ([dataStr containsString:@"acTL"]) return @"apng";
    }
    // MP4
    if (fileData.length > 16 &&
        bytes[4] == 'f' && bytes[5] == 't' && bytes[6] == 'y' && bytes[7] == 'p' &&
        ((bytes[8] == 'i' && bytes[9] == 's' && bytes[10] == 'o' && bytes[11] == 'm') ||
         (bytes[8] == 'm' && bytes[9] == 'p' && bytes[10] == '4' && bytes[11] == '2'))) return @"mp4";
    // MOV
    if (fileData.length > 16 &&
        bytes[4] == 'f' && bytes[5] == 't' && bytes[6] == 'y' && bytes[7] == 'p' &&
        (bytes[8] == 'q' && bytes[9] == 't' && bytes[10] == ' ' && bytes[11] == ' ')) return @"mov";
    // 3GP
    if (fileData.length > 16 &&
        bytes[4] == 'f' && bytes[5] == 't' && bytes[6] == 'y' && bytes[7] == 'p' &&
        (bytes[8] == '3' && bytes[9] == 'g' && bytes[10] == 'p')) return @"3gp";
    // AVI
    if (bytes[0] == 'R' && bytes[1] == 'I' && bytes[2] == 'F' && bytes[3] == 'F' &&
        bytes[8] == 'A' && bytes[9] == 'V' && bytes[10] == 'I' && bytes[11] == ' ') return @"avi";
    // MKV
    if (bytes[0] == 0x1A && bytes[1] == 0x45 && bytes[2] == (char)0xDF && bytes[3] == (char)0xA3) return @"mkv";
    // FLV
    if (bytes[0] == 'F' && bytes[1] == 'L' && bytes[2] == 'V') return @"flv";
    // WMV
    if (bytes[0] == 0x30 && bytes[1] == 0x26 && bytes[2] == 0xB2 && bytes[3] == 0x75) return @"wmv";
    // MP3
    if ((bytes[0] == 'I' && bytes[1] == 'D' && bytes[2] == '3') ||
        ((bytes[0] & 0xFF) == 0xFF && (bytes[1] & 0xE0) == 0xE0)) return @"mp3";
    // M4A
    if (fileData.length > 16 &&
        bytes[4] == 'f' && bytes[5] == 't' && bytes[6] == 'y' && bytes[7] == 'p' &&
        (bytes[8] == 'M' && bytes[9] == '4' && bytes[10] == 'A')) return @"m4a";
    // OGG
    if (bytes[0] == 'O' && bytes[1] == 'g' && bytes[2] == 'g' && bytes[3] == 'S') return @"ogg";
    // WEBM
    if (bytes[0] == 0x1A && bytes[1] == 0x45 && bytes[2] == (char)0xDF && bytes[3] == (char)0xA3) return @"webm";
    // APFS表情包（微信/QQ等自定义表情包格式）
    if ([fileURL.lastPathComponent.lowercaseString hasSuffix:@".bq"] ||
        [fileURL.lastPathComponent.lowercaseString hasSuffix:@".face"] ||
        [fileURL.lastPathComponent.lowercaseString hasSuffix:@".sticker"]) return @"sticker";
    // Live Photo（通过伴随的.mov/.mp4和.heic/.jpg判断）
    if ([fileURL.lastPathComponent.lowercaseString hasSuffix:@".mov"] ||
        [fileURL.lastPathComponent.lowercaseString hasSuffix:@".mp4"]) {
        NSURL *imgURL1 = [[fileURL URLByDeletingPathExtension] URLByAppendingPathExtension:@"heic"];
        NSURL *imgURL2 = [[fileURL URLByDeletingPathExtension] URLByAppendingPathExtension:@"jpg"];
        NSString *imgPath1 = imgURL1 ? [imgURL1 path] : nil;
        NSString *imgPath2 = imgURL2 ? [imgURL2 path] : nil;
        if ((imgPath1 && [[NSFileManager defaultManager] fileExistsAtPath:imgPath1]) ||
            (imgPath2 && [[NSFileManager defaultManager] fileExistsAtPath:imgPath2])) return @"livephoto";
    }
    // 其他未知格式
    return @"unknown";
}

/// 判断是否为动图（GIF/APNG/WebP等）
+ (BOOL)isAnimatedImageFormat:(NSString *)format {
    NSArray *animatedFormats = @[@"gif", @"apng", @"webp"];
    return [animatedFormats containsObject:format.lowercaseString];
}

/// 判断是否为表情包格式
+ (BOOL)isStickerFormat:(NSString *)format {
    NSArray *stickerFormats = @[@"sticker", @"bq", @"face"];
    return [stickerFormats containsObject:format.lowercaseString];
}

/// 判断是否为视频格式
+ (BOOL)isVideoFormat:(NSString *)format {
    NSArray *videoFormats = @[@"mp4", @"mov", @"avi", @"mkv", @"flv", @"wmv", @"3gp", @"webm"];
    return [videoFormats containsObject:format.lowercaseString];
}

/// 判断是否为图片格式
+ (BOOL)isImageFormat:(NSString *)format {
    NSArray *imageFormats = @[@"jpeg", @"jpg", @"png", @"bmp", @"tiff", @"heic", @"heif", @"gif", @"apng", @"webp"];
    return [imageFormats containsObject:format.lowercaseString];
}

/// 判断是否为实况图格式
+ (BOOL)isLivePhotoFormat:(NSString *)format {
    return [format.lowercaseString isEqualToString:@"livephoto"];
}

// =======================================

// 需要添加KVO回调方法来处理下载进度
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if ([keyPath isEqualToString:@"fractionCompleted"] && [object isKindOfClass:[NSProgress class]]) {
        NSString *downloadID = (__bridge NSString *)context;
        if (downloadID) {
            NSProgress *progress = (NSProgress *)object;
            float fractionCompleted = progress.fractionCompleted;
            [self.taskProgressMap setObject:@(fractionCompleted) forKey:downloadID];
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

+ (void)downloadMedia:(NSURL *)url mediaType:(MediaType)mediaType completion:(void (^)(void))completion {
    [self downloadMediaWithProgress:url mediaType:mediaType progress:nil completion:^(BOOL success, NSURL *fileURL) {
        if (success) {
            if (mediaType == MediaTypeAudio) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];
                    
                    [activityVC setCompletionWithItemsHandler:^(UIActivityType _Nullable activityType, BOOL completed, NSArray * _Nullable returnedItems, NSError * _Nullable error) {
                        [[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];
                    }];
                    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
                    [rootVC presentViewController:activityVC animated:YES completion:nil];
                });
            } else {
                [self saveMedia:fileURL mediaType:mediaType completion:completion];
            }
        } else {
            if (completion) {
                completion();
            }
        }
    }];
}

+ (void)downloadMediaWithProgress:(NSURL *)url mediaType:(MediaType)mediaType progress:(void (^)(float progress))progressBlock completion:(void (^)(BOOL success, NSURL *fileURL))completion {
    // 创建自定义进度条界面
    dispatch_async(dispatch_get_main_queue(), ^{
        // 创建进度视图
        CGRect screenBounds = [UIScreen mainScreen].bounds;
        DYYYDownloadProgressView *progressView = [[DYYYDownloadProgressView alloc] initWithFrame:screenBounds];
        
        // 生成下载ID并保存进度视图
        NSString *downloadID = [NSUUID UUID].UUIDString;
        [[DYYYManager shared].progressViews setObject:progressView forKey:downloadID];
        
        // 显示进度视图
        [progressView show];
        
        // 设置取消按钮事件
        progressView.cancelBlock = ^{
            NSURLSessionDownloadTask *task = [[DYYYManager shared].downloadTasks objectForKey:downloadID];
            if (task) {
                [task cancel];
                [[DYYYManager shared].downloadTasks removeObjectForKey:downloadID];
                [[DYYYManager shared].taskProgressMap removeObjectForKey:downloadID];
            }
            
            // 已经在取消按钮中隐藏了进度视图，无需再次隐藏
            [[DYYYManager shared].progressViews removeObjectForKey:downloadID];
            
            if (completion) {
                completion(NO, nil);
            }
        };
        
        // 保存回调
        [[DYYYManager shared] setCompletionBlock:completion forDownloadID:downloadID];
        [[DYYYManager shared] setMediaType:mediaType forDownloadID:downloadID];
        
        // 配置下载会话 - 使用带委托的会话以获取进度更新
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration delegate:[DYYYManager shared] delegateQueue:[NSOperationQueue mainQueue]];
        
        // 创建下载任务 - 不使用completionHandler，使用代理方法
        NSURLSessionDownloadTask *downloadTask = [session downloadTaskWithURL:url];
        
        // 存储下载任务
        [[DYYYManager shared].downloadTasks setObject:downloadTask forKey:downloadID];
        [[DYYYManager shared].taskProgressMap setObject:@0.0 forKey:downloadID]; // 初始化进度为0
        
        // 开始下载
        [downloadTask resume];
    });
}

+ (NSString *)getMediaTypeDescription:(MediaType)mediaType {
    switch (mediaType) {
        case MediaTypeVideo:
            return @"视频";
        case MediaTypeImage:
            return @"图片";
        case MediaTypeAudio:
            return @"音频";
        case MediaTypeHeic:
            return @"表情包";
        default:
            return @"文件";
    }
}

// 取消所有下载
+ (void)cancelAllDownloads {
    NSArray *downloadIDs = [[DYYYManager shared].downloadTasks allKeys];
    
    for (NSString *downloadID in downloadIDs) {
        NSURLSessionDownloadTask *task = [[DYYYManager shared].downloadTasks objectForKey:downloadID];
        if (task) {
            [task cancel];
        }
        
        DYYYDownloadProgressView *progressView = [[DYYYManager shared].progressViews objectForKey:downloadID];
        if (progressView) {
            [progressView dismiss];
        }
    }
    
    [[DYYYManager shared].downloadTasks removeAllObjects];
    [[DYYYManager shared].progressViews removeAllObjects];
}

+ (void)downloadAllImages:(NSMutableArray *)imageURLs {
    if (imageURLs.count == 0) {
        return;
    }
    
    [self downloadAllImagesWithProgress:imageURLs progress:nil completion:^(NSInteger successCount, NSInteger totalCount) {
        [self showToast:[NSString stringWithFormat:@"已保存 %ld/%ld 张图片", (long)successCount, (long)totalCount]];
    }];
}

+ (void)downloadAllImagesWithProgress:(NSMutableArray *)imageURLs progress:(void (^)(NSInteger current, NSInteger total))progressBlock completion:(void (^)(NSInteger successCount, NSInteger totalCount))completion {
    if (imageURLs.count == 0) {
        if (completion) {
            completion(0, 0);
        }
        return;
    }
    
    // 创建自定义批量下载进度条界面
    dispatch_async(dispatch_get_main_queue(), ^{
        CGRect screenBounds = [UIScreen mainScreen].bounds;
        DYYYDownloadProgressView *progressView = [[DYYYDownloadProgressView alloc] initWithFrame:screenBounds];
        NSString *batchID = [NSUUID UUID].UUIDString;
        [[DYYYManager shared].progressViews setObject:progressView forKey:batchID];
        
        // 显示进度视图
        [progressView show];
        
        // 创建下载任务
        __block NSInteger completedCount = 0;
        __block NSInteger successCount = 0;
        NSInteger totalCount = imageURLs.count;
        
        // 设置取消按钮事件
        progressView.cancelBlock = ^{
            // 在这里可以添加取消批量下载的逻辑
            [self cancelAllDownloads];
            if (completion) {
                completion(successCount, totalCount);
            }
        };
        
        // 存储批量下载的相关信息
        [[DYYYManager shared] setBatchInfo:batchID totalCount:totalCount progressBlock:progressBlock completionBlock:completion];
        
        // 为每个URL创建下载任务
        for (NSString *urlString in imageURLs) {
            NSURL *url = [NSURL URLWithString:urlString];
            if (!url) {
                [[DYYYManager shared] incrementCompletedAndUpdateProgressForBatch:batchID success:NO];
                continue;
            }
            
            // 创建单个下载任务ID
            NSString *downloadID = [NSUUID UUID].UUIDString;
            
            // 关联到批量下载
            [[DYYYManager shared] associateDownload:downloadID withBatchID:batchID];
            
            // 配置下载会话 - 使用带委托的会话以获取进度更新
            NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
            NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration delegate:[DYYYManager shared] delegateQueue:[NSOperationQueue mainQueue]];
            
            // 创建下载任务 - 使用代理方法
            NSURLSessionDownloadTask *downloadTask = [session downloadTaskWithURL:url];
            
            // 存储下载任务
            [[DYYYManager shared].downloadTasks setObject:downloadTask forKey:downloadID];
            [[DYYYManager shared].taskProgressMap setObject:@0.0 forKey:downloadID];
            [[DYYYManager shared] setMediaType:MediaTypeImage forDownloadID:downloadID];
            
            // 开始下载
            [downloadTask resume];
        }
    });
}

// 设置批量下载信息
- (void)setBatchInfo:(NSString *)batchID totalCount:(NSInteger)totalCount progressBlock:(void (^)(NSInteger current, NSInteger total))progressBlock completionBlock:(void (^)(NSInteger successCount, NSInteger totalCount))completionBlock {
    [self.batchTotalCountMap setObject:@(totalCount) forKey:batchID];
    [self.batchCompletedCountMap setObject:@(0) forKey:batchID];
    [self.batchSuccessCountMap setObject:@(0) forKey:batchID];
    
    if (progressBlock) {
        [self.batchProgressBlocks setObject:[progressBlock copy] forKey:batchID];
    }
    
    if (completionBlock) {
        [self.batchCompletionBlocks setObject:[completionBlock copy] forKey:batchID];
    }
}

// 关联单个下载到批量下载
- (void)associateDownload:(NSString *)downloadID withBatchID:(NSString *)batchID {
    [self.downloadToBatchMap setObject:batchID forKey:downloadID];
}

// 增加批量下载完成计数并更新进度
- (void)incrementCompletedAndUpdateProgressForBatch:(NSString *)batchID success:(BOOL)success {
    @synchronized (self) {
        NSNumber *completedCountNum = self.batchCompletedCountMap[batchID];
        NSInteger completedCount = completedCountNum ? [completedCountNum integerValue] + 1 : 1;
        [self.batchCompletedCountMap setObject:@(completedCount) forKey:batchID];
        
        if (success) {
            NSNumber *successCountNum = self.batchSuccessCountMap[batchID];
            NSInteger successCount = successCountNum ? [successCountNum integerValue] + 1 : 1;
            [self.batchSuccessCountMap setObject:@(successCount) forKey:batchID];
        }
        
        NSNumber *totalCountNum = self.batchTotalCountMap[batchID];
        NSInteger totalCount = totalCountNum ? [totalCountNum integerValue] : 0;
        
        // 更新批量下载进度视图
        DYYYDownloadProgressView *progressView = self.progressViews[batchID];
        if (progressView) {
            float progress = totalCount > 0 ? (float)completedCount / totalCount : 0;
            [progressView setProgress:progress];
            
            // 更新进度标签
            progressView.progressLabel.text = [NSString stringWithFormat:@"%ld/%ld", (long)completedCount, (long)totalCount];
        }
        
        // 调用进度回调
        void (^progressBlock)(NSInteger current, NSInteger total) = self.batchProgressBlocks[batchID];
        if (progressBlock) {
            progressBlock(completedCount, totalCount);
        }
        
        // 如果所有下载都已完成，调用完成回调并清理
        if (completedCount >= totalCount) {
            NSInteger successCount = [self.batchSuccessCountMap[batchID] integerValue];
            
            // 调用完成回调
            void (^completionBlock)(NSInteger successCount, NSInteger totalCount) = self.batchCompletionBlocks[batchID];
            if (completionBlock) {
                completionBlock(successCount, totalCount);
            }
            
            // 移除进度视图
            [progressView dismiss];
            [self.progressViews removeObjectForKey:batchID];
            
            // 清理批量下载相关信息
            [self.batchCompletedCountMap removeObjectForKey:batchID];
            [self.batchSuccessCountMap removeObjectForKey:batchID];
            [self.batchTotalCountMap removeObjectForKey:batchID];
            [self.batchProgressBlocks removeObjectForKey:batchID];
            [self.batchCompletionBlocks removeObjectForKey:batchID];
            
            // 移除关联的下载ID
            NSArray *downloadIDs = [self.downloadToBatchMap allKeysForObject:batchID];
            for (NSString *downloadID in downloadIDs) {
                [self.downloadToBatchMap removeObjectForKey:downloadID];
            }
        }
    }
}

// 保存完成回调
- (void)setCompletionBlock:(void (^)(BOOL success, NSURL *fileURL))completion forDownloadID:(NSString *)downloadID {
    if (completion) {
        [self.completionBlocks setObject:[completion copy] forKey:downloadID];
    }
}

// 保存媒体类型
- (void)setMediaType:(MediaType)mediaType forDownloadID:(NSString *)downloadID {
    [self.mediaTypeMap setObject:@(mediaType) forKey:downloadID];
}

#pragma mark - NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    // 确保不会除以0
    if (totalBytesExpectedToWrite <= 0) {
        return;
    }
    
    // 计算进度
    float progress = (float)totalBytesWritten / totalBytesExpectedToWrite;
    
    // 在主线程更新UI
    dispatch_async(dispatch_get_main_queue(), ^{
        // 找到对应的进度视图
        NSString *downloadIDForTask = nil;
        
        // 遍历找到任务对应的ID
        for (NSString *key in self.downloadTasks.allKeys) {
            NSURLSessionDownloadTask *task = self.downloadTasks[key];
            if (task == downloadTask) {
                downloadIDForTask = key;
                break;
            }
        }
        
        // 如果找到对应的进度视图，更新进度
        if (downloadIDForTask) {
            // 更新进度记录
            [self.taskProgressMap setObject:@(progress) forKey:downloadIDForTask];
            
            DYYYDownloadProgressView *progressView = self.progressViews[downloadIDForTask];
            if (progressView) {
                // 确保进度视图存在并且没有被取消
                if (!progressView.isCancelled) {
                    [progressView setProgress:progress];
                }
            }
        }
    });
}

// 添加下载完成的代理方法
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location {
    // 找到对应的下载ID
    NSString *downloadIDForTask = nil;
    for (NSString *key in self.downloadTasks.allKeys) {
        NSURLSessionDownloadTask *task = self.downloadTasks[key];
        if (task == downloadTask) {
            downloadIDForTask = key;
            break;
        }
    }
    
    if (!downloadIDForTask) {
        return;
    }
    
    // 检查是否属于批量下载
    NSString *batchID = self.downloadToBatchMap[downloadIDForTask];
    BOOL isBatchDownload = (batchID != nil);
    
    // 获取该下载任务的mediaType
    NSNumber *mediaTypeNumber = self.mediaTypeMap[downloadIDForTask];
    MediaType mediaType = MediaTypeImage; // 默认为图片
    if (mediaTypeNumber) {
        mediaType = (MediaType)[mediaTypeNumber integerValue];
    }
    
    // 处理下载的文件
    NSString *fileName = [downloadTask.originalRequest.URL lastPathComponent];
    
    if (!fileName.pathExtension.length) {
        switch (mediaType) {
            case MediaTypeVideo:
                fileName = [fileName stringByAppendingPathExtension:@"mp4"];
                break;
            case MediaTypeImage:
                fileName = [fileName stringByAppendingPathExtension:@"jpg"];
                break;
            case MediaTypeAudio:
                fileName = [fileName stringByAppendingPathExtension:@"mp3"];
                break;
            case MediaTypeHeic:
                fileName = [fileName stringByAppendingPathExtension:@"heic"];
                break;
        }
    }
    
    NSURL *tempDir = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    NSURL *destinationURL = [tempDir URLByAppendingPathComponent:fileName];
    
    NSError *moveError;
    if ([[NSFileManager defaultManager] fileExistsAtPath:destinationURL.path]) {
        [[NSFileManager defaultManager] removeItemAtURL:destinationURL error:nil];
    }
    
    [[NSFileManager defaultManager] moveItemAtURL:location toURL:destinationURL error:&moveError];
    
    if (isBatchDownload) {
        // 批量下载处理
        if (!moveError) {
            [DYYYManager saveMedia:destinationURL mediaType:mediaType completion:^{
                [[DYYYManager shared] incrementCompletedAndUpdateProgressForBatch:batchID success:YES];
            }];
        } else {
            [[DYYYManager shared] incrementCompletedAndUpdateProgressForBatch:batchID success:NO];
        }
        
        // 清理下载任务
        [self.downloadTasks removeObjectForKey:downloadIDForTask];
        [self.taskProgressMap removeObjectForKey:downloadIDForTask];
        [self.mediaTypeMap removeObjectForKey:downloadIDForTask];
    } else {
        // 单个下载处理
        // 获取保存的完成回调
        void (^completionBlock)(BOOL success, NSURL *fileURL) = self.completionBlocks[downloadIDForTask];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            // 隐藏进度视图
            DYYYDownloadProgressView *progressView = self.progressViews[downloadIDForTask];
            BOOL wasCancelled = progressView.isCancelled;
            
            [progressView dismiss];
            [self.progressViews removeObjectForKey:downloadIDForTask];
            [self.downloadTasks removeObjectForKey:downloadIDForTask];
            [self.taskProgressMap removeObjectForKey:downloadIDForTask];
            [self.completionBlocks removeObjectForKey:downloadIDForTask];
            [self.mediaTypeMap removeObjectForKey:downloadIDForTask];
            
            // 如果已取消，直接返回
            if (wasCancelled) {
                return;
            }
            
            if (!moveError) {
                if (completionBlock) {
                    completionBlock(YES, destinationURL);
                }
            } else {
                if (completionBlock) {
                    completionBlock(NO, nil);
                }
            }
        });
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (!error) {
        return; // 成功完成的情况已在didFinishDownloadingToURL处理
    }
    
    // 处理错误情况
    NSString *downloadIDForTask = nil;
    for (NSString *key in self.downloadTasks.allKeys) {
        NSURLSessionTask *existingTask = self.downloadTasks[key];
        if (existingTask == task) {
            downloadIDForTask = key;
            break;
        }
    }
    
    if (!downloadIDForTask) {
        return;
    }
    
    // 检查是否属于批量下载
    NSString *batchID = self.downloadToBatchMap[downloadIDForTask];
    BOOL isBatchDownload = (batchID != nil);
    
    if (isBatchDownload) {
        // 批量下载错误处理
        [[DYYYManager shared] incrementCompletedAndUpdateProgressForBatch:batchID success:NO];
        
        // 清理下载任务
        [self.downloadTasks removeObjectForKey:downloadIDForTask];
        [self.taskProgressMap removeObjectForKey:downloadIDForTask];
        [self.mediaTypeMap removeObjectForKey:downloadIDForTask];
        [self.downloadToBatchMap removeObjectForKey:downloadIDForTask];
    } else {
        // 单个下载错误处理
        void (^completionBlock)(BOOL success, NSURL *fileURL) = self.completionBlocks[downloadIDForTask];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            // 隐藏进度视图
            DYYYDownloadProgressView *progressView = self.progressViews[downloadIDForTask];
            [progressView dismiss];
            
            [self.progressViews removeObjectForKey:downloadIDForTask];
            [self.downloadTasks removeObjectForKey:downloadIDForTask];
            [self.taskProgressMap removeObjectForKey:downloadIDForTask];
            [self.completionBlocks removeObjectForKey:downloadIDForTask];
            [self.mediaTypeMap removeObjectForKey:downloadIDForTask];
            
            if (error.code != NSURLErrorCancelled) {
                [DYYYManager showToast:@"下载失败"];
            }
            
            if (completionBlock) {
                completionBlock(NO, nil);
            }
        });
    }
}

//MARK: 以下都是创建保存实况的调用方法
- (void)saveLivePhoto:(NSString *)imageSourcePath videoUrl:(NSString *)videoSourcePath {
    // 首先检查iOS版本
    if (@available(iOS 15.0, *)) {
        // iOS 15及更高版本使用原有的实现
        NSURL *photoURL = [NSURL fileURLWithPath:imageSourcePath];
        NSURL *videoURL = [NSURL fileURLWithPath:videoSourcePath];
        BOOL available = [PHAssetCreationRequest supportsAssetResourceTypes:@[@(PHAssetResourceTypePhoto), @(PHAssetResourceTypePairedVideo)]];
        if (!available) {
            return;
        }
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
            if (status != PHAuthorizationStatusAuthorized) {
                return;
            }
            NSString *identifier = [NSUUID UUID].UUIDString;
            [self useAssetWriter:photoURL video:videoURL identifier:identifier complete:^(BOOL success, NSString *photoFile, NSString *videoFile, NSError *error) {
                NSURL *photo = [NSURL fileURLWithPath:photoFile];
                NSURL *video = [NSURL fileURLWithPath:videoFile];
                [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                    PHAssetCreationRequest *request = [PHAssetCreationRequest creationRequestForAsset];
                    [request addResourceWithType:PHAssetResourceTypePhoto fileURL:photo options:nil];
                    [request addResourceWithType:PHAssetResourceTypePairedVideo fileURL:video options:nil];
                } completionHandler:^(BOOL success, NSError * _Nullable error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (success) {
                            // 删除临时文件
                            [[NSFileManager defaultManager] removeItemAtPath:imageSourcePath error:nil];
                            [[NSFileManager defaultManager] removeItemAtPath:videoSourcePath error:nil];
                            [[NSFileManager defaultManager] removeItemAtPath:photoFile error:nil];
                            [[NSFileManager defaultManager] removeItemAtPath:videoFile error:nil];
                        } 
                    });
                }];
            }];
        }];
    } else {
        // iOS 14 兼容处理 - 分别保存图片和视频
        dispatch_async(dispatch_get_main_queue(), ^{
            [DYYYManager showToast:@"当前iOS版本不支持实况照片，将分别保存图片和视频"];
            
            // 分别保存图片和视频
            [self saveLivePhotoComponentsForIOS14:imageSourcePath videoPath:videoSourcePath];
        });
    }
}

// 为iOS 14添加的兼容方法，分别保存图片和视频
- (void)saveLivePhotoComponentsForIOS14:(NSString *)imagePath videoPath:(NSString *)videoPath {
    // 保存图片
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        if (status != PHAuthorizationStatusAuthorized) {
            return;
        }
        
        // 先保存图片
        UIImage *image = [UIImage imageWithContentsOfFile:imagePath];
        if (image) {
            [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                [PHAssetChangeRequest creationRequestForAssetFromImage:image];
            } completionHandler:^(BOOL success, NSError * _Nullable error) {
                if (success) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [DYYYManager showToast:@"图片已保存到相册"];
                    });
                }
                
                // 再保存视频
                NSURL *videoURL = [NSURL fileURLWithPath:videoPath];
                [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                    [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:videoURL];
                } completionHandler:^(BOOL success, NSError * _Nullable error) {
                    if (success) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [DYYYManager showToast:@"视频已保存到相册"];
                        });
                    }
                    
                    // 删除临时文件
                    [[NSFileManager defaultManager] removeItemAtPath:imagePath error:nil];
                    [[NSFileManager defaultManager] removeItemAtPath:videoPath error:nil];
                }];
            }];
        }
    }];
}
- (void)useAssetWriter:(NSURL *)photoURL video:(NSURL *)videoURL identifier:(NSString *)identifier complete:(void (^)(BOOL success, NSString *photoFile, NSString *videoFile, NSError *error))complete {
    NSString *photoName = [photoURL lastPathComponent];
    NSString *photoFile = [self filePathFromDoc:photoName];
    [self addMetadataToPhoto:photoURL outputFile:photoFile identifier:identifier];
    NSString *videoName = [videoURL lastPathComponent];
    NSString *videoFile = [self filePathFromDoc:videoName];
    [self addMetadataToVideo:videoURL outputFile:videoFile identifier:identifier];
    if (!DYYYManager.shared->group) return;
    dispatch_group_notify(DYYYManager.shared->group, dispatch_get_main_queue(), ^{
        [self finishWritingTracksWithPhoto:photoFile video:videoFile complete:complete];
    });
}
- (void)finishWritingTracksWithPhoto:(NSString *)photoFile video:(NSString *)videoFile complete:(void (^)(BOOL success, NSString *photoFile, NSString *videoFile, NSError *error))complete {
    [DYYYManager.shared->reader cancelReading];
    [DYYYManager.shared->writer finishWritingWithCompletionHandler:^{
        if (complete) complete(YES, photoFile, videoFile, nil);
    }];
}
- (void)addMetadataToPhoto:(NSURL *)photoURL outputFile:(NSString *)outputFile identifier:(NSString *)identifier {
    NSMutableData *data = [NSData dataWithContentsOfURL:photoURL].mutableCopy;
    UIImage *image = [UIImage imageWithData:data];
    CGImageRef imageRef = image.CGImage;
    NSDictionary *imageMetadata = @{(NSString *)kCGImagePropertyMakerAppleDictionary : @{@"17" : identifier}};
    CGImageDestinationRef dest = CGImageDestinationCreateWithData((CFMutableDataRef)data, kUTTypeJPEG, 1, nil);
    CGImageDestinationAddImage(dest, imageRef, (CFDictionaryRef)imageMetadata);
    CGImageDestinationFinalize(dest);
    [data writeToFile:outputFile atomically:YES];
}

- (void)addMetadataToVideo:(NSURL *)videoURL outputFile:(NSString *)outputFile identifier:(NSString *)identifier {
    NSError *error = nil;
    AVAsset *asset = [AVAsset assetWithURL:videoURL];
    AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:asset error:&error];
    if (error) {
        return;
    }
    NSMutableArray<AVMetadataItem *> *metadata = asset.metadata.mutableCopy;
    AVMetadataItem *item = [self createContentIdentifierMetadataItem:identifier];
    [metadata addObject:item];
    NSURL *videoFileURL = [NSURL fileURLWithPath:outputFile];
    [self deleteFile:outputFile];
    AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:videoFileURL fileType:AVFileTypeQuickTimeMovie error:&error];
    if (error) {
        return;
    }
    [writer setMetadata:metadata];
    NSArray<AVAssetTrack *> *tracks = [asset tracks];
    for (AVAssetTrack *track in tracks) {
        NSDictionary *readerOutputSettings = nil;
        NSDictionary *writerOuputSettings = nil;
        if ([track.mediaType isEqualToString:AVMediaTypeAudio]) {
            readerOutputSettings = @{AVFormatIDKey : @(kAudioFormatLinearPCM)};
            writerOuputSettings = @{AVFormatIDKey : @(kAudioFormatMPEG4AAC),
                                    AVSampleRateKey : @(44100),
                                    AVNumberOfChannelsKey : @(2),
                                    AVEncoderBitRateKey : @(128000)};
        }
        AVAssetReaderTrackOutput *output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:readerOutputSettings];
        AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:track.mediaType outputSettings:writerOuputSettings];
        if ([reader canAddOutput:output] && [writer canAddInput:input]) {
            [reader addOutput:output];
            [writer addInput:input];
        }
    }
    AVAssetWriterInput *input = [self createStillImageTimeAssetWriterInput];
    AVAssetWriterInputMetadataAdaptor *adaptor = [AVAssetWriterInputMetadataAdaptor assetWriterInputMetadataAdaptorWithAssetWriterInput:input];
    if ([writer canAddInput:input]) {
        [writer addInput:input];
    }
    [writer startWriting];
    [writer startSessionAtSourceTime:kCMTimeZero];
    [reader startReading];
    AVMetadataItem *timedItem = [self createStillImageTimeMetadataItem];
    CMTimeRange timedRange = CMTimeRangeMake(kCMTimeZero, CMTimeMake(1, 100));
    AVTimedMetadataGroup *timedMetadataGroup = [[AVTimedMetadataGroup alloc] initWithItems:@[timedItem] timeRange:timedRange];
    [adaptor appendTimedMetadataGroup:timedMetadataGroup];
    DYYYManager.shared->reader = reader;
    DYYYManager.shared->writer = writer;
    DYYYManager.shared->queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    DYYYManager.shared->group = dispatch_group_create();
    for (NSInteger i = 0; i < reader.outputs.count; ++i) {
        dispatch_group_enter(DYYYManager.shared->group);
        [self writeTrack:i];
    }
}

- (void)writeTrack:(NSInteger)trackIndex {
    AVAssetReaderOutput *output = DYYYManager.shared->reader.outputs[trackIndex];
    AVAssetWriterInput *input = DYYYManager.shared->writer.inputs[trackIndex];
    
    [input requestMediaDataWhenReadyOnQueue:DYYYManager.shared->queue usingBlock:^{
        while (input.readyForMoreMediaData) {
            AVAssetReaderStatus status = DYYYManager.shared->reader.status;
            CMSampleBufferRef buffer = NULL;
            if ((status == AVAssetReaderStatusReading) &&
                (buffer = [output copyNextSampleBuffer])) {
                BOOL success = [input appendSampleBuffer:buffer];
                CFRelease(buffer);
                if (!success) {
                   
                    [input markAsFinished];
                    dispatch_group_leave(DYYYManager.shared->group);
                    return;
                }
            } else {
                if (status == AVAssetReaderStatusReading) {
                   
                } else if (status == AVAssetReaderStatusCompleted) {
                   
                } else if (status == AVAssetReaderStatusCancelled) {
                   
                } else if (status == AVAssetReaderStatusFailed) {
                   
                }
                [input markAsFinished];
                dispatch_group_leave(DYYYManager.shared->group);
                return;
            }
        }
    }];
}
- (AVMetadataItem *)createContentIdentifierMetadataItem:(NSString *)identifier {
    AVMutableMetadataItem *item = [AVMutableMetadataItem metadataItem];
    item.keySpace = AVMetadataKeySpaceQuickTimeMetadata;
    item.key = AVMetadataQuickTimeMetadataKeyContentIdentifier;
    item.value = identifier;
    return item;
}

- (AVAssetWriterInput *)createStillImageTimeAssetWriterInput {
    NSArray *spec = @[@{(NSString *)kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier : @"mdta/com.apple.quicktime.still-image-time",
                        (NSString *)kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType : (NSString *)kCMMetadataBaseDataType_SInt8 }];
    CMFormatDescriptionRef desc = NULL;
    CMMetadataFormatDescriptionCreateWithMetadataSpecifications(kCFAllocatorDefault, kCMMetadataFormatType_Boxed, (__bridge CFArrayRef)spec, &desc);
    AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeMetadata outputSettings:nil sourceFormatHint:desc];
    return input;
}

- (AVMetadataItem *)createStillImageTimeMetadataItem {
    AVMutableMetadataItem *item = [AVMutableMetadataItem metadataItem];
    item.keySpace = AVMetadataKeySpaceQuickTimeMetadata;
    item.key = @"com.apple.quicktime.still-image-time";
    item.value = @(-1);
    item.dataType = (NSString *)kCMMetadataBaseDataType_SInt8;
    return item;
}
- (NSString *)filePathFromDoc:(NSString *)filename {
    NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *filePath = [docPath stringByAppendingPathComponent:filename];
    return filePath;
}

- (void)deleteFile:(NSString *)file {
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:file]) {
        [fm removeItemAtPath:file error:nil];
    }
}

+ (void)downloadAllLivePhotos:(NSArray<NSDictionary *> *)livePhotos {
    if (livePhotos.count == 0) {
        return;
    }
    
    [self downloadAllLivePhotosWithProgress:livePhotos progress:nil completion:^(NSInteger successCount, NSInteger totalCount) {
        [self showToast:[NSString stringWithFormat:@"已保存 %ld/%ld 个实况照片", (long)successCount, (long)totalCount]];
    }];
}

+ (void)downloadAllLivePhotosWithProgress:(NSArray<NSDictionary *> *)livePhotos progress:(void (^)(NSInteger current, NSInteger total))progressBlock completion:(void (^)(NSInteger successCount, NSInteger totalCount))completion {
    if (livePhotos.count == 0) {
        if (completion) {
            completion(0, 0);
        }
        return;
    }
    
    // 检查iOS版本
    BOOL supportsLivePhoto = NO;
    if (@available(iOS 15.0, *)) {
        supportsLivePhoto = YES;
    }
    
    if (!supportsLivePhoto) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [DYYYManager showToast:@"当前iOS版本不完全支持实况照片，将分别保存图片和视频"];
        });
    }
    
    // 创建自定义批量下载进度条界面
    dispatch_async(dispatch_get_main_queue(), ^{
        CGRect screenBounds = [UIScreen mainScreen].bounds;
        DYYYDownloadProgressView *progressView = [[DYYYDownloadProgressView alloc] initWithFrame:screenBounds];
        progressView.progressLabel.text = @"准备下载实况照片...";
        [progressView show];
        
        NSString *batchID = [NSUUID UUID].UUIDString;
        
        // 设置取消按钮事件
        progressView.cancelBlock = ^{
            [DYYYManager cancelAllDownloads];
            if (completion) {
                completion(0, livePhotos.count);
            }
        };
        
        // 创建下载任务
        __block NSInteger completedCount = 0;
        __block NSInteger successCount = 0;
        NSInteger totalCount = livePhotos.count;
        
        // 为每个实况照片创建下载任务
        for (NSInteger index = 0; index < livePhotos.count; index++) {
            NSDictionary *livePhoto = livePhotos[index];
            NSURL *imageURL = [NSURL URLWithString:livePhoto[@"imageURL"]];
            NSURL *videoURL = [NSURL URLWithString:livePhoto[@"videoURL"]];
            
            if (!imageURL || !videoURL) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completedCount++;
                    float progress = (float)completedCount / totalCount;
                    [progressView setProgress:progress];
                    progressView.progressLabel.text = [NSString stringWithFormat:@"进度: %ld/%ld", (long)completedCount, (long)totalCount];
                    
                    if (progressBlock) {
                        progressBlock(completedCount, totalCount);
                    }
                    
                    if (completedCount >= totalCount) {
                        [progressView dismiss];
                        if (completion) {
                            completion(successCount, totalCount);
                        }
                    }
                });
                continue;
            }
            
            // 延迟启动每个下载，避免同时发起大量网络请求
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, index * 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [self downloadLivePhoto:imageURL videoURL:videoURL completion:^{
                    dispatch_async(dispatch_get_main_queue(), ^{
                        successCount++;
                        completedCount++;
                        
                        float progress = (float)completedCount / totalCount;
                        [progressView setProgress:progress];
                        progressView.progressLabel.text = [NSString stringWithFormat:@"进度: %ld/%ld", (long)completedCount, (long)totalCount];
                        
                        if (progressBlock) {
                            progressBlock(completedCount, totalCount);
                        }
                        
                        if (completedCount >= totalCount) {
                            [progressView dismiss];
                            if (completion) {
                                completion(successCount, totalCount);
                            }
                        }
                    });
                }];
            });
        }
    });
}

+ (BOOL)isDarkMode {
    return [NSClassFromString(@"AWEUIThemeManager") isLightTheme] ? NO : YES;
}

// 辅助方法用于将 UIImage 转换为 HEIC 格式的 NSData
+ (NSData *)heicDataFromImage:(UIImage *)image quality:(CGFloat)quality {
    if (@available(iOS 11.0, *)) {
        NSDictionary *options = @{(NSString *)kCGImageDestinationLossyCompressionQuality: @(quality)};
        return [self dataWithImage:image format:@"public.heic" options:options];
    }
    return UIImageJPEGRepresentation(image, quality); // iOS 11以下使用JPEG格式降级
}

+ (NSData *)dataWithImage:(UIImage *)image format:(NSString *)format options:(NSDictionary *)options {
    NSMutableData *data = [NSMutableData data];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data, (__bridge CFStringRef)format, 1, NULL);
    if (!destination) {
        return nil;
    }
    
    CGImageDestinationAddImage(destination, image.CGImage, (__bridge CFDictionaryRef)options);
    if (!CGImageDestinationFinalize(destination)) {
        CFRelease(destination);
        return nil;
    }
    CFRelease(destination);
    return data;
}

- (void)saveHeicImageWithURL:(NSURL *)url completion:(void (^)(void))completion {
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (!data) {
        [DYYYManager showToast:@"无法下载图片"];
        return;
    }
    
    UIImage *image = [UIImage imageWithData:data];
    if (!image) {
        [DYYYManager showToast:@"图片解码失败"];
        return;
    }
    
    // 辅助方法
    NSData *heicData = [DYYYManager heicDataFromImage:image quality:0.9];
    if ([heicData length] > 0) {
        // 保存到相册
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            [PHAssetChangeRequest creationRequestForAssetFromImage:[UIImage imageWithData:heicData]];
        } completionHandler:^(BOOL success, NSError * _Nullable error) {
            if (success) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [DYYYManager showToast:@"图片已保存到相册"];
                });
            } else {
                [DYYYManager showToast:@"保存失败"];
            }
            if (completion) {
                completion();
            }
        }];
    }
}

+ (void)saveImageToPhotosAlbum:(UIImage *)image quality:(CGFloat)quality completion:(void (^)(BOOL))completion {
    NSData *imageData = nil;
    
    // 修改这里，使用我们的辅助方法
    imageData = [DYYYManager heicDataFromImage:image quality:quality];
    
    if ([imageData length] > 0) {
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            [PHAssetChangeRequest creationRequestForAssetFromImage:[UIImage imageWithData:imageData]];
        } completionHandler:^(BOOL success, NSError * _Nullable error) {
            if (completion) {
                completion(success);
            }
        }];
    } else {
        if (completion) {
            completion(NO);
        }
    }
}

+ (void)handleImageResult:(UIImage *)image completion:(void (^)(void))completion {
    CGFloat quality = 0.9;
    NSData *imageData;
    
    // 辅助方法
    imageData = [DYYYManager heicDataFromImage:image quality:quality];
    
    if ([imageData length] > 0) {
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            [PHAssetChangeRequest creationRequestForAssetFromImage:[UIImage imageWithData:imageData]];
        } completionHandler:^(BOOL success, NSError * _Nullable error) {
            if (success) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [DYYYManager showToast:@"图片已保存到相册"];
                });
            } else {
                [DYYYManager showToast:@"保存失败"];
            }
            if (completion) {
                completion();
            }
        }];
    }
}

+ (void)parseAndDownloadVideoWithShareLink:(NSString *)shareLink apiKey:(NSString *)apiKey {
	if (shareLink.length == 0 || apiKey.length == 0) {
		[self showToast:@"分享链接或API密钥无效"];
		return;
	}

	NSString *apiUrl = [NSString stringWithFormat:@"%@%@", apiKey, [shareLink stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
	[self showToast:@"正在通过接口解析..."];

	NSURL *url = [NSURL URLWithString:apiUrl];
	NSURLRequest *request = [NSURLRequest requestWithURL:url];
	NSURLSession *session = [NSURLSession sharedSession];

	NSURLSessionDataTask *dataTask = [session
	    dataTaskWithRequest:request
	      completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
		  if (error) {
			  [self showToast:[NSString stringWithFormat:@"接口请求失败: %@", error.localizedDescription]];
			  return;
		  }

		  NSError *jsonError;
		  NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
		  if (jsonError) {
			  [self showToast:@"解析接口返回数据失败"];
			  return;
		  }

		  NSInteger code = [json[@"code"] integerValue];
		  if (code != 0 && code != 200) {
			  [self showToast:[NSString stringWithFormat:@"接口返回错误: %@", json[@"msg"] ?: @"未知错误"]];
			  return;
		  }

		  NSDictionary *dataDict = json[@"data"];
		  if (!dataDict) {
			  [self showToast:@"接口返回数据为空"];
			  return;
		  }

		  NSArray *videos = dataDict[@"videos"];
		  NSArray *images = dataDict[@"images"];
		  NSArray *videoList = dataDict[@"video_list"];
		  BOOL hasVideos = [videos isKindOfClass:[NSArray class]] && videos.count > 0;
		  BOOL hasImages = [images isKindOfClass:[NSArray class]] && images.count > 0;
		  BOOL hasVideoList = [videoList isKindOfClass:[NSArray class]] && videoList.count > 0;
		  BOOL shouldShowQualityOptions = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYShowAllVideoQuality"];

		  // 如果启用了显示清晰度选项并且存在 videoList，或者原本就需要显示清晰度选项
		  if ((shouldShowQualityOptions && hasVideoList) || (!hasVideos && !hasImages && hasVideoList)) {
			  AWEUserActionSheetView *actionSheet = [[NSClassFromString(@"AWEUserActionSheetView") alloc] init];
			  NSMutableArray *actions = [NSMutableArray array];

			  for (NSDictionary *videoDict in videoList) {
				  NSString *url = videoDict[@"url"];
				  NSString *level = videoDict[@"level"];
				  if (url.length > 0 && level.length > 0) {
					  AWEUserSheetAction *qualityAction = [NSClassFromString(@"AWEUserSheetAction")
					      actionWithTitle:level
						      imgName:nil
						      handler:^{
							NSURL *videoDownloadUrl = [NSURL URLWithString:url];
							[self downloadMedia:videoDownloadUrl
								  mediaType:MediaTypeVideo
								 completion:^{
								   [self showToast:[NSString stringWithFormat:@"视频已保存到相册 (%@)", level]];
								 }];
						      }];
					  [actions addObject:qualityAction];
				  }
			  }

			  // 如果用户选择了显示清晰度选项，并且有视频和图片需要下载，添加一个批量下载选项
			  if (shouldShowQualityOptions && (hasVideos || hasImages)) {
				  AWEUserSheetAction *batchDownloadAction = [NSClassFromString(@"AWEUserSheetAction") actionWithTitle:@"批量下载所有资源"
															      imgName:nil
															      handler:^{
																// 执行批量下载
																[self batchDownloadResources:videos images:images];
															      }];
				  [actions addObject:batchDownloadAction];
			  }

			  if (actions.count > 0) {
				  [actionSheet setActions:actions];
				  [actionSheet show];
				  return;
			  }
		  }

		  // 如果显示清晰度选项但是没有videoList，并且有videos数组（多个视频）
		  if (shouldShowQualityOptions && !hasVideoList && hasVideos && videos.count > 1) {
			  AWEUserActionSheetView *actionSheet = [[NSClassFromString(@"AWEUserActionSheetView") alloc] init];
			  NSMutableArray *actions = [NSMutableArray array];

			  for (NSInteger i = 0; i < videos.count; i++) {
				  NSDictionary *videoDict = videos[i];
				  NSString *videoUrl = videoDict[@"url"];
				  NSString *desc = videoDict[@"desc"] ?: [NSString stringWithFormat:@"视频 %ld", (long)(i + 1)];

				  if (videoUrl.length > 0) {
					  AWEUserSheetAction *videoAction = [NSClassFromString(@"AWEUserSheetAction")
					      actionWithTitle:[NSString stringWithFormat:@"%@", desc]
						      imgName:nil
						      handler:^{
							NSURL *videoDownloadUrl = [NSURL URLWithString:videoUrl];
							[self downloadMedia:videoDownloadUrl
								  mediaType:MediaTypeVideo
								 completion:^{
								   [self showToast:[NSString stringWithFormat:@"视频已保存到相册"]];
								 }];
						      }];
					  [actions addObject:videoAction];
				  }
			  }

			  AWEUserSheetAction *batchDownloadAction = [NSClassFromString(@"AWEUserSheetAction") actionWithTitle:@"批量下载所有资源"
														      imgName:nil
														      handler:^{
															// 执行批量下载
															[self batchDownloadResources:videos images:images];
														      }];
			  [actions addObject:batchDownloadAction];

			  if (actions.count > 0) {
				  [actionSheet setActions:actions];
				  [actionSheet show];
				  return;
			  }
		  }

		  // 如果没有视频或图片数组，但有单个视频URL
		  if (!hasVideos && !hasImages && !hasVideoList) {
			  NSString *videoUrl = dataDict[@"url"];
			  if (videoUrl.length > 0) {
				  [self showToast:@"开始下载单个视频..."];
				  NSURL *videoDownloadUrl = [NSURL URLWithString:videoUrl];
				  [self downloadMedia:videoDownloadUrl
					    mediaType:MediaTypeVideo
					   completion:^{
					     [self showToast:@"视频已保存到相册"];
					   }];
			  } else {
				  [self showToast:@"接口未返回有效的视频链接"];
			  }
			  return;
		  }

		  [self batchDownloadResources:videos images:images];
		});
	      }];

	[dataTask resume];
}

+ (void)batchDownloadResources:(NSArray *)videos images:(NSArray *)images {
	BOOL hasVideos = [videos isKindOfClass:[NSArray class]] && videos.count > 0;
	BOOL hasImages = [images isKindOfClass:[NSArray class]] && images.count > 0;

	NSMutableArray<id> *videoFiles = [NSMutableArray arrayWithCapacity:videos.count];
	NSMutableArray<id> *imageFiles = [NSMutableArray arrayWithCapacity:images.count];
	for (NSInteger i = 0; i < videos.count; i++)
		[videoFiles addObject:[NSNull null]];
	for (NSInteger i = 0; i < images.count; i++)
		[imageFiles addObject:[NSNull null]];

	dispatch_group_t downloadGroup = dispatch_group_create();
	__block NSInteger totalDownloads = 0;
	__block NSInteger completedDownloads = 0;

	if (hasVideos) {
		totalDownloads += videos.count;
		for (NSInteger i = 0; i < videos.count; i++) {
			NSDictionary *videoDict = videos[i];
			NSString *videoUrl = videoDict[@"url"];
			if (videoUrl.length == 0) {
				completedDownloads++;
				continue;
			}
			dispatch_group_enter(downloadGroup);
			NSURL *videoDownloadUrl = [NSURL URLWithString:videoUrl];
			[self downloadMediaWithProgress:videoDownloadUrl
					      mediaType:MediaTypeVideo
					       progress:nil
					     completion:^(BOOL success, NSURL *fileURL) {
					       if (success && fileURL) {
						       @synchronized(videoFiles) {
							       videoFiles[i] = fileURL;
						       }
					       }
					       completedDownloads++;
					       dispatch_group_leave(downloadGroup);
					     }];
		}
	}

	if (hasImages) {
		totalDownloads += images.count;
		for (NSInteger i = 0; i < images.count; i++) {
			NSString *imageUrl = images[i];
			if (imageUrl.length == 0) {
				completedDownloads++;
				continue;
			}
			dispatch_group_enter(downloadGroup);
			NSURL *imageDownloadUrl = [NSURL URLWithString:imageUrl];
			[self downloadMediaWithProgress:imageDownloadUrl
					      mediaType:MediaTypeImage
					       progress:nil
					     completion:^(BOOL success, NSURL *fileURL) {
					       if (success && fileURL) {
						       @synchronized(imageFiles) {
							       imageFiles[i] = fileURL;
						       }
					       }
					       completedDownloads++;
					       dispatch_group_leave(downloadGroup);
					     }];
		}
	}

	dispatch_group_notify(downloadGroup, dispatch_get_main_queue(), ^{
	  if (completedDownloads < totalDownloads) {
		  [self showToast:@"部分下载失败"];
	  }

	  NSInteger videoSuccessCount = 0;
	  for (id file in videoFiles) {
		  if ([file isKindOfClass:[NSURL class]]) {
			  [self saveMedia:(NSURL *)file mediaType:MediaTypeVideo completion:nil];
			  videoSuccessCount++;
		  }
	  }

	  NSInteger imageSuccessCount = 0;
	  for (id file in imageFiles) {
		  if ([file isKindOfClass:[NSURL class]]) {
			  [self saveMedia:(NSURL *)file mediaType:MediaTypeImage completion:nil];
			  imageSuccessCount++;
		  }
	  }

	  NSString *toastMessage;
	  if (hasVideos && hasImages) {
		  toastMessage = [NSString stringWithFormat:@"已保存 %ld/%ld 个视频和 %ld/%ld 张图片", (long)videoSuccessCount, (long)videos.count, (long)imageSuccessCount, (long)images.count];
	  } else if (hasVideos) {
		  toastMessage = [NSString stringWithFormat:@"已保存 %ld/%ld 个视频", (long)videoSuccessCount, (long)videos.count];
	  } else if (hasImages) {
		  toastMessage = [NSString stringWithFormat:@"已保存 %ld/%ld 张图片", (long)imageSuccessCount, (long)images.count];
	  }
	  [self showToast:toastMessage];
	});
}

@end
