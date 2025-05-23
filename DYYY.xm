#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <CoreLocation/CoreLocation.h> 
#import "CityManager.h"
#import "AwemeHeaders.h"
#import "DYYYManager.h"
#import "DYYYSettingViewController.h"

// 添加自定义函数声明
static void DYYYAddCustomViewToParent(UIView *view, CGFloat transparency) {
    if (!view) return;
    
    // 设置视图的背景色透明度
    if (view.backgroundColor) {
        CGFloat red, green, blue, alpha;
        [view.backgroundColor getRed:&red green:&green blue:&blue alpha:&alpha];
        view.backgroundColor = [UIColor colorWithRed:red green:green blue:blue alpha:transparency];
    }
    
    // 递归处理子视图
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:[UIImageView class]] || 
            [subview isKindOfClass:[UILabel class]] ||
            [subview isKindOfClass:[UIButton class]]) {
            continue;  // 跳过某些特定类型的视图
        }
        DYYYAddCustomViewToParent(subview, transparency);
    }
}


@interface CityManager (DYYYExt)
- (NSString *)generateRandomFourLevelAddressForCityCode:(NSString *)cityCode;
@end

#define DYYYMediaTypeVideo MediaTypeVideo
#define DYYYMediaTypeImage MediaTypeImage
#define DYYYMediaTypeAudio MediaTypeAudio
#define DYYYMediaTypeHeic MediaTypeHeic

%hook AWEAwemePlayVideoViewController

- (void)setIsAutoPlay:(BOOL)arg0 {
    float defaultSpeed = [[NSUserDefaults standardUserDefaults] floatForKey:@"DYYYDefaultSpeed"];
    
    if (defaultSpeed > 0 && defaultSpeed != 1) {
        [self setVideoControllerPlaybackRate:defaultSpeed];
    }
    
    %orig(arg0);
}

%end


%hook AWENormalModeTabBarGeneralPlusButton
+ (id)button {
    BOOL isHiddenJia = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisHiddenJia"];
    if (isHiddenJia) {
        return nil;
    }
    return %orig;
}
%end

%hook AWEFeedContainerContentView
- (void)setAlpha:(CGFloat)alpha {
	// 纯净模式功能
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisEnablePure"]) {
		%orig(0.0);

		static dispatch_source_t timer = nil;
		static int attempts = 0;

		if (timer) {
			dispatch_source_cancel(timer);
			timer = nil;
		}

		void (^tryFindAndSetPureMode)(void) = ^{
		  UIWindow *keyWindow = [DYYYManager getActiveWindow];

		  if (keyWindow && keyWindow.rootViewController) {
			  UIViewController *feedVC = [self findViewController:keyWindow.rootViewController ofClass:NSClassFromString(@"AWEFeedTableViewController")];
			  if (feedVC) {
				  [feedVC setValue:@YES forKey:@"pureMode"];
				  if (timer) {
					  dispatch_source_cancel(timer);
					  timer = nil;
				  }
				  attempts = 0;
				  return;
			  }
		  }

		  attempts++;
		  if (attempts >= 10) {
			  if (timer) {
				  dispatch_source_cancel(timer);
				  timer = nil;
			  }
			  attempts = 0;
		  }
		};

		timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
		dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC, 0);
		dispatch_source_set_event_handler(timer, tryFindAndSetPureMode);
		dispatch_resume(timer);

		tryFindAndSetPureMode();
		return;
	}

	// 原来的透明度设置逻辑，保持不变
	NSString *transparentValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYtopbartransparent"];
	if (transparentValue && transparentValue.length > 0) {
		CGFloat alphaValue = [transparentValue floatValue];
		if (alphaValue >= 0.0 && alphaValue <= 1.0) {
			%orig(alphaValue);
		} else {
			%orig(1.0);
		}
	} else {
		%orig(1.0);
	}
}

%new
- (UIViewController *)findViewController:(UIViewController *)vc ofClass:(Class)targetClass {
	if (!vc)
		return nil;
	if ([vc isKindOfClass:targetClass])
		return vc;

	for (UIViewController *childVC in vc.childViewControllers) {
		UIViewController *found = [self findViewController:childVC ofClass:targetClass];
		if (found)
			return found;
	}

	return [self findViewController:vc.presentedViewController ofClass:targetClass];
}
%end

// 添加新的 hook 来处理顶栏透明度
%hook AWEFeedTopBarContainer
- (void)layoutSubviews {
	%orig;
	[self applyDYYYTransparency];
}
- (void)didMoveToSuperview {
	%orig;
	[self applyDYYYTransparency];
}
%new
- (void)applyDYYYTransparency {
	// 如果启用了纯净模式，不做任何处理
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisEnablePure"]) {
		return;
	}

	NSString *transparentValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYtopbartransparent"];
	if (transparentValue && transparentValue.length > 0) {
		CGFloat alphaValue = [transparentValue floatValue];
		if (alphaValue >= 0.0 && alphaValue <= 1.0) {
			// 设置自身背景色的透明度
			UIColor *backgroundColor = self.backgroundColor;
			if (backgroundColor) {
				CGFloat r, g, b, a;
				if ([backgroundColor getRed:&r green:&g blue:&b alpha:&a]) {
					self.backgroundColor = [UIColor colorWithRed:r green:g blue:b alpha:alphaValue * a];
				}
			}

			// 使用类型转换确保编译器知道这是一个 UIView
			[(UIView *)self setAlpha:alphaValue];

			// 确保子视图不会叠加透明度
			for (UIView *subview in self.subviews) {
				subview.alpha = 1.0;
			}
		}
	}
}
%end

%hook AWEDanmakuContentLabel
- (void)setTextColor:(UIColor *)textColor {
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYEnableDanmuColor"]) {
		NSString *danmuColor = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYdanmuColor"];

		if ([danmuColor.lowercaseString isEqualToString:@"random"] || [danmuColor.lowercaseString isEqualToString:@"#random"]) {
			textColor = [UIColor colorWithRed:(arc4random_uniform(256)) / 255.0
						    green:(arc4random_uniform(256)) / 255.0
						     blue:(arc4random_uniform(256)) / 255.0
						    alpha:CGColorGetAlpha(textColor.CGColor)];
			self.layer.shadowOffset = CGSizeZero;
			self.layer.shadowOpacity = 0.0;
		} else if ([danmuColor hasPrefix:@"#"]) {
			textColor = [self colorFromHexString:danmuColor baseColor:textColor];
			self.layer.shadowOffset = CGSizeZero;
			self.layer.shadowOpacity = 0.0;
		} else {
			textColor = [self colorFromHexString:@"#FFFFFF" baseColor:textColor];
		}
	}

	%orig(textColor);
}

%new
- (UIColor *)colorFromHexString:(NSString *)hexString baseColor:(UIColor *)baseColor {
	if ([hexString hasPrefix:@"#"]) {
		hexString = [hexString substringFromIndex:1];
	}
	if ([hexString length] != 6) {
		return [baseColor colorWithAlphaComponent:1];
	}
	unsigned int red, green, blue;
	[[NSScanner scannerWithString:[hexString substringWithRange:NSMakeRange(0, 2)]] scanHexInt:&red];
	[[NSScanner scannerWithString:[hexString substringWithRange:NSMakeRange(2, 2)]] scanHexInt:&green];
	[[NSScanner scannerWithString:[hexString substringWithRange:NSMakeRange(4, 2)]] scanHexInt:&blue];

	if (red < 128 && green < 128 && blue < 128) {
		return [UIColor whiteColor];
	}

	return [UIColor colorWithRed:(red / 255.0) green:(green / 255.0) blue:(blue / 255.0) alpha:CGColorGetAlpha(baseColor.CGColor)];
}
%end

%hook AWEDanmakuItemTextInfo
- (void)setDanmakuTextColor:(id)arg1 {

	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYEnableDanmuColor"]) {
		NSString *danmuColor = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYdanmuColor"];

		if ([danmuColor.lowercaseString isEqualToString:@"random"] || [danmuColor.lowercaseString isEqualToString:@"#random"]) {
			arg1 = [UIColor colorWithRed:(arc4random_uniform(256)) / 255.0 green:(arc4random_uniform(256)) / 255.0 blue:(arc4random_uniform(256)) / 255.0 alpha:1.0];
		} else if ([danmuColor hasPrefix:@"#"]) {
			arg1 = [self colorFromHexStringForTextInfo:danmuColor];
		} else {
			arg1 = [self colorFromHexStringForTextInfo:@"#FFFFFF"];
		}
	}

	%orig(arg1);
}

%new
- (UIColor *)colorFromHexStringForTextInfo:(NSString *)hexString {
	if ([hexString hasPrefix:@"#"]) {
		hexString = [hexString substringFromIndex:1];
	}
	if ([hexString length] != 6) {
		return [UIColor whiteColor];
	}
	unsigned int red, green, blue;
	[[NSScanner scannerWithString:[hexString substringWithRange:NSMakeRange(0, 2)]] scanHexInt:&red];
	[[NSScanner scannerWithString:[hexString substringWithRange:NSMakeRange(2, 2)]] scanHexInt:&green];
	[[NSScanner scannerWithString:[hexString substringWithRange:NSMakeRange(4, 2)]] scanHexInt:&blue];

	if (red < 128 && green < 128 && blue < 128) {
		return [UIColor whiteColor];
	}

	return [UIColor colorWithRed:(red / 255.0) green:(green / 255.0) blue:(blue / 255.0) alpha:1.0];
}
%end


%hook UIWindow
- (instancetype)initWithFrame:(CGRect)frame {
	UIWindow *window = %orig(frame);
	if (window) {
		UILongPressGestureRecognizer *doubleFingerLongPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleFingerLongPressGesture:)];
		doubleFingerLongPressGesture.numberOfTouchesRequired = 2;
		[window addGestureRecognizer:doubleFingerLongPressGesture];
	}
	return window;
}

%new
- (void)handleDoubleFingerLongPressGesture:(UILongPressGestureRecognizer *)gesture {
	if (gesture.state == UIGestureRecognizerStateBegan) {
		UIViewController *rootViewController = self.rootViewController;
		if (rootViewController) {
			UIViewController *settingVC = [[DYYYSettingViewController alloc] init];

			if (settingVC) {
				BOOL isIPad = UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad;
				if (@available(iOS 15.0, *)) {
					if (!isIPad) {
						settingVC.modalPresentationStyle = UIModalPresentationPageSheet;
					} else {
						settingVC.modalPresentationStyle = UIModalPresentationFullScreen;
					}
				} else {
					settingVC.modalPresentationStyle = UIModalPresentationFullScreen;
				}

				if (settingVC.modalPresentationStyle == UIModalPresentationFullScreen) {
					UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
					[closeButton setTitle:@"关闭" forState:UIControlStateNormal];
					closeButton.translatesAutoresizingMaskIntoConstraints = NO;

					[settingVC.view addSubview:closeButton];

					[NSLayoutConstraint activateConstraints:@[
						[closeButton.trailingAnchor constraintEqualToAnchor:settingVC.view.trailingAnchor constant:-10],
						[closeButton.topAnchor constraintEqualToAnchor:settingVC.view.topAnchor constant:40], [closeButton.widthAnchor constraintEqualToConstant:80],
						[closeButton.heightAnchor constraintEqualToConstant:40]
					]];

					[closeButton addTarget:self action:@selector(closeSettings:) forControlEvents:UIControlEventTouchUpInside];
				}

				UIView *handleBar = [[UIView alloc] init];
				handleBar.backgroundColor = [UIColor whiteColor];
				handleBar.layer.cornerRadius = 2.5;
				handleBar.translatesAutoresizingMaskIntoConstraints = NO;
				[settingVC.view addSubview:handleBar];

				[NSLayoutConstraint activateConstraints:@[
					[handleBar.centerXAnchor constraintEqualToAnchor:settingVC.view.centerXAnchor],
					[handleBar.topAnchor constraintEqualToAnchor:settingVC.view.topAnchor constant:8], [handleBar.widthAnchor constraintEqualToConstant:40],
					[handleBar.heightAnchor constraintEqualToConstant:5]
				]];

				[rootViewController presentViewController:settingVC animated:YES completion:nil];
			}
		}
	}
}

%new
- (void)closeSettings:(UIButton *)button {
	[button.superview.window.rootViewController dismissViewControllerAnimated:YES completion:nil];
}
%end


%hook AWEFeedLiveMarkView
- (void)setHidden:(BOOL)hidden {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideAvatarButton"]) {
        hidden = YES;
    }

    %orig(hidden);
}
%end

// 隐藏头像加号和透明
%hook LOTAnimationView
- (void)layoutSubviews {
    %orig;

    // 检查是否需要隐藏加号
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideLOTAnimationView"]) {
        [self removeFromSuperview];
        return;
    }

    // 应用透明度设置
    NSString *transparencyValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYAvatarViewTransparency"];
    if (transparencyValue && transparencyValue.length > 0) {
        CGFloat alphaValue = [transparencyValue floatValue];
        if (alphaValue >= 0.0 && alphaValue <= 1.0) {
            self.alpha = alphaValue;
        }
    }
}
%end

%hook AWELongVideoControlModel
- (bool)allowDownload {
    return YES;
}
%end

%hook AWELongVideoControlModel
- (long long)preventDownloadType {
    return 0;
}
%end

// 拦截开屏广告
%hook BDASplashControllerView
+ (id)alloc {
	BOOL noAds = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYNoAds"];
	if (noAds) {
		return nil;
	}
	return %orig;
}
%end

%hook AWELandscapeFeedEntryView
- (void)setCenter:(CGPoint)center {
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisEnableFullScreen"] || [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisEnableCommentBlur"]) {
		center.y += 60;
	}

	%orig(center);
}

- (void)layoutSubviews {
	%orig;
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisHiddenEntry"]) {
		[self removeFromSuperview];
	}
}

%end

%hook AWEAwemeModel

- (void)live_callInitWithDictyCategoryMethod:(id)arg1 {
    if (self.currentAweme && [self.currentAweme isLive] && [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisSkipLive"]) {
        return;
    }
    %orig;
}

+ (id)liveStreamURLJSONTransformer {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisSkipLive"] ? nil : %orig;
}

+ (id)relatedLiveJSONTransformer {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisSkipLive"] ? nil : %orig;
}

+ (id)rawModelFromLiveRoomModel:(id)arg1 {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisSkipLive"] ? nil : %orig;
}

+ (id)aweLiveRoom_subModelPropertyKey {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisSkipLive"] ? nil : %orig;
}

%end


%hook AWEStoryContainerCollectionView
- (void)layoutSubviews {
	%orig;
	if ([self.subviews count] == 2)
		return;

	// 获取 enableEnterProfile 属性来判断是否是主页
	id enableEnterProfile = [self valueForKey:@"enableEnterProfile"];
	BOOL isHome = (enableEnterProfile != nil && [enableEnterProfile boolValue]);

	// 检查是否在作者主页
	BOOL isAuthorProfile = NO;
	UIResponder *responder = self;
	while ((responder = [responder nextResponder])) {
		if ([NSStringFromClass([responder class]) containsString:@"UserHomeViewController"] || [NSStringFromClass([responder class]) containsString:@"ProfileViewController"]) {
			isAuthorProfile = YES;
			break;
		}
	}

	// 如果不是主页也不是作者主页，直接返回
	if (!isHome && !isAuthorProfile)
		return;

	for (UIView *subview in self.subviews) {
		if ([subview isKindOfClass:[UIView class]]) {
			UIView *nextResponder = (UIView *)subview.nextResponder;

			// 处理主页的情况
			if (isHome && [nextResponder isKindOfClass:%c(AWEPlayInteractionViewController)]) {
				UIViewController *awemeBaseViewController = [nextResponder valueForKey:@"awemeBaseViewController"];
				if (![awemeBaseViewController isKindOfClass:%c(AWEFeedCellViewController)]) {
					continue;
				}

				CGRect frame = subview.frame;
				if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisEnableFullScreen"]) {
					frame.size.height = subview.superview.frame.size.height - 83;
					subview.frame = frame;
				}
			}
			// 处理作者主页的情况
			else if (isAuthorProfile) {
				// 检查是否是作品图片
				BOOL isWorkImage = NO;

				// 可以通过检查子视图、标签或其他特性来确定是否是作品图片
				for (UIView *childView in subview.subviews) {
					if ([NSStringFromClass([childView class]) containsString:@"ImageView"] || [NSStringFromClass([childView class]) containsString:@"ThumbnailView"]) {
						isWorkImage = YES;
						break;
					}
				}

				if (isWorkImage) {
					// 修复作者主页作品图片上移问题
					CGRect frame = subview.frame;
					frame.origin.y += 83;
					subview.frame = frame;
				}
			}
		}
	}
}
%end

%hook AWEFeedTableView
- (void)layoutSubviews {
    %orig;
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisEnableFullScreen"]) {
        CGRect frame = self.frame;
        frame.size.height = self.superview.frame.size.height;
        self.frame = frame;
    }
}
%end

%hook AWEPlayInteractionProgressContainerView
- (void)layoutSubviews {
    %orig;
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisEnableFullScreen"]) {
        for (UIView *subview in self.subviews) {
            if ([subview class] == [UIView class]) {
                [subview setBackgroundColor:[UIColor clearColor]];
            }
        }
    }
}
%end

%hook UIView

- (void)setFrame:(CGRect)frame {

	if ([self isKindOfClass:%c(AWEIMSkylightListView)] && [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisHiddenAvatarList"]) {
		frame = CGRectZero;
	}

	if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisEnableCommentBlur"] && ![[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisEnableFullScreen"]) {
		%orig;
		return;
	}

	UIViewController *vc = [self firstAvailableUIViewController];
	if ([vc isKindOfClass:%c(AWEAwemePlayVideoViewController)]) {

		if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisEnableCommentBlur"] && frame.origin.x != 0) {
			return;
		} else if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisEnableFullScreen"] && frame.origin.x != 0 && frame.origin.y != 0) {
			%orig;
			return;
		} else {
			CGRect superviewFrame = self.superview.frame;

			if (superviewFrame.size.height > 0 && frame.size.height > 0 && frame.size.height < superviewFrame.size.height && frame.origin.x == 0 && frame.origin.y == 0) {

				CGFloat heightDifference = superviewFrame.size.height - frame.size.height;
				if (fabs(heightDifference - 83) < 1.0) {
					frame.size.height = superviewFrame.size.height;
					%orig(frame);
					return;
				}
			}
		}
	}
	%orig;
}

%end

%hook AWEBaseListViewController
- (void)viewDidLayoutSubviews {
    %orig;
    [self applyBlurEffectIfNeeded];
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [self applyBlurEffectIfNeeded];
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    [self applyBlurEffectIfNeeded];
}

%new
- (void)applyBlurEffectIfNeeded {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisEnableCommentBlur"] && 
        [self isKindOfClass:NSClassFromString(@"AWECommentPanelContainerSwiftImpl.CommentContainerInnerViewController")]) {
        
        self.view.backgroundColor = [UIColor clearColor];
        for (UIView *subview in self.view.subviews) {
            if (![subview isKindOfClass:[UIVisualEffectView class]]) {
                subview.backgroundColor = [UIColor clearColor];
            }
        }
        
        UIVisualEffectView *existingBlurView = nil;
        for (UIView *subview in self.view.subviews) {
            if ([subview isKindOfClass:[UIVisualEffectView class]] && subview.tag == 999) {
                existingBlurView = (UIVisualEffectView *)subview;
                break;
            }
        }
        
        BOOL isDarkMode = YES;
        
        UILabel *commentLabel = [self findCommentLabel:self.view];
        if (commentLabel) {
            UIColor *textColor = commentLabel.textColor;
            CGFloat red, green, blue, alpha;
            [textColor getRed:&red green:&green blue:&blue alpha:&alpha];
            
            if (red > 0.7 && green > 0.7 && blue > 0.7) {
                isDarkMode = YES;
            } else if (red < 0.3 && green < 0.3 && blue < 0.3) {
                isDarkMode = NO;
            }
        }
        
        UIBlurEffectStyle blurStyle = isDarkMode ? UIBlurEffectStyleDark : UIBlurEffectStyleLight;
        
        if (!existingBlurView) {
            UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:blurStyle];
            UIVisualEffectView *blurEffectView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
            blurEffectView.frame = self.view.bounds;
            blurEffectView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            blurEffectView.alpha = 0.98;
            blurEffectView.tag = 999;
            
            UIView *overlayView = [[UIView alloc] initWithFrame:self.view.bounds];
            CGFloat alpha = isDarkMode ? 0.3 : 0.1;
            overlayView.backgroundColor = [UIColor colorWithWhite:(isDarkMode ? 0 : 1) alpha:alpha];
            overlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [blurEffectView.contentView addSubview:overlayView];
            
            [self.view insertSubview:blurEffectView atIndex:0];
        } else {
            UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:blurStyle];
            [existingBlurView setEffect:blurEffect];
            
            for (UIView *subview in existingBlurView.contentView.subviews) {
                if (subview.tag != 999) {
                    CGFloat alpha = isDarkMode ? 0.3 : 0.1;
                    subview.backgroundColor = [UIColor colorWithWhite:(isDarkMode ? 0 : 1) alpha:alpha];
                }
            }
            
            [self.view insertSubview:existingBlurView atIndex:0];
        }
    }
}

%new
- (UILabel *)findCommentLabel:(UIView *)view {
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        if (label.text && ([label.text hasSuffix:@"条评论"] || [label.text hasSuffix:@"暂无评论"])) {
            return label;
        }
    }
    
    for (UIView *subview in view.subviews) {
        UILabel *result = [self findCommentLabel:subview];
        if (result) {
            return result;
        }
    }
    
    return nil;
}
%end

%hook AFDFastSpeedView
- (void)layoutSubviews {
    %orig;
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisEnableFullScreen"]) {
        for (UIView *subview in self.subviews) {
            if ([subview class] == [UIView class]) {
                [subview setBackgroundColor:[UIColor clearColor]];
            }
        }
    }
}
%end

// UIView分类实现，获取关联的UIViewController
%hook UIView
%new
- (UIViewController *)yy_viewController {
    UIResponder *responder = self;
    while ((responder = [responder nextResponder])) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            return (UIViewController *)responder;
        }
    }
    return nil;
}
%end

%hook UIView

- (void)setAlpha:(CGFloat)alpha {
    UIViewController *vc = [self firstAvailableUIViewController];
    
    if ([vc isKindOfClass:%c(AWEPlayInteractionViewController)] && alpha > 0) {
        NSString *transparentValue = [[NSUserDefaults standardUserDefaults] stringForKey:@"DYYYGlobalTransparency"];
        if (transparentValue.length > 0) {
            CGFloat alphaValue = transparentValue.floatValue;
            if (alphaValue >= 0.0 && alphaValue <= 1.0) {
                %orig(alphaValue);
                return;
            }
        }
    }
    %orig;
}

%new
- (UIViewController *)firstAvailableUIViewController {
    UIResponder *responder = [self nextResponder];
    while (responder != nil) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            return (UIViewController *)responder;
        }
        responder = [responder nextResponder];
    }
    return nil;
}

%end

// 移除共创头像列表
%hook AWEPlayInteractionCoCreatorNewInfoView
- (void)layoutSubviews {
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideGongChuang"]) {
		if ([self respondsToSelector:@selector(removeFromSuperview)]) {
			[self removeFromSuperview];
		}
		self.hidden = YES;
		return;
	}
	%orig;
}
%end

// 隐藏右下音乐和取消静音按钮
%hook AFDCancelMuteAwemeView
- (void)layoutSubviews {
	%orig;

	UIView *superview = self.superview;

	if ([superview isKindOfClass:NSClassFromString(@"AWEBaseElementView")]) {
		if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideCancelMute"]) {
			self.hidden = YES;
		}
	}
}
%end

// 隐藏弹幕按钮
%hook AWEPlayDanmakuInputContainView

- (void)layoutSubviews {
	%orig;

	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideDanmuButton"]) {
		self.hidden = YES;
	}
}

%end

// 隐藏作者店铺
%hook AWEECommerceEntryView

- (void)layoutSubviews {
	%orig;

	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideHisShop"]) {
		UIView *parentView = self.superview;
		if (parentView) {
			parentView.hidden = YES;
		} else {
			self.hidden = YES;
		}
	}
}

%end

// 隐藏评论搜索
%hook AWECommentSearchAnchorView
- (void)layoutSubviews {
	%orig;

	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideCommentViews"]) {
		[self setHidden:YES];
	}
}

%end

// 隐藏评论区定位
%hook AWEPOIEntryAnchorView

- (void)p_addViews {
	// 检查用户偏好设置
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideCommentViews"]) {
		// 直接跳过视图添加流程
		return;
	}
	// 执行原始方法
	%orig;
}

- (void)setIconUrls:(id)arg1 defaultImage:(id)arg2 {
	// 根据需求选择是否拦截资源加载
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideCommentViews"]) {
		%orig(nil, nil);
		return;
	}
	// 正常传递参数
	%orig(arg1, arg2);
}

- (void)setContentSize:(CGSize)arg1 {
	// 可选：动态调整尺寸计算逻辑
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideCommentViews"]) {
		// 计算不包含评论视图的尺寸
		CGSize newSize = CGSizeMake(arg1.width, arg1.height - 44); // 示例减法
		%orig(newSize);
		return;
	}
	// 保持原有尺寸计算
	%orig(arg1);
}

%end

// 隐藏评论音乐
%hook AWECommentGuideLunaAnchorView
- (void)layoutSubviews {
	%orig;

	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideCommentViews"]) {
		[self setHidden:YES];
	}
}

%end

// Swift 类组 - 这些会在 %ctor 中动态初始化
%group CommentHeaderGeneralGroup
%hook AWECommentPanelHeaderSwiftImpl_CommentHeaderGeneralView
- (void)layoutSubviews {
	%orig;

	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideCommentViews"]) {
		[self setHidden:YES];
	}
}
%end
%end
%group CommentHeaderGoodsGroup
%hook AWECommentPanelHeaderSwiftImpl_CommentHeaderGoodsView
- (void)layoutSubviews {
	%orig;

	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideCommentViews"]) {
		[self setHidden:YES];
	}
}
%end
%end
%group CommentHeaderTemplateGroup
%hook AWECommentPanelHeaderSwiftImpl_CommentHeaderTemplateAnchorView
- (void)layoutSubviews {
	%orig;

	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideCommentViews"]) {
		[self setHidden:YES];
	}
}
%end
%end

// 隐藏大家都在搜
%hook AWESearchAnchorListModel

- (void)setHideWords:(BOOL)arg1 {
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideCommentViews"]) {
		%orig(YES);
	} else {
		%orig(arg1);
	}
}

- (void)setScene:(id)arg1 {
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideCommentViews"]) {
		NSDictionary *customScene = @{@"hideComments" : @YES};
		%orig(customScene);
	} else {
		%orig(arg1);
	}
}
%end

// 隐藏观看历史搜索
%hook AWEDiscoverFeedEntranceView
- (id)init {
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideInteractionSearch"]) {
		return nil;
	}
	return %orig;
}
%end

// 隐藏校园提示
%hook AWETemplateTagsCommonView

- (void)layoutSubviews {
	%orig;

	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideTemplateTags"]) {
		UIView *parentView = self.superview;
		if (parentView) {
			parentView.hidden = YES;
		} else {
			self.hidden = YES;
		}
	}
}

%end

// 隐藏挑战贴纸
%hook AWEFeedStickerContainerView

- (BOOL)isHidden {
	BOOL origHidden = %orig;
	BOOL hideRecommend = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideChallengeStickers"];
	return origHidden || hideRecommend;
}

- (void)setHidden:(BOOL)hidden {
	BOOL forceHide = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideChallengeStickers"];
	%orig(forceHide ? YES : hidden);
}

%end

%hook AWEPostWorkViewController
- (BOOL)isDouGuideTipViewShow {
	BOOL r = %orig;
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideChallengeStickers"]) {
		return YES;
	}
	return r;
}
%end

// 隐藏消息页顶栏头像气泡
%hook AFDSkylightCellBubble
- (void)layoutSubviews {
	%orig;

	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisHiddenAvatarBubble"]) {
		[self removeFromSuperview];
		return;
	}
}
%end

// 隐藏消息页开启通知提示
%hook AWEIMMessageTabOptPushBannerView

- (instancetype)initWithFrame:(CGRect)frame {
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHidePushBanner"]) {
		return %orig(CGRectMake(frame.origin.x, frame.origin.y, 0, 0));
	}
	return %orig;
}

%end

// 隐藏拍同款
%hook AWEFeedAnchorContainerView

- (BOOL)isHidden {
	BOOL origHidden = %orig;
	BOOL hideSamestyle = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideFeedAnchorContainer"];
	return origHidden || hideSamestyle;
}

- (void)setHidden:(BOOL)hidden {
	BOOL forceHide = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideFeedAnchorContainer"];
	%orig(forceHide ? YES : hidden);
}

%end

// 隐藏合集和声明
%hook AWEAntiAddictedNoticeBarView
- (void)layoutSubviews {
	%orig;

	// 获取 tipsLabel 属性
	UILabel *tipsLabel = [self valueForKey:@"tipsLabel"];

	if (tipsLabel && [tipsLabel isKindOfClass:%c(UILabel)]) {
		NSString *labelText = tipsLabel.text;

		if (labelText) {
			// 明确判断是合集还是作者声明
			if ([labelText containsString:@"合集"]) {
				// 如果是合集，只检查合集的开关
				if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideTemplateVideo"]) {
					[self removeFromSuperview];
				}
			} else {
				// 如果不是合集（即作者声明），只检查声明的开关
				if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideAntiAddictedNotice"]) {
					[self removeFromSuperview];
				}
			}
		}
	}
}
%end

// 隐藏分享给朋友提示
%hook AWEPlayInteractionStrongifyShareContentView

- (void)layoutSubviews {
	%orig;

	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideShareContentView"]) {
		UIView *parentView = self.superview;
		if (parentView) {
			parentView.hidden = YES;
		} else {
			self.hidden = YES;
		}
	}
}

%end

// 移除下面推荐框黑条
%hook AWEPlayInteractionRelatedVideoView
- (void)layoutSubviews {
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideBottomRelated"]) {
		if ([self respondsToSelector:@selector(removeFromSuperview)]) {
			[self removeFromSuperview];
		}
		self.hidden = YES;
		return;
	}
	%orig;
}
%end

%hook AWEFeedRelatedSearchTipView
- (void)layoutSubviews {
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideBottomRelated"]) {
		if ([self respondsToSelector:@selector(removeFromSuperview)]) {
			[self removeFromSuperview];
		}
		self.hidden = YES;
		return;
	}
	%orig;
}
%end


%hook AWEAwemeModel
- (id)initWithDictionary:(id)arg1 error:(id *)arg2 {
	id orig = %orig;

	BOOL noAds = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYNoAds"];
	BOOL skipLive = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisSkipLive"];
	BOOL skipHotSpot = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisSkipHotSpot"];

	BOOL shouldFilterAds = noAds && (self.hotSpotLynxCardModel || self.isAds);
	BOOL shouldFilterRec = skipLive && (self.liveReason != nil);
	BOOL shouldFilterHotSpot = skipHotSpot && self.hotSpotLynxCardModel;

	BOOL shouldFilterLowLikes = NO;
	BOOL shouldFilterKeywords = NO;

	BOOL shouldFilterTime = NO;

	// 获取用户设置的需要过滤的关键词
	NSString *filterKeywords = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYfilterKeywords"];
	NSArray *keywordsList = nil;

	if (filterKeywords.length > 0) {
		keywordsList = [filterKeywords componentsSeparatedByString:@","];
	}

	NSInteger filterLowLikesThreshold = [[NSUserDefaults standardUserDefaults] integerForKey:@"DYYYfilterLowLikes"];

	// 只有当shareRecExtra不为空时才过滤点赞量低的视频和关键词
	if (self.shareRecExtra && ![self.shareRecExtra isEqual:@""]) {
		// 过滤低点赞量视频
		if (filterLowLikesThreshold > 0) {
			AWESearchAwemeExtraModel *searchExtraModel = [self searchExtraModel];
			if (!searchExtraModel) {
				AWEAwemeStatisticsModel *statistics = self.statistics;
				if (statistics && statistics.diggCount) {
					shouldFilterLowLikes = statistics.diggCount.integerValue < filterLowLikesThreshold;
				}
			}
		}

		// 过滤包含特定关键词的视频
		if (keywordsList.count > 0) {
			// 检查视频标题
			if (self.itemTitle.length > 0) {
				for (NSString *keyword in keywordsList) {
					NSString *trimmedKeyword = [keyword stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
					if (trimmedKeyword.length > 0 && [self.itemTitle containsString:trimmedKeyword]) {
						shouldFilterKeywords = YES;
						break;
					}
				}
			}

			// 如果标题中没有关键词，检查标签(textExtras)
			if (!shouldFilterKeywords && self.textExtras.count > 0) {
				for (AWEAwemeTextExtraModel *textExtra in self.textExtras) {
					NSString *hashtagName = textExtra.hashtagName;
					if (hashtagName.length > 0) {
						for (NSString *keyword in keywordsList) {
							NSString *trimmedKeyword = [keyword stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
							if (trimmedKeyword.length > 0 && [hashtagName containsString:trimmedKeyword]) {
								shouldFilterKeywords = YES;
								break;
							}
						}
						if (shouldFilterKeywords)
							break;
					}
				}
			}
		}

		// 过滤视频发布时间
		long long currentTimestamp = (long long)[[NSDate date] timeIntervalSince1970];
		NSInteger daysThreshold = [[NSUserDefaults standardUserDefaults] integerForKey:@"DYYYfiltertimelimit"];
		if (daysThreshold > 0) {
			NSTimeInterval videoTimestamp = [self.createTime doubleValue];
			if (videoTimestamp > 0) {
				NSTimeInterval threshold = daysThreshold * 86400.0;
				NSTimeInterval current = (NSTimeInterval)currentTimestamp;
				NSTimeInterval timeDifference = current - videoTimestamp;
				shouldFilterTime = (timeDifference > threshold);
			}
		}
	}
	return (shouldFilterAds || shouldFilterRec || shouldFilterHotSpot || shouldFilterLowLikes || shouldFilterKeywords || shouldFilterTime) ? nil : orig;
}

- (id)init {
	id orig = %orig;

	BOOL noAds = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYNoAds"];
	BOOL skipLive = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisSkipLive"];
	BOOL skipHotSpot = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisSkipHotSpot"];

	BOOL shouldFilterAds = noAds && (self.hotSpotLynxCardModel || self.isAds);
	BOOL shouldFilterRec = skipLive && (self.liveReason != nil);
	BOOL shouldFilterHotSpot = skipHotSpot && self.hotSpotLynxCardModel;

	BOOL shouldFilterLowLikes = NO;
	BOOL shouldFilterKeywords = NO;

	BOOL shouldFilterTime = NO;

	// 获取用户设置的需要过滤的关键词
	NSString *filterKeywords = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYfilterKeywords"];
	NSArray *keywordsList = nil;

	if (filterKeywords.length > 0) {
		keywordsList = [filterKeywords componentsSeparatedByString:@","];
	}

	NSInteger filterLowLikesThreshold = [[NSUserDefaults standardUserDefaults] integerForKey:@"DYYYfilterLowLikes"];

	// 只有当shareRecExtra不为空时才过滤
	if (self.shareRecExtra && ![self.shareRecExtra isEqual:@""]) {
		// 过滤低点赞量视频
		if (filterLowLikesThreshold > 0) {
			AWESearchAwemeExtraModel *searchExtraModel = [self searchExtraModel];
			if (!searchExtraModel) {
				AWEAwemeStatisticsModel *statistics = self.statistics;
				if (statistics && statistics.diggCount) {
					shouldFilterLowLikes = statistics.diggCount.integerValue < filterLowLikesThreshold;
				}
			}
		}

		// 过滤包含特定关键词的视频
		if (keywordsList.count > 0) {
			// 检查视频标题
			if (self.itemTitle.length > 0) {
				for (NSString *keyword in keywordsList) {
					NSString *trimmedKeyword = [keyword stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
					if (trimmedKeyword.length > 0 && [self.itemTitle containsString:trimmedKeyword]) {
						shouldFilterKeywords = YES;
						break;
					}
				}
			}

			// 如果标题中没有关键词，检查标签(textExtras)
			if (!shouldFilterKeywords && self.textExtras.count > 0) {
				for (AWEAwemeTextExtraModel *textExtra in self.textExtras) {
					NSString *hashtagName = textExtra.hashtagName;
					if (hashtagName.length > 0) {
						for (NSString *keyword in keywordsList) {
							NSString *trimmedKeyword = [keyword stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
							if (trimmedKeyword.length > 0 && [hashtagName containsString:trimmedKeyword]) {
								shouldFilterKeywords = YES;
								break;
							}
						}
						if (shouldFilterKeywords)
							break;
					}
				}
			}
		}

		// 过滤视频发布时间
		long long currentTimestamp = (long long)[[NSDate date] timeIntervalSince1970];
		NSInteger daysThreshold = [[NSUserDefaults standardUserDefaults] integerForKey:@"DYYYfiltertimelimit"];
		if (daysThreshold > 0) {
			NSTimeInterval videoTimestamp = [self.createTime doubleValue];
			if (videoTimestamp > 0) {
				NSTimeInterval threshold = daysThreshold * 86400.0;
				NSTimeInterval current = (NSTimeInterval)currentTimestamp;
				NSTimeInterval timeDifference = current - videoTimestamp;
				shouldFilterTime = (timeDifference > threshold);
			}
		}
	}

	return (shouldFilterAds || shouldFilterRec || shouldFilterHotSpot || shouldFilterLowLikes || shouldFilterKeywords || shouldFilterTime) ? nil : orig;
}

- (bool)preventDownload {
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYNoAds"]) {
		return NO;
	} else {
		return %orig;
	}
}

- (void)setAdLinkType:(long long)arg1 {
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYNoAds"]) {
		arg1 = 0;
	} else {
	}

	%orig;
}

%end

%hook AWENormalModeTabBarBadgeContainerView

- (void)layoutSubviews {
    %orig;
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisHiddenBottomDot"]) {
        for (UIView *subview in [self subviews]) {
            if ([subview isKindOfClass:NSClassFromString(@"DUXBadge")]) {
                [subview setHidden:YES];
            }
        }
    }
}

%end

// 隐藏搜同款
%hook ACCStickerContainerView
- (void)layoutSubviews {
	// 类型安全检查 + 隐藏逻辑
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideInteractionSearch"]) {
		if ([self respondsToSelector:@selector(removeFromSuperview)]) {
			[self removeFromSuperview];
		}
		self.hidden = YES; // 隐藏更彻底
		return;
	}
	%orig;
}
%end

// 隐藏礼物展馆
%hook BDXWebView
- (void)layoutSubviews {
	%orig;

	BOOL enabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideGiftPavilion"];
	if (!enabled)
		return;

	NSString *title = [self valueForKey:@"title"];

	if ([title containsString:@"任务Banner"] || [title containsString:@"活动Banner"]) {
		[self removeFromSuperview];
	}
}
%end

%hook AWEVideoTypeTagView

- (void)setupUI {
	if (![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYHideLiveGIF"])
		%orig;
}
%end

%hook IESLiveActivityBannnerView
- (void)layoutSubviews {
	%orig;
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideGiftPavilion"]) {
		self.hidden = YES;
	}
}

%end

// 隐藏直播广场
%hook IESLiveFeedDrawerEntranceView
- (void)layoutSubviews {
	%orig;

	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideLivePlayground"]) {
		self.hidden = YES;
	}
}

%end

%hook AWELeftSideBarEntranceView

- (void)layoutSubviews {

	__block BOOL isInTargetController = NO;
	UIResponder *currentResponder = self;

	while ((currentResponder = [currentResponder nextResponder])) {
		if ([currentResponder isKindOfClass:NSClassFromString(@"AWEUserHomeViewControllerV2")]) {
			isInTargetController = YES;
			break;
		}
	}

	if (!isInTargetController && [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisHiddenLeftSideBar"]) {
		for (UIView *subview in self.subviews) {
			subview.hidden = YES;
		}
	}
}

- (void)setRedDot:(id)redDot {
    %orig(nil); 
}

- (void)setNumericalRedDot:(id)numericalRedDot {
    %orig(nil); 
}

%end

%hook AWEFeedVideoButton

- (void)layoutSubviews {
	%orig;

	NSString *accessibilityLabel = self.accessibilityLabel;

	if ([accessibilityLabel isEqualToString:@"点赞"]) {
		if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideLikeButton"]) {
			[self removeFromSuperview];
			return;
		}

		// 隐藏点赞数值标签
		if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideLikeLabel"]) {
			for (UIView *subview in self.subviews) {
				if ([subview isKindOfClass:[UILabel class]]) {
					subview.hidden = YES;
				}
			}
		}
	} else if ([accessibilityLabel isEqualToString:@"评论"]) {
		if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideCommentButton"]) {
			[self removeFromSuperview];
			return;
		}

		// 隐藏评论数值标签
		if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideCommentLabel"]) {
			for (UIView *subview in self.subviews) {
				if ([subview isKindOfClass:[UILabel class]]) {
					subview.hidden = YES;
				}
			}
		}
	} else if ([accessibilityLabel isEqualToString:@"分享"]) {
		if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideShareButton"]) {
			[self removeFromSuperview];
			return;
		}

		// 隐藏分享数值标签
		if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideShareLabel"]) {
			for (UIView *subview in self.subviews) {
				if ([subview isKindOfClass:[UILabel class]]) {
					subview.hidden = YES;
				}
			}
		}
	} else if ([accessibilityLabel isEqualToString:@"收藏"]) {
		if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideCollectButton"]) {
			[self removeFromSuperview];
			return;
		}

		// 隐藏收藏数值标签
		if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideCollectLabel"]) {
			for (UIView *subview in self.subviews) {
				if ([subview isKindOfClass:[UILabel class]]) {
					subview.hidden = YES;
				}
			}
		}
	}
}

%end

%hook AWEMusicCoverButton

- (void)layoutSubviews {
    %orig;

    NSString *accessibilityLabel = self.accessibilityLabel;

    if ([accessibilityLabel isEqualToString:@"音乐详情"]) {
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideMusicButton"]) {
            [self removeFromSuperview];
            return;
        }
    }
}

%end

%hook AWEPlayInteractionListenFeedView
- (void)layoutSubviews {
    %orig;

    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideMusicButton"]) {
        [self removeFromSuperview];
        return;
    }
}
%end

%hook AWEPlayInteractionFollowPromptView

- (void)layoutSubviews {
    %orig;

    NSString *accessibilityLabel = self.accessibilityLabel;

    if ([accessibilityLabel isEqualToString:@"关注"]) {
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideAvatarButton"]) {
            [self removeFromSuperview];
            return;
        }
    }
}

%end

// 首页头像隐藏和透明
%hook AWEAdAvatarView
- (void)layoutSubviews {
    %orig;

    // 检查是否需要隐藏头像
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideAvatarButton"]) {
        [self removeFromSuperview];
        return;
    }

    // 应用透明度设置
    NSString *transparencyValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYAvatarViewTransparency"];
    if (transparencyValue && transparencyValue.length > 0) {
        CGFloat alphaValue = [transparencyValue floatValue];
        if (alphaValue >= 0.0 && alphaValue <= 1.0) {
            self.alpha = alphaValue;
        }
    }
}
%end

// 移除同城吃喝玩乐提示框
%hook AWENearbySkyLightCapsuleView
- (void)layoutSubviews {
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideNearbyCapsuleView"]) {
		if ([self respondsToSelector:@selector(removeFromSuperview)]) {
			[self removeFromSuperview];
		}
		self.hidden = YES;
		return;
	}
	%orig;
}
%end

%hook AWENormalModeTabBar

- (void)layoutSubviews {
    %orig;

    BOOL hideShop = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideShopButton"];
    BOOL hideMsg = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideMessageButton"];
    BOOL hideFri = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideFriendsButton"];
    
    NSMutableArray *visibleButtons = [NSMutableArray array];
    Class generalButtonClass = %c(AWENormalModeTabBarGeneralButton);
    Class plusButtonClass = %c(AWENormalModeTabBarGeneralPlusButton);
    
    for (UIView *subview in self.subviews) {
        if (![subview isKindOfClass:generalButtonClass] && ![subview isKindOfClass:plusButtonClass]) continue;
        
        NSString *label = subview.accessibilityLabel;
        BOOL shouldHide = NO;
        
        if ([label isEqualToString:@"商城"]) {
            shouldHide = hideShop;
        } else if ([label containsString:@"消息"]) {
            shouldHide = hideMsg;
        } else if ([label containsString:@"朋友"]) {
            shouldHide = hideFri;
        }
        
        if (!shouldHide) {
            [visibleButtons addObject:subview];
        } else {
            [subview removeFromSuperview];
        }
    }

    [visibleButtons sortUsingComparator:^NSComparisonResult(UIView* a, UIView* b) {
        return [@(a.frame.origin.x) compare:@(b.frame.origin.x)];
    }];

    CGFloat totalWidth = self.bounds.size.width;
    CGFloat buttonWidth = totalWidth / visibleButtons.count;
    
    for (NSInteger i = 0; i < visibleButtons.count; i++) {
        UIView *button = visibleButtons[i];
        button.frame = CGRectMake(i * buttonWidth, button.frame.origin.y, buttonWidth, button.frame.size.height);
    }

    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisHiddenBottomBg"] || [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisEnableFullScreen"]) {
        for (UIView *subview in self.subviews) {
            if ([subview class] == [UIView class]) {
                BOOL hasImageView = NO;
                for (UIView *childView in subview.subviews) {
                    if ([childView isKindOfClass:[UIImageView class]]) {
                        hasImageView = YES;
                        break;
                    }
                }
                
                if (hasImageView) {
                    subview.hidden = YES;
                    break;
                }
            }
        }
    }
}

%end

%hook UITextInputTraits
- (void)setKeyboardAppearance:(UIKeyboardAppearance)appearance {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisDarkKeyBoard"]) {
        %orig(UIKeyboardAppearanceDark);
    }else {
        %orig;
    }
}
%end

%hook AWECommentMiniEmoticonPanelView

- (void)layoutSubviews {
    %orig;
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisDarkKeyBoard"]) {
        
        for (UIView *subview in self.subviews) {
            if ([subview isKindOfClass:[UICollectionView class]]) {
                subview.backgroundColor = [UIColor colorWithRed:115/255.0 green:115/255.0 blue:115/255.0 alpha:1.0];
            }
        }
    }
}
%end

%hook AWECommentPublishGuidanceView

- (void)layoutSubviews {
    %orig;
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisDarkKeyBoard"]) {
        
        for (UIView *subview in self.subviews) {
            if ([subview isKindOfClass:[UICollectionView class]]) {
                subview.backgroundColor = [UIColor colorWithRed:115/255.0 green:115/255.0 blue:115/255.0 alpha:1.0];
            }
        }
    }
}
%end

%hook UIView
- (void)layoutSubviews {
	%orig;

	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideDiscover"] && [self.accessibilityLabel isEqualToString:@"搜索"]) {
		[self removeFromSuperview];
	}

	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisEnableCommentBlur"]) {
		for (UIView *subview in self.subviews) {
			if ([subview isKindOfClass:NSClassFromString(@"AWECommentInputViewSwiftImpl.CommentInputViewMiddleContainer")]) {
				BOOL containsDanmu = NO;

				for (UIView *innerSubview in subview.subviews) {
					if ([innerSubview isKindOfClass:[UILabel class]] && [((UILabel *)innerSubview).text containsString:@"弹幕"]) {
						containsDanmu = YES;
						break;
					}
				}
				if (containsDanmu) {
					UIView *parentView = subview.superview;
					for (UIView *innerSubview in parentView.subviews) {
						if ([innerSubview isKindOfClass:[UIView class]]) {
							// NSLog(@"[innerSubview] %@", innerSubview);
							[innerSubview.subviews[0] removeFromSuperview];

							UIView *whiteBackgroundView = [[UIView alloc] initWithFrame:innerSubview.bounds];
							whiteBackgroundView.backgroundColor = [UIColor whiteColor];
							whiteBackgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
							[innerSubview addSubview:whiteBackgroundView];
							break;
						}
					}
				} else {
					for (UIView *innerSubview in subview.subviews) {
						if ([innerSubview isKindOfClass:[UIView class]]) {
							float userTransparency = [[[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYCommentBlurTransparent"] floatValue];
							if (userTransparency <= 0 || userTransparency > 1) {
								userTransparency = 0.95;
							}
							DYYYAddCustomViewToParent(innerSubview, userTransparency);
							break;
						}
					}
				}
			}
		}
	}
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisEnableFullScreen"] || [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisEnableCommentBlur"]) {

		UIViewController *vc = [self firstAvailableUIViewController];
		if ([vc isKindOfClass:%c(AWEPlayInteractionViewController)]) {
			BOOL shouldHideSubview = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisEnableFullScreen"] ||
						 [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisEnableCommentBlur"];

			if (shouldHideSubview) {
				for (UIView *subview in self.subviews) {
					if ([subview isKindOfClass:[UIView class]] && subview.backgroundColor && CGColorEqualToColor(subview.backgroundColor.CGColor, [UIColor blackColor].CGColor)) {
						subview.hidden = YES;
					}
				}
			}
		}
	}
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisEnableCommentBlur"]) {
		NSString *className = NSStringFromClass([self class]);
		if ([className isEqualToString:@"AWECommentInputViewSwiftImpl.CommentInputContainerView"]) {
			for (UIView *subview in self.subviews) {
				if ([subview isKindOfClass:[UIView class]] && subview.backgroundColor) {
					CGFloat red = 0, green = 0, blue = 0, alpha = 0;
					[subview.backgroundColor getRed:&red green:&green blue:&blue alpha:&alpha];

					if ((red == 22 / 255.0 && green == 22 / 255.0 && blue == 22 / 255.0) || (red == 1.0 && green == 1.0 && blue == 1.0)) {
						float userTransparency = [[[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYCommentBlurTransparent"] floatValue];
						if (userTransparency <= 0 || userTransparency > 1) {
							userTransparency = 0.95;
						}
						DYYYAddCustomViewToParent(subview, userTransparency);
					}
				}
			}
		}
	}
}
%end

%hook UILabel

- (void)setText:(NSString *)text {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisDarkKeyBoard"]) {
        if ([text hasPrefix:@"善语"] || [text hasPrefix:@"友爱评论"] || [text hasPrefix:@"回复"]) {
            self.textColor = [UIColor colorWithRed:125/255.0 green:125/255.0 blue:125/255.0 alpha:0.6];
        }
    }
    %orig;
}

- (void)layoutSubviews {
	%orig;

	BOOL hideRightLabel = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideRightLable"];
	if (!hideRightLabel)
		return;

	NSString *accessibilityLabel = self.accessibilityLabel;
	if (!accessibilityLabel || accessibilityLabel.length == 0)
		return;

	NSString *trimmedLabel = [accessibilityLabel stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	BOOL shouldHide = NO;

	if ([trimmedLabel hasSuffix:@"人共创"]) {
		NSString *prefix = [trimmedLabel substringToIndex:trimmedLabel.length - 3];
		NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
		shouldHide = ([prefix rangeOfCharacterFromSet:nonDigits].location == NSNotFound);
	}

	if (!shouldHide) {
		shouldHide = [trimmedLabel isEqualToString:@"章节要点"] || [trimmedLabel isEqualToString:@"图集"];
	}

	if (shouldHide) {
		self.hidden = YES;

		// 找到父视图是否为 UIStackView
		UIView *superview = self.superview;
		if ([superview isKindOfClass:[UIStackView class]]) {
			UIStackView *stackView = (UIStackView *)superview;
			// 刷新 UIStackView 的布局
			[stackView layoutIfNeeded];
		}
	}
}

%end

%hook UIButton

- (void)setImage:(UIImage *)image forState:(UIControlState)state {
    NSString *label = self.accessibilityLabel;
//    NSLog(@"Label -> %@",accessibilityLabel);
    if ([label isEqualToString:@"表情"] || [label isEqualToString:@"at"] || [label isEqualToString:@"图片"] || [label isEqualToString:@"键盘"]) {
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisDarkKeyBoard"]) {
            
            UIImage *whiteImage = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            
            self.tintColor = [UIColor whiteColor];
            
            %orig(whiteImage, state);
        }else {
            %orig(image, state);
        }
    } else {
        %orig(image, state);
    }
}

%end

%hook AWETextViewInternal

- (void)drawRect:(CGRect)rect {
    %orig(rect);
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisDarkKeyBoard"]) {
        
        self.textColor = [UIColor whiteColor];
    }
}

- (double)lineSpacing {
    double r = %orig;
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisDarkKeyBoard"]) {
        
        self.textColor = [UIColor whiteColor];
    }
    return r;
}

%end

%hook AWEPlayInteractionUserAvatarElement

- (void)onFollowViewClicked:(UITapGestureRecognizer *)gesture {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYfollowTips"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *alertController = [UIAlertController
                                                  alertControllerWithTitle:@"关注确认"
                                                  message:@"是否确认关注？"
                                                  preferredStyle:UIAlertControllerStyleAlert];
            
            UIAlertAction *cancelAction = [UIAlertAction
                                           actionWithTitle:@"取消"
                                           style:UIAlertActionStyleCancel
                                           handler:nil];
            
            UIAlertAction *confirmAction = [UIAlertAction
                                            actionWithTitle:@"确定"
                                            style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                %orig(gesture);
            }];
            
            [alertController addAction:cancelAction];
            [alertController addAction:confirmAction];
            
            UIViewController *topController = [DYYYManager getActiveTopController];
            if (topController) {
                [topController presentViewController:alertController animated:YES completion:nil];
            }
        });
    }else {
        %orig;
    }
}

%end

%hook AWEFeedVideoButton
- (id)touchUpInsideBlock {
    id r = %orig;
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYcollectTips"] && [self.accessibilityLabel isEqualToString:@"收藏"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *alertController = [UIAlertController
                                                  alertControllerWithTitle:@"收藏确认"
                                                  message:@"是否[确认/取消]收藏？"
                                                  preferredStyle:UIAlertControllerStyleAlert];

            UIAlertAction *cancelAction = [UIAlertAction
                                           actionWithTitle:@"取消"
                                           style:UIAlertActionStyleCancel
                                           handler:nil];

            UIAlertAction *confirmAction = [UIAlertAction
                                            actionWithTitle:@"确定"
                                            style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                if (r && [r isKindOfClass:NSClassFromString(@"NSBlock")]) {
                    ((void(^)(void))r)();
                }
            }];

            [alertController addAction:cancelAction];
            [alertController addAction:confirmAction];

            UIViewController *topController = [DYYYManager getActiveTopController];
            if (topController) {
                [topController presentViewController:alertController animated:YES completion:nil];
            }
        });

        return nil;
    }

    return r;
}
%end

%hook AWEFeedProgressSlider

//开启视频进度条后默认显示进度条的透明度否则有部分视频不会显示进度条以及秒数
- (void)setAlpha:(CGFloat)alpha {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisShowScheduleDisplay"]) {
        alpha = 1.0;
        %orig(alpha);
    }else {
        %orig;
    }
}
//MARK: 视频显示进度条以及视频进度秒数
//新建一个左时间
%property (nonatomic, strong) UIView *leftLabelUI;
//新建一个右时间
%property (nonatomic, strong) UIView *rightLabelUI;

- (void)setLimitUpperActionArea:(BOOL)arg1 {
    %orig;
    //定义一下进度条默认算法
    NSString *duration = [self.progressSliderDelegate formatTimeFromSeconds:floor(self.progressSliderDelegate.model.videoDuration/1000)];
    //如果开启了显示时间进度
    if([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisShowScheduleDisplay"]){
        //左时间的视图不存在就创建 50 15 大小的视图文本
        if (!self.leftLabelUI) {
            self.leftLabelUI = [[UILabel alloc] init];
            self.leftLabelUI.frame = CGRectMake(0, -12, 50, 15);
            self.leftLabelUI.backgroundColor = [UIColor clearColor];
            [(UILabel *)self.leftLabelUI setText:@"00:00"];
            [(UILabel *)self.leftLabelUI setTextColor:[UIColor whiteColor]];
            [(UILabel *)self.leftLabelUI setFont:[UIFont systemFontOfSize:8]];
            [self addSubview:self.leftLabelUI];
        }else{
            [(UILabel *)self.leftLabelUI setText:@"00:00"];
            [(UILabel *)self.leftLabelUI setTextColor:[UIColor whiteColor]];
            [(UILabel *)self.leftLabelUI setFont:[UIFont systemFontOfSize:8]];
        }
        
        // 如果rightLabelUI为空,创建右侧视图
        if (!self.rightLabelUI) {
            self.rightLabelUI = [[UILabel alloc] init];
            self.rightLabelUI.frame = CGRectMake(self.frame.size.width - 25, -12, 50, 15);
            self.rightLabelUI.backgroundColor = [UIColor clearColor];
            [(UILabel *)self.rightLabelUI setText:duration];
            [(UILabel *)self.rightLabelUI setTextColor:[UIColor whiteColor]];
            [(UILabel *)self.rightLabelUI setFont:[UIFont systemFontOfSize:8]];
            [self addSubview:self.rightLabelUI];
        }else{
            [(UILabel *)self.rightLabelUI setText:duration];
            [(UILabel *)self.rightLabelUI setTextColor:[UIColor whiteColor]];
            [(UILabel *)self.rightLabelUI setFont:[UIFont systemFontOfSize:8]];
        }
    }
}

%end
//MARK: 视频显示-算法
%hook AWEPlayInteractionProgressController
%new
//根据时间来给算法
- (NSString *)formatTimeFromSeconds:(CGFloat)seconds {
    //小时
    NSInteger hours = (NSInteger)seconds / 3600;
    //分钟
    NSInteger minutes = ((NSInteger)seconds % 3600) / 60;
    //秒数
    NSInteger secs = (NSInteger)seconds % 60;
    //定义进度条实例
    AWEFeedProgressSlider *progressSlider = self.progressSlider;
    //如果视频超过 60 分钟
    if (hours > 0) {
        //主线程设置他的显示总时间进度条位置
         dispatch_async(dispatch_get_main_queue(), ^{
            //设置右边小时进度条的位置
            progressSlider.rightLabelUI.frame = CGRectMake(progressSlider.frame.size.width - 46, -12, 50, 15);
         });
         //返回 00:00:00
        return [NSString stringWithFormat:@"%02ld:%02ld:%02ld", (long)hours, (long)minutes, (long)secs];
    } else {
        //返回 00:00
        return [NSString stringWithFormat:@"%02ld:%02ld", (long)minutes, (long)secs];
    }
}

- (void)updateProgressSliderWithTime:(CGFloat)arg1 totalDuration:(CGFloat)arg2 {
    %orig;
    //如果开启了显示视频进度
    if([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisShowScheduleDisplay"]){
        //获取进度条实例
        AWEFeedProgressSlider *progressSlider = self.progressSlider;
        //如果检测到时间
        if (arg1 > 0) {
            //创建左边的文本进度并且算法格式化时间
            [(UILabel *)progressSlider.leftLabelUI setText:[self formatTimeFromSeconds:arg1]];
        }
        //如果检测到时间
        if (arg2 > 0) {
            //创建右边的文本进度条并且算法格式化时间
            [(UILabel *)progressSlider.rightLabelUI setText:[self formatTimeFromSeconds:arg2]];
        }
    }
}
%end

%hook AWENormalModeTabBarTextView

- (void)layoutSubviews {
    %orig;
    
    NSString *indexTitle = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYIndexTitle"];
    NSString *friendsTitle = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYFriendsTitle"];
    NSString *msgTitle = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYMsgTitle"];
    NSString *selfTitle = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYSelfTitle"];
    
    for (UIView *subview in [self subviews]) {
        if ([subview isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)subview;
            if ([label.text isEqualToString:@"首页"]) {
                if (indexTitle.length > 0) {
                    [label setText:indexTitle];
                    [self setNeedsLayout];
                }
            }
            if ([label.text isEqualToString:@"朋友"]) {
                if (friendsTitle.length > 0) {
                    [label setText:friendsTitle];
                    [self setNeedsLayout];
                }
            }
            if ([label.text isEqualToString:@"消息"]) {
                if (msgTitle.length > 0) {
                    [label setText:msgTitle];
                    [self setNeedsLayout];
                }
            }
            if ([label.text isEqualToString:@"我"]) {
                if (selfTitle.length > 0) {
                    [label setText:selfTitle];
                    [self setNeedsLayout];
                }
            }
        }
    }
}
%end

%hook AWEFeedIPhoneAutoPlayManager
 
 - (BOOL)isAutoPlayOpen {
     BOOL r = %orig;
     
     if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisEnableAutoPlay"]) {
         return YES;
     }
     return r;
 }
 
%end

%hook AWEFeedModuleService

- (BOOL)getFeedIphoneAutoPlayState {
	BOOL r = %orig;

	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisEnableAutoPlay"]) {
		return YES;
	}
	return %orig;
}
%end

%hook AWEFeedChannelManager

- (void)reloadChannelWithChannelModels:(id)arg1 currentChannelIDList:(id)arg2 reloadType:(id)arg3 selectedChannelID:(id)arg4 {
    NSArray *channelModels = arg1;
    NSMutableArray *newChannelModels = [NSMutableArray array];
    NSArray *currentChannelIDList = arg2;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    NSMutableArray *newCurrentChannelIDList = [NSMutableArray arrayWithArray:currentChannelIDList];
    
    for (AWEHPTopTabItemModel *tabItemModel in channelModels) {
        NSString *channelID = tabItemModel.channelID;
        
        if ([channelID isEqualToString:@"homepage_hot_container"]) {
            [newChannelModels addObject:tabItemModel];
            continue;
        }
        
        BOOL isHideChannel = NO;
        if ([channelID isEqualToString:@"homepage_follow"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHideFollow"];
        } else if ([channelID isEqualToString:@"homepage_mediumvideo"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHideMediumVideo"];
        } else if ([channelID isEqualToString:@"homepage_mall"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHideMall"];
        } else if ([channelID isEqualToString:@"homepage_nearby"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHideNearby"];
        } else if ([channelID isEqualToString:@"homepage_groupon"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHideGroupon"];
        } else if ([channelID isEqualToString:@"homepage_tablive"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHideTabLive"];
        } else if ([channelID isEqualToString:@"homepage_pad_hot"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHidePadHot"];
        } else if ([channelID isEqualToString:@"homepage_hangout"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHideHangout"];
        } else if ([channelID isEqualToString:@"homepage_familiar"]) {
            isHideChannel = [defaults boolForKey:@"DYYYHideFriend"];
        }
        
        if (!isHideChannel) {
            [newChannelModels addObject:tabItemModel];
        } else {
            [newCurrentChannelIDList removeObject:channelID];
        }
    }
    
    %orig(newChannelModels, newCurrentChannelIDList, arg3, arg4);
}

%end



%hook AWEFeedRootViewController

- (BOOL)prefersStatusBarHidden {
    if([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisHideStatusbar"]){
        return YES;
    } else {
        return %orig;
    }
}

%end

// 隐藏点击进入直播间
%hook AWELiveFeedStatusLabel
- (void)layoutSubviews {
	%orig;
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideEnterLive"]) {
		UIView *parentView = self.superview;
		UIView *grandparentView = parentView.superview;

		if (grandparentView) {
			grandparentView.hidden = YES;
		} else if (parentView) {
			parentView.hidden = YES;
		} else {
			self.hidden = YES;
		}
	}
}
%end

// 去除消息群直播提示
%hook AWEIMCellLiveStatusContainerView

- (void)p_initUI {
	if (![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYGroupLiving"])
		%orig;
}
%end

%hook AWELiveStatusIndicatorView

- (void)layoutSubviews {
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYGroupLiving"]) {
		if ([self respondsToSelector:@selector(removeFromSuperview)]) {
			[self removeFromSuperview];
		}
		self.hidden = YES;
		return;
	}
	%orig;
}
%end

%hook AWELiveSkylightCatchView
- (void)layoutSubviews {

	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHidenLiveCapsuleView"]) {
		if ([self respondsToSelector:@selector(removeFromSuperview)]) {
			[self removeFromSuperview];
		}
		self.hidden = YES;
		return;
	}
	%orig;
}

%end

// 隐藏首页直播胶囊
%hook AWEHPTopTabItemBadgeContentView

- (void)layoutSubviews {
	%orig;
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideLiveCapsuleView"]) {
		self.frame = CGRectMake(0, 0, 0, 0);
		self.hidden = YES;
	}
}

- (id)showBadgeWithBadgeStyle:(NSUInteger)style badgeConfig:(id)config count:(NSInteger)count text:(id)text {
	BOOL hideEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideTopBarBadge"];

	if (hideEnabled) {
		// 阻断徽章创建
		return nil; // 返回 nil 阻止视图生成
	} else {
		// 未启用隐藏功能时正常显示
		return %orig(style, config, count, text);
	}
}

%end

// 隐藏群商店
%hook AWEIMFansGroupTopDynamicDomainTemplateView
- (void)layoutSubviews {
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideGroupShop"]) {
		if ([self respondsToSelector:@selector(removeFromSuperview)]) {
			[self removeFromSuperview];
		}
		self.hidden = YES;
		return;
	}
	%orig;
}
%end

%hook AWEHPDiscoverFeedEntranceView
- (void)setAlpha:(CGFloat)alpha {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideDiscover"]) {
        alpha = 0;
        %orig(alpha);
   }else {
       %orig;
    }
}

- (void)layoutSubviews {
	%orig;
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideDiscover"]) {
		for (UIView *subview in self.subviews) {
			subview.hidden = YES;
		}
	}
}

%end

// 隐藏直播退出清屏、投屏按钮
%hook IESLiveButton

- (void)layoutSubviews {
	%orig;

	// 处理清屏按钮
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideLiveRoomClear"]) {
		if ([self.accessibilityLabel isEqualToString:@"退出清屏"] && self.superview) {
			[self.superview removeFromSuperview];
		}
	}

	// 投屏按钮
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideLiveRoomMirroring"]) {
		if ([self.accessibilityLabel isEqualToString:@"投屏"] && self.superview) {
			[self.superview removeFromSuperview];
		}
	}
}

%end

// 去除群聊天输入框上方快捷方式
%hook AWEIMInputActionBarInteractor

- (void)p_setupUI {
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideGroupInputActionBar"]) {
		if ([self respondsToSelector:@selector(removeFromSuperview)]) {
			[self removeFromSuperview];
		}
		self.hidden = YES;
		return;
	}
	%orig;
}
%end

// 隐藏直播间流量弹窗
%hook AWELiveFlowAlertView
- (void)layoutSubviews {
	%orig;
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideCellularAlert"]) {
		self.hidden = YES;
	}
}
%end

%hook AWEFeedTemplateAnchorView

- (void)layoutSubviews {
    %orig;

    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideLocation"]) {
        [self removeFromSuperview];
        return;
    }
}

%end

// 屏蔽青少年模式弹窗
%hook AWEUIAlertView
- (void)show {
	if (![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYHideteenmode"])
		%orig;
}
%end

// 屏蔽青少年模式弹窗
%hook AWETeenModeAlertView
- (BOOL)show {
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideteenmode"]) {
		return NO;
	}
	return %orig;
}
%end

// 屏蔽青少年模式弹窗
%hook AWETeenModeSimpleAlertView
- (BOOL)show {
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideteenmode"]) {
		return NO;
	}
	return %orig;
}
%end

// 强制启用新版抖音长按 UI（现代风）
%hook AWELongPressPanelManager
- (BOOL)shouldShowModernLongPressPanel {
	// 从 NSUserDefaults 读取开关状态
	BOOL isEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisEnableModern"];
	
	// 如果开关未设置，默认启用现代风格面板
	if (![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYisEnableModern"]) {
		isEnabled = YES;
		[[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"DYYYisEnableModern"];
	}
	
	return isEnabled; // 返回是否启用现代风格面板
}

%end

// 聊天视频底部评论框背景透明
%hook AWEIMFeedBottomQuickEmojiInputBar

- (void)layoutSubviews {
	%orig;

	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideChatCommentBg"]) {
		UIView *parentView = self.superview;
		while (parentView) {
			if ([NSStringFromClass([parentView class]) isEqualToString:@"UIView"]) {
				dispatch_async(dispatch_get_main_queue(), ^{
				  parentView.backgroundColor = [UIColor clearColor];
				  parentView.layer.backgroundColor = [UIColor clearColor].CGColor;
				  parentView.opaque = NO;
				});
				break;
			}
			parentView = parentView.superview;
		}
	}
}

%end

// 隐藏侧栏红点
%hook AWEHPTopBarCTAItemView

- (void)showRedDot {
	if (![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYisHiddenSidebarDot"])
		%orig;
}

- (void)hideCountRedDot {
	if (![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYisHiddenSidebarDot"])
		%orig;
}

- (void)layoutSubviews {
	%orig;
	for (UIView *subview in self.subviews) {
		if ([subview isKindOfClass:[%c(DUXBadge) class]]) {
				if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisHiddenSidebarDot"]) {
				subview.hidden = YES;
			}
		}
	}
}
%end

// 隐藏相机定位
%hook AWETemplateCommonView
- (void)layoutSubviews {
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideCameraLocation"]) {
		if ([self respondsToSelector:@selector(removeFromSuperview)]) {
			[self removeFromSuperview];
		}
		self.hidden = YES;
		return;
	}
	%orig;
}
%end

// 隐藏短剧合集
%hook AWETemplatePlayletView

- (void)layoutSubviews {

	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideTemplatePlaylet"]) {
		if ([self respondsToSelector:@selector(removeFromSuperview)]) {
			[self removeFromSuperview];
		}
		self.hidden = YES;
		return;
	}
	%orig;
}
%end

// 隐藏作者作品集搜索
%hook AWESearchEntranceView

- (void)layoutSubviews {

	Class targetClass = NSClassFromString(@"AWESearchEntranceView");
	if (!targetClass)
		return;

	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideInteractionSearch"]) {

		SEL removeSel = NSSelectorFromString(@"removeFromSuperview");
		if ([targetClass instancesRespondToSelector:removeSel]) {
			[self performSelector:removeSel];
		}
		self.hidden = YES;
		return;
	}
	%orig;
}

%end

// 隐藏视频滑条
%hook AWEStoryProgressSlideView

- (void)layoutSubviews {
	%orig;

	BOOL shouldHide = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideStoryProgressSlide"];
	if (!shouldHide)
		return;
	__block UIView *targetView = nil;
	[self.subviews enumerateObjectsUsingBlock:^(__kindof UIView *_Nonnull obj, NSUInteger idx, BOOL *_Nonnull stop) {
	  if ([obj isKindOfClass:NSClassFromString(@"UISlider")] || obj.frame.size.height < 5) {
		  targetView = obj.superview;
		  *stop = YES;
	  }
	}];

	if (targetView) {
		targetView.hidden = YES;
	} else {
	}
}

%end

// 隐藏好友分享私信
%hook AFDNewFastReplyView

- (void)layoutSubviews {
	%orig;

	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHidePrivateMessages"]) {
		UIView *parentView = self.superview;
		if (parentView) {
			parentView.hidden = YES;
		} else {
			self.hidden = YES;
		}
	}
}

%end

// 处理自定义相册图片入口
%hook AWEPlayInteractionUserAvatarElement

- (void)layoutSubviews {
    %orig;
    
    // 检查是否启用了自定义相册图片
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYEnableCustomAlbum"]) {
        NSString *customImagePath = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYCustomAlbumImagePath"];
        
        if (customImagePath && [[NSFileManager defaultManager] fileExistsAtPath:customImagePath]) {
            // 查找相册按钮
            for (UIView *subview in self.subviews) {
                if ([subview isKindOfClass:[UIButton class]] && 
                    [subview.accessibilityIdentifier isEqualToString:@"avatar_album_button"]) {
                    
                    UIButton *albumButton = (UIButton *)subview;
                    
                    // 计算按钮大小
                    CGFloat buttonSize = 40.0; // 默认中号
                    
                    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYCustomAlbumSizeSmall"]) {
                        buttonSize = 30.0;
                    } else if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYCustomAlbumSizeMedium"]) {
                        buttonSize = 40.0;
                    } else if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYCustomAlbumSizeLarge"]) {
                        buttonSize = 50.0;
                    }
                    
                    // 调整按钮尺寸
                    albumButton.frame = CGRectMake(albumButton.frame.origin.x,
                                                  albumButton.frame.origin.y,
                                                  buttonSize,
                                                  buttonSize);
                    
                    // 加载自定义图片
                    UIImage *customImage = [UIImage imageWithContentsOfFile:customImagePath];
                    if (customImage) {
                        // 创建圆形图片
                        UIGraphicsBeginImageContextWithOptions(CGSizeMake(buttonSize, buttonSize), NO, 0);
                        
                        // 创建圆形裁剪路径
                        UIBezierPath *circlePath = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, buttonSize, buttonSize)];
                        [circlePath addClip];
                        
                        // 绘制图片铺满整个圆形区域
                        [customImage drawInRect:CGRectMake(0, 0, buttonSize, buttonSize)];
                        
                        UIImage *roundedImage = UIGraphicsGetImageFromCurrentImageContext();
                        UIGraphicsEndImageContext();
                        
                        // 设置自定义图片
                        [albumButton setImage:roundedImage forState:UIControlStateNormal];
                        albumButton.backgroundColor = [UIColor clearColor];
                    }
                    
                    break;
                }
            }
        }
    }
}

%end

%hook AWEPlayInteractionSearchAnchorView

- (void)layoutSubviews {
    %orig;
    %orig;

    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideInteractionSearch"]) {
        [self removeFromSuperview];
        return;
    }
}

%end

%hook AWEAwemeMusicInfoView

- (void)layoutSubviews {
    %orig;

    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideQuqishuiting"]) {
        // 找到父视图并隐藏
        UIView *parentView = self.superview;
        if (parentView) {
            parentView.hidden = YES;
        } else {
            self.hidden = YES;
        }
    }
}

%end

%hook AWETemplateHotspotView

- (void)layoutSubviews {
    %orig;

    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideHotspot"]) {
        [self removeFromSuperview];
        return;
    }
}

%end

%hook AWELongPressPanelTableViewController

- (NSArray *)dataArray {
    NSArray *originalArray = %orig;

    if (!originalArray) {
        originalArray = @[];
    }

    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYLongPressDownload"] && ![[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYCopyText"]) {
        return originalArray;
    }

    AWELongPressPanelViewGroupModel *newGroupModel = [[%c(AWELongPressPanelViewGroupModel) alloc] init];
    newGroupModel.groupType = 0;

    NSMutableArray *viewModels = [NSMutableArray array];

    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYLongPressDownload"]) {
        if (self.awemeModel.awemeType != 68) {
            // 检查是否启用了视频下载功能
            if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYLongPressVideoDownload"]) {
                // 保存视频选项
                AWELongPressPanelBaseViewModel *downloadViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
                downloadViewModel.awemeModel = self.awemeModel;
                downloadViewModel.actionType = 666;
                downloadViewModel.duxIconName = @"ic_boxarrowdownhigh_outlined";
                downloadViewModel.describeString = @"保存视频";

                downloadViewModel.action = ^{
                    AWEAwemeModel *awemeModel = self.awemeModel;
                    AWEVideoModel *videoModel = awemeModel.video;
                    
                    if (videoModel && videoModel.h264URL && videoModel.h264URL.originURLList.count > 0) {
                        NSURL *url = [NSURL URLWithString:videoModel.h264URL.originURLList.firstObject];
                        [DYYYManager downloadMedia:url
                                        mediaType:DYYYMediaTypeVideo
                                        completion:^{
                                            [DYYYManager showToast:@"视频已保存到相册"];
                                        }];
                    }

                    AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
                    [panelManager dismissWithAnimation:YES completion:nil];
                };

                [viewModels addObject:downloadViewModel];
            }
        }

        // 检查是否启用了音频下载功能
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYLongPressAudioDownload"]) {
            // 保存音频选项
            AWELongPressPanelBaseViewModel *audioViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
            audioViewModel.awemeModel = self.awemeModel;
            audioViewModel.actionType = 668;
            audioViewModel.duxIconName = @"ic_boxarrowdownhigh_outlined";
            audioViewModel.describeString = @"保存音频";

            audioViewModel.action = ^{
                AWEAwemeModel *awemeModel = self.awemeModel;
                AWEMusicModel *musicModel = awemeModel.music;

                if (musicModel && musicModel.playURL && musicModel.playURL.originURLList.count > 0) {
                    NSURL *url = [NSURL URLWithString:musicModel.playURL.originURLList.firstObject];
                    [DYYYManager downloadMedia:url mediaType:DYYYMediaTypeAudio completion:nil];
                }

                AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
                [panelManager dismissWithAnimation:YES completion:nil];
            };

            [viewModels addObject:audioViewModel];
        }

        // 图集处理
        if (self.awemeModel.awemeType == 68 && self.awemeModel.albumImages.count > 0) {
            // 检查是否启用了图片下载功能或实况动图下载功能
            BOOL enableImageDownload = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYLongPressImageDownload"];
            BOOL enableLivePhotoDownload = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYLongPressLivePhotoDownload"];
            
            // 只有在相应功能开启时才添加菜单项
            if ((enableLivePhotoDownload || enableImageDownload)) {
                AWELongPressPanelBaseViewModel *imageViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
                imageViewModel.awemeModel = self.awemeModel;
                imageViewModel.actionType = 669;
                imageViewModel.duxIconName = @"ic_boxarrowdownhigh_outlined";
                imageViewModel.describeString = @"保存当前图片";

                imageViewModel.action = ^{
                    AWEAwemeModel *awemeModel = self.awemeModel;
                    AWEImageAlbumImageModel *currentImageModel = nil;

                    if (awemeModel.currentImageIndex > 0 && awemeModel.currentImageIndex <= awemeModel.albumImages.count) {
                        currentImageModel = awemeModel.albumImages[awemeModel.currentImageIndex - 1];
                    } else {
                        currentImageModel = awemeModel.albumImages.firstObject;
                    }

                    if (currentImageModel && currentImageModel.urlList.count > 0) {
                        NSURL *url = [NSURL URLWithString:currentImageModel.urlList.firstObject];
                        [DYYYManager downloadMedia:url
                                        mediaType:DYYYMediaTypeImage
                                        completion:^{
                                            [DYYYManager showToast:@"图片已保存到相册"];
                                        }];
                    }

                    AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
                    [panelManager dismissWithAnimation:YES completion:nil];
                };

                [viewModels addObject:imageViewModel];
            }

            if (self.awemeModel.albumImages.count > 1) {
                AWELongPressPanelBaseViewModel *allImagesViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
                allImagesViewModel.awemeModel = self.awemeModel;
                allImagesViewModel.actionType = 670;
                allImagesViewModel.duxIconName = @"ic_boxarrowdownhigh_outlined";
                allImagesViewModel.describeString = @"保存所有图片";

                allImagesViewModel.action = ^{
                    AWEAwemeModel *awemeModel = self.awemeModel;
                    NSMutableArray *imageURLs = [NSMutableArray array];

                    for (AWEImageAlbumImageModel *imageModel in awemeModel.albumImages) {
                        if (imageModel.urlList.count > 0) {
                            [imageURLs addObject:imageModel.urlList.firstObject];
                        }
                    }

                    if (imageURLs.count > 0) {
                        [DYYYManager downloadAllImages:imageURLs];
                    }

                    AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
                    [panelManager dismissWithAnimation:YES completion:nil];
                };

                [viewModels addObject:allImagesViewModel];
            }
        }
    }

    // 添加复制文案功能
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYCopyText"]) {
        AWELongPressPanelBaseViewModel *copyText = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        copyText.awemeModel = self.awemeModel;
        copyText.actionType = 671;
        copyText.duxIconName = @"ic_xiaoxihuazhonghua_outlined";
        copyText.describeString = @"复制文案";

        copyText.action = ^{
            NSString *descText = [self.awemeModel valueForKey:@"descriptionString"];
            [[UIPasteboard generalPasteboard] setString:descText];
            [DYYYManager showToast:@"文案已复制到剪贴板"];

            AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
            [panelManager dismissWithAnimation:YES completion:nil];
        };

        [viewModels addObject:copyText];

        // 新增复制分享链接
        AWELongPressPanelBaseViewModel *copyShareLink = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        copyShareLink.awemeModel = self.awemeModel;
        copyShareLink.actionType = 672;
        copyShareLink.duxIconName = @"ic_share_outlined";
        copyShareLink.describeString = @"复制分享链接";

        copyShareLink.action = ^{
            NSString *shareLink = [self.awemeModel valueForKey:@"shareURL"];
            [[UIPasteboard generalPasteboard] setString:shareLink];
            [DYYYManager showToast:@"分享链接已复制到剪贴板"];

            AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
            [panelManager dismissWithAnimation:YES completion:nil];
        };

        [viewModels addObject:copyShareLink];
    }

    // 添加接口保存功能
    NSString *apiKey = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYInterfaceDownload"];
    if (apiKey.length > 0) {
        AWELongPressPanelBaseViewModel *apiDownload = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        apiDownload.awemeModel = self.awemeModel;
        apiDownload.actionType = 673;
        apiDownload.duxIconName = @"ic_cloudarrowdown_outlined_20";
        apiDownload.describeString = @"接口保存";

        apiDownload.action = ^{
            NSString *shareLink = [self.awemeModel valueForKey:@"shareURL"];
            if (shareLink.length == 0) {
                [DYYYManager showToast:@"无法获取分享链接"];
                return;
            }

            // 使用封装的方法进行解析下载
            [DYYYManager parseAndDownloadVideoWithShareLink:shareLink apiKey:apiKey];

            AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
            [panelManager dismissWithAnimation:YES completion:nil];
        };

        [viewModels addObject:apiDownload];
    }

    newGroupModel.groupArr = viewModels;
    
    if (originalArray.count > 0) {
        NSMutableArray *resultArray = [originalArray mutableCopy];
        [resultArray insertObject:newGroupModel atIndex:0]; 
        return [resultArray copy];
    } else {
        return @[newGroupModel];
    }
}
%end

%hook AWEModernLongPressPanelTableViewController

- (NSArray *)dataArray {
    NSArray *originalArray = %orig;

    if (!originalArray) {
        originalArray = @[];
    }

    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYLongPressDownload"] && ![[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYCopyText"]) {
        return originalArray;
    }

    AWELongPressPanelViewGroupModel *newGroupModel = [[%c(AWELongPressPanelViewGroupModel) alloc] init];
    newGroupModel.groupType = 0;

    NSMutableArray *viewModels = [NSMutableArray array];

    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYLongPressDownload"]) {
        if (self.awemeModel.awemeType != 68) {
            // 检查是否启用了视频下载功能
            if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYLongPressVideoDownload"]) {
                AWELongPressPanelBaseViewModel *downloadViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
                downloadViewModel.awemeModel = self.awemeModel;
                downloadViewModel.actionType = 666;
                downloadViewModel.duxIconName = @"ic_boxarrowdownhigh_outlined";
                downloadViewModel.describeString = @"保存视频";

                downloadViewModel.action = ^{
                    AWEAwemeModel *awemeModel = self.awemeModel;
                    AWEVideoModel *videoModel = awemeModel.video;
                    
                    if (videoModel && videoModel.h264URL && videoModel.h264URL.originURLList.count > 0) {
                        NSURL *url = [NSURL URLWithString:videoModel.h264URL.originURLList.firstObject];
                        [DYYYManager downloadMedia:url
                                        mediaType:DYYYMediaTypeVideo
                                        completion:^{
                                            [DYYYManager showToast:@"视频已保存到相册"];
                                        }];
                    }

                    AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
                    [panelManager dismissWithAnimation:YES completion:nil];
                };

                [viewModels addObject:downloadViewModel];
            }
        }

        // 检查是否启用了音频下载功能
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYLongPressAudioDownload"]) {
            AWELongPressPanelBaseViewModel *audioViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
            audioViewModel.awemeModel = self.awemeModel;
            audioViewModel.actionType = 668;
            audioViewModel.duxIconName = @"ic_boxarrowdownhigh_outlined";
            audioViewModel.describeString = @"保存音频";

            audioViewModel.action = ^{
                AWEAwemeModel *awemeModel = self.awemeModel;
                AWEMusicModel *musicModel = awemeModel.music;

                if (musicModel && musicModel.playURL && musicModel.playURL.originURLList.count > 0) {
                    NSURL *url = [NSURL URLWithString:musicModel.playURL.originURLList.firstObject];
                    [DYYYManager downloadMedia:url mediaType:DYYYMediaTypeAudio completion:nil];
                }

                AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
                [panelManager dismissWithAnimation:YES completion:nil];
            };

            [viewModels addObject:audioViewModel];
        }

        if (self.awemeModel.awemeType == 68 && self.awemeModel.albumImages.count > 0) {
            // 检查是否启用了图片下载功能或实况动图下载功能
            BOOL enableImageDownload = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYLongPressImageDownload"];
            BOOL enableLivePhotoDownload = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYLongPressLivePhotoDownload"];
            
            // 获取当前图片模型
            AWEImageAlbumImageModel *currimge = self.awemeModel.albumImages[self.awemeModel.currentImageIndex - 1];
            BOOL isLivePhoto = (currimge.clipVideo != nil);
            
            // 只有在相应功能开启时才添加菜单项
            if ((isLivePhoto && enableLivePhotoDownload) || (!isLivePhoto && enableImageDownload)) {
                AWELongPressPanelBaseViewModel *imageViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
                imageViewModel.awemeModel = self.awemeModel;
                imageViewModel.actionType = 669;
                imageViewModel.duxIconName = @"ic_boxarrowdownhigh_outlined";
                
                if (isLivePhoto) {
                    imageViewModel.describeString = @"保存当前实况";
                } else {
                    imageViewModel.describeString = @"保存当前图片";
                }

                imageViewModel.action = ^{
                    AWEAwemeModel *awemeModel = self.awemeModel;
                    AWEImageAlbumImageModel *currentImageModel = nil;

                    if (awemeModel.currentImageIndex > 0 && awemeModel.currentImageIndex <= awemeModel.albumImages.count) {
                        currentImageModel = awemeModel.albumImages[awemeModel.currentImageIndex - 1];
                    } else {
                        currentImageModel = awemeModel.albumImages.firstObject;
                    }
                    
                    // 如果是实况照片
                    if (currentImageModel.clipVideo != nil) {
                        NSURL *url = [NSURL URLWithString:currentImageModel.urlList.firstObject];
                        NSURL *videoURL = [currentImageModel.clipVideo.playURL getDYYYSrcURLDownload];

                        [DYYYManager downloadLivePhoto:url
                                              videoURL:videoURL
                                            completion:^{
                                                [DYYYManager showToast:@"实况照片已保存到相册"];
                                            }];
                    } else if (currentImageModel && currentImageModel.urlList.count > 0) {
                        NSURL *url = [NSURL URLWithString:currentImageModel.urlList.firstObject];
                        [DYYYManager downloadMedia:url
                                        mediaType:DYYYMediaTypeImage
                                        completion:^{
                                            [DYYYManager showToast:@"图片已保存到相册"];
                                        }];
                    }

                    AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
                    [panelManager dismissWithAnimation:YES completion:nil];
                };

                [viewModels addObject:imageViewModel];
            }

            if (self.awemeModel.albumImages.count > 1) {
                // 检查是否有任何一个下载功能开启
                if (enableImageDownload || enableLivePhotoDownload) {
                    AWELongPressPanelBaseViewModel *allImagesViewModel = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
                    allImagesViewModel.awemeModel = self.awemeModel;
                    allImagesViewModel.actionType = 670;
                    allImagesViewModel.duxIconName = @"ic_boxarrowdownhigh_outlined";
                    allImagesViewModel.describeString = @"保存所有图片";

                    // 检查是否有实况照片并更改按钮文字
                    BOOL hasLivePhoto = NO;
                    for (AWEImageAlbumImageModel *imageModel in self.awemeModel.albumImages) {
                        if (imageModel.clipVideo != nil) {
                            hasLivePhoto = YES;
                            break;
                        }
                    }

                    if (hasLivePhoto) {
                        allImagesViewModel.describeString = @"保存所有实况";
                    }

                    allImagesViewModel.action = ^{
                        AWEAwemeModel *awemeModel = self.awemeModel;
                        NSMutableArray *imageURLs = [NSMutableArray array];

                        for (AWEImageAlbumImageModel *imageModel in awemeModel.albumImages) {
                            if (imageModel.urlList.count > 0) {
                                [imageURLs addObject:imageModel.urlList.firstObject];
                            }
                        }

                        // 检查是否有实况照片
                        BOOL hasLivePhoto = NO;
                        for (AWEImageAlbumImageModel *imageModel in awemeModel.albumImages) {
                            if (imageModel.clipVideo != nil) {
                                hasLivePhoto = YES;
                                break;
                            }
                        }

                        // 如果有实况照片，使用单独的downloadLivePhoto方法逐个下载
                        if (hasLivePhoto) {
                            NSMutableArray *livePhotos = [NSMutableArray array];
                            for (AWEImageAlbumImageModel *imageModel in awemeModel.albumImages) {
                                if (imageModel.urlList.count > 0 && imageModel.clipVideo != nil) {
                                    NSURL *photoURL = [NSURL URLWithString:imageModel.urlList.firstObject];
                                    NSURL *videoURL = [imageModel.clipVideo.playURL getDYYYSrcURLDownload];

                                    [livePhotos addObject:@{@"imageURL" : photoURL.absoluteString, @"videoURL" : videoURL.absoluteString}];
                                }
                            }

                            // 使用批量下载实况照片方法
                            [DYYYManager downloadAllLivePhotos:livePhotos];
                        } else if (imageURLs.count > 0) {
                            [DYYYManager downloadAllImages:imageURLs];
                        }

                        AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
                        [panelManager dismissWithAnimation:YES completion:nil];
                    };

                    [viewModels addObject:allImagesViewModel];
                }
            }
        }
    }

    // 添加复制文案功能
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYCopyText"]) {
        AWELongPressPanelBaseViewModel *copyText = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        copyText.awemeModel = self.awemeModel;
        copyText.actionType = 671;
        copyText.duxIconName = @"ic_xiaoxihuazhonghua_outlined";
        copyText.describeString = @"复制文案";

        copyText.action = ^{
            NSString *descText = [self.awemeModel valueForKey:@"descriptionString"];
            [[UIPasteboard generalPasteboard] setString:descText];
            [DYYYManager showToast:@"文案已复制到剪贴板"];

            AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
            [panelManager dismissWithAnimation:YES completion:nil];
        };

        [viewModels addObject:copyText];

        // 新增复制分享链接
        AWELongPressPanelBaseViewModel *copyShareLink = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        copyShareLink.awemeModel = self.awemeModel;
        copyShareLink.actionType = 672;
        copyShareLink.duxIconName = @"ic_share_outlined";
        copyShareLink.describeString = @"复制分享链接";

        copyShareLink.action = ^{
            NSString *shareLink = [self.awemeModel valueForKey:@"shareURL"];
            [[UIPasteboard generalPasteboard] setString:shareLink];
            [DYYYManager showToast:@"分享链接已复制到剪贴板"];

            AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
            [panelManager dismissWithAnimation:YES completion:nil];
        };

        [viewModels addObject:copyShareLink];
    }

    // 添加接口保存功能
    NSString *apiKey = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYInterfaceDownload"];
    if (apiKey.length > 0) {
        AWELongPressPanelBaseViewModel *apiDownload = [[%c(AWELongPressPanelBaseViewModel) alloc] init];
        apiDownload.awemeModel = self.awemeModel;
        apiDownload.actionType = 673;
        apiDownload.duxIconName = @"ic_cloudarrowdown_outlined_20";
        apiDownload.describeString = @"接口保存视频";

        apiDownload.action = ^{
            NSString *shareLink = [self.awemeModel valueForKey:@"shareURL"];
            if (shareLink.length == 0) {
                [DYYYManager showToast:@"无法获取分享链接"];
                return;
            }

            // 使用封装的方法进行解析下载
            [DYYYManager parseAndDownloadVideoWithShareLink:shareLink apiKey:apiKey];

            AWELongPressPanelManager *panelManager = [%c(AWELongPressPanelManager) shareInstance];
            [panelManager dismissWithAnimation:YES completion:nil];
        };

        [viewModels addObject:apiDownload];
    }

    newGroupModel.groupArr = viewModels;
    return [@[ newGroupModel ] arrayByAddingObjectsFromArray:originalArray];
}
%end

%hook DYYYManager

%new
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

%new
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

%end



static CGFloat stream_frame_y = 0;

%hook AWEElementStackView
static CGFloat right_tx = 0;
static CGFloat left_tx = 0;
static CGFloat currentScale = 1.0;

- (void)viewWillAppear:(BOOL)animated {
	%orig;
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisEnableFullScreen"]) {
		UIResponder *nextResponder = [self nextResponder];
		if ([nextResponder isKindOfClass:[UIView class]]) {
			UIView *parentView = (UIView *)nextResponder;
			UIViewController *viewController = [parentView firstAvailableUIViewController];

			if ([viewController isKindOfClass:%c(AWELiveNewPreStreamViewController)]) {
				CGRect frame = self.frame;
				if (stream_frame_y != 0) {
					frame.origin.y = stream_frame_y;
					self.frame = frame;
				}
			}
		}
	}
}

- (void)viewDidAppear:(BOOL)animated {
	%orig;
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisEnableFullScreen"]) {
		UIResponder *nextResponder = [self nextResponder];
		if ([nextResponder isKindOfClass:[UIView class]]) {
			UIView *parentView = (UIView *)nextResponder;
			UIViewController *viewController = [parentView firstAvailableUIViewController];

			if ([viewController isKindOfClass:%c(AWELiveNewPreStreamViewController)]) {
				CGRect frame = self.frame;
				if (stream_frame_y != 0) {
					frame.origin.y = stream_frame_y;
					self.frame = frame;
				}
			}
		}
	}
}

- (void)layoutSubviews {
	%orig;

	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisEnableFullScreen"]) {
		UIResponder *nextResponder = [self nextResponder];
		if ([nextResponder isKindOfClass:[UIView class]]) {
			UIView *parentView = (UIView *)nextResponder;
			UIViewController *viewController = [parentView firstAvailableUIViewController];

			if ([viewController isKindOfClass:%c(AWELiveNewPreStreamViewController)]) {
				CGRect frame = self.frame;
				frame.origin.y -= 83;
				stream_frame_y = frame.origin.y;
				self.frame = frame;
			}
		}
	}

	NSString *scaleValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYElementScale"];
	if ([self.accessibilityLabel isEqualToString:@"right"]) {

		self.transform = CGAffineTransformIdentity;

		if (scaleValue.length > 0) {
			CGFloat scale = [scaleValue floatValue];

			if (currentScale != scale) {
				currentScale = scale;
			}

			if (scale > 0 && scale != 1.0) {
				CGFloat ty = 0;

				for (UIView *view in self.subviews) {
					CGFloat viewHeight = view.frame.size.height;
					CGFloat contribution = (viewHeight - viewHeight * scale) / 2;
					ty += contribution;
				}

				CGFloat frameWidth = self.frame.size.width;
				right_tx = (frameWidth - frameWidth * scale) / 2;

				self.transform = CGAffineTransformMake(scale, 0, 0, scale, right_tx, ty);
			} else {
				self.transform = CGAffineTransformIdentity;
			}
		} else {
		}
	}

	if ([self.accessibilityLabel isEqualToString:@"left"]) {
		NSString *scaleValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYNicknameScale"];

		// 首先恢复到原始状态，确保变换不会累积
		self.transform = CGAffineTransformIdentity;

		if (scaleValue.length > 0) {
			CGFloat scale = [scaleValue floatValue];

			if (currentScale != scale) {
				currentScale = scale;
			}

			if (scale > 0 && scale != 1.0) {
				CGFloat ty = 0;

				for (UIView *view in self.subviews) {
					CGFloat viewHeight = view.frame.size.height;
					CGFloat contribution = (viewHeight - viewHeight * scale) / 2;
					ty += contribution;
				}

				CGFloat frameWidth = self.frame.size.width;
				left_tx = (frameWidth - frameWidth * scale) / 2 - frameWidth * (1 - scale);

				self.transform = CGAffineTransformMake(scale, 0, 0, scale, left_tx, ty);
			} else {
				self.transform = CGAffineTransformIdentity;
			}
		}
	}
}

%end

%hook AWEPlayInteractionDescriptionScrollView

- (void)layoutSubviews {
	%orig;

	self.transform = CGAffineTransformIdentity;

	// 添加文案垂直偏移支持
	NSString *descriptionOffsetValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYDescriptionVerticalOffset"];
	CGFloat verticalOffset = 0;
	if (descriptionOffsetValue.length > 0) {
		verticalOffset = [descriptionOffsetValue floatValue];
	}

	UIView *parentView = self.superview;
	UIView *grandParentView = nil;

	if (parentView) {
		grandParentView = parentView.superview;
	}
}

%end

%hook AWEPlayInteractionDescriptionLabel

- (void)layoutSubviews {
	%orig;

	self.transform = CGAffineTransformIdentity;

	// 添加文案垂直偏移支持
	NSString *descriptionOffsetValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYDescriptionVerticalOffset"];
	CGFloat verticalOffset = 0;
	if (descriptionOffsetValue.length > 0) {
		verticalOffset = [descriptionOffsetValue floatValue];
	}

	UIView *parentView = self.superview;
	UIView *grandParentView = nil;

	if (parentView) {
		grandParentView = parentView.superview;
	}
}

%end

%hook AWEUserNameLabel

- (void)layoutSubviews {
	%orig;

	self.transform = CGAffineTransformIdentity;

	// 添加垂直偏移支持
	NSString *verticalOffsetValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYNicknameVerticalOffset"];
	CGFloat verticalOffset = 0;
	if (verticalOffsetValue.length > 0) {
		verticalOffset = [verticalOffsetValue floatValue];
	}

	UIView *parentView = self.superview;
	UIView *grandParentView = nil;

	if (parentView) {
		grandParentView = parentView.superview;
	}

	// 检查祖父视图是否为 AWEBaseElementView 类型
	if (grandParentView && [grandParentView.superview isKindOfClass:%c(AWEBaseElementView)]) {
		CGRect scaledFrame = grandParentView.frame;
		CGFloat translationX = -scaledFrame.origin.x;

		CGAffineTransform translationTransform = CGAffineTransformMakeTranslation(translationX, verticalOffset);
		grandParentView.transform = translationTransform;
	}
}

%end

%hook AWEFeedVideoButton

- (void)setImage:(id)arg1 {
	NSString *nameString = nil;

	if ([self respondsToSelector:@selector(imageNameString)]) {
		nameString = [self performSelector:@selector(imageNameString)];
	}

	if (!nameString) {
		%orig;
		return;
	}

	NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
	NSString *dyyyFolderPath = [documentsPath stringByAppendingPathComponent:@"DYYY"];

	[[NSFileManager defaultManager] createDirectoryAtPath:dyyyFolderPath withIntermediateDirectories:YES attributes:nil error:nil];

	NSDictionary *iconMapping = @{
		@"icon_home_like_after" : @"like_after.png",
		@"icon_home_like_before" : @"like_before.png",
		@"icon_home_comment" : @"comment.png",
		@"icon_home_unfavorite" : @"unfavorite.png",
		@"icon_home_favorite" : @"favorite.png",
		@"iconHomeShareRight" : @"share.png"
	};

	NSString *customFileName = nil;
	if ([nameString containsString:@"_comment"]) {
		customFileName = @"comment.png";
	} else if ([nameString containsString:@"_like"]) {
		customFileName = @"like_before.png";
	} else if ([nameString containsString:@"_collect"]) {
		customFileName = @"unfavorite.png";
	} else if ([nameString containsString:@"_share"]) {
		customFileName = @"share.png";
	}

	for (NSString *prefix in iconMapping.allKeys) {
		if ([nameString hasPrefix:prefix]) {
			customFileName = iconMapping[prefix];
			break;
		}
	}

	if (customFileName) {
		NSString *customImagePath = [dyyyFolderPath stringByAppendingPathComponent:customFileName];

		if ([[NSFileManager defaultManager] fileExistsAtPath:customImagePath]) {
			UIImage *customImage = [UIImage imageWithContentsOfFile:customImagePath];
			if (customImage) {
				CGFloat targetWidth = 44.0;
				CGFloat targetHeight = 44.0;
				CGSize originalSize = customImage.size;

				CGFloat scale = MIN(targetWidth / originalSize.width, targetHeight / originalSize.height);
				CGFloat newWidth = originalSize.width * scale;
				CGFloat newHeight = originalSize.height * scale;

				UIGraphicsBeginImageContextWithOptions(CGSizeMake(newWidth, newHeight), NO, 0.0);
				[customImage drawInRect:CGRectMake(0, 0, newWidth, newHeight)];
				UIImage *resizedImage = UIGraphicsGetImageFromCurrentImageContext();
				UIGraphicsEndImageContext();

				if (resizedImage) {
					%orig(resizedImage);
					return;
				}
			}
		}
	}

	%orig;
}

%end

%hook AWECommentMediaDownloadConfigLivePhoto

bool commentLivePhotoNotWaterMark = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYCommentLivePhotoNotWaterMark"];

- (bool)needClientWaterMark {
	return commentLivePhotoNotWaterMark ? 0 : %orig;
}

- (bool)needClientEndWaterMark {
	return commentLivePhotoNotWaterMark ? 0 : %orig;
}

- (id)watermarkConfig {
	return commentLivePhotoNotWaterMark ? nil : %orig;
}

%end

%hook AWECommentImageModel
- (id)downloadUrl {
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYCommentNotWaterMark"]) {
		return self.originUrl;
	}
	return %orig;
}
%end

%hook _TtC33AWECommentLongPressPanelSwiftImpl37CommentLongPressPanelSaveImageElement

static BOOL isDownloadFlied = NO;

-(BOOL)elementShouldShow{
    BOOL DYYYForceDownloadEmotion = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYForceDownloadEmotion"];
    if(DYYYForceDownloadEmotion){
        AWECommentLongPressPanelContext *commentPageContext = [self commentPageContext];
        AWECommentModel *selectdComment = [commentPageContext selectdComment];
        if(!selectdComment){
            AWECommentLongPressPanelParam *params = [commentPageContext params];
            selectdComment = [params selectdComment];
        }
        AWEIMStickerModel *sticker = [selectdComment sticker];
        if(sticker){
            AWEURLModel *staticURLModel = [sticker staticURLModel];
            NSArray *originURLList = [staticURLModel originURLList];
            if (originURLList.count > 0) {
                return YES;
            }
        }
    }
    return %orig;
}

-(void)elementTapped{
    BOOL DYYYForceDownloadEmotion = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYForceDownloadEmotion"];
    if(DYYYForceDownloadEmotion){
        AWECommentLongPressPanelContext *commentPageContext = [self commentPageContext];
        AWECommentModel *selectdComment = [commentPageContext selectdComment];
        if(!selectdComment){
            AWECommentLongPressPanelParam *params = [commentPageContext params];
            selectdComment = [params selectdComment];
        }
        AWEIMStickerModel *sticker = [selectdComment sticker];
        if(sticker){
            AWEURLModel *staticURLModel = [sticker staticURLModel];
            NSArray *originURLList = [staticURLModel originURLList];
            if (originURLList.count > 0) {
                NSString *urlString = @"";
                if(isDownloadFlied){
                    urlString = originURLList[originURLList.count-1];
                    isDownloadFlied = NO;
                }else{
                    urlString = originURLList[0];
                }

                NSURL *heifURL = [NSURL URLWithString:urlString];
                [DYYYManager downloadMedia:heifURL mediaType:MediaTypeHeic completion:^{
                    [DYYYManager showToast:@"表情包已保存到相册"];
                }];
                return;
            }
        }
    }
    %orig;
}
%end

%hook _TtC33AWECommentLongPressPanelSwiftImpl32CommentLongPressPanelCopyElement

-(void)elementTapped{
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYEnableCommentCopyText"]) {
        AWECommentLongPressPanelContext *commentPageContext = [self commentPageContext];
        AWECommentModel *selectdComment = [commentPageContext selectdComment];
        if(!selectdComment){
            AWECommentLongPressPanelParam *params = [commentPageContext params];
            selectdComment = [params selectdComment];
        }
        NSString *descText = [selectdComment content];
        [[UIPasteboard generalPasteboard] setString:descText];
        [DYYYManager showToast:@"文案已复制到剪贴板"];
    }
}
%end

// 去除启动视频广告
%hook AWEAwesomeSplashFeedCellOldAccessoryView

// 在方法入口处添加控制逻辑
- (id)ddExtraView {
	// 检查用户是否启用了无广告模式
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYNoAds"]) {
		return NULL; // 返回空视图
	}

	// 正常模式调用原始方法
	return %orig;
}

%end

// 隐藏关注直播
%hook AWEConcernSkylightCapsuleView
- (void)setHidden:(BOOL)hidden {
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideConcernCapsuleView"]) {
		[self removeFromSuperview];
		return;
	}

	%orig(hidden);
}
%end

// 隐藏直播发现
%hook AWEFeedLiveTabRevisitControlView

- (void)layoutSubviews {
	%orig;

	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideLiveDiscovery"]) {
		if ([self respondsToSelector:@selector(removeFromSuperview)]) {
			[self removeFromSuperview];
		}
		self.hidden = YES;
		return;
	}
}
%end

// 隐藏直播点歌
%hook IESLiveKTVSongIndicatorView
- (void)layoutSubviews {
	%orig;
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideKTVSongIndicator"]) {
		self.hidden = YES;
		[self removeFromSuperview];
	}
}
%end

// 隐藏图片滑条
%hook AWEStoryProgressContainerView
- (BOOL)isHidden {
	BOOL originalValue = %orig;
	BOOL customHide = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideDotsIndicator"];
	return originalValue || customHide;
}

- (void)setHidden:(BOOL)hidden {
	BOOL forceHide = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideDotsIndicator"];
	%orig(forceHide ? YES : hidden);
}
%end

// 去广告功能
%hook AwemeAdManager
- (void)showAd {
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYNoAds"])
		return;
	%orig;
}
%end

// 隐藏顶栏关注下的提示线
%hook AWEFeedMultiTabSelectedContainerView

- (void)setHidden:(BOOL)hidden {
	BOOL forceHide = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHidentopbarprompt"];

	if (forceHide) {
		%orig(YES);
	} else {
		%orig(hidden);
	}
}

%end

%hook AFDRecommendToFriendEntranceLabel
- (void)layoutSubviews {
	%orig;
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideRecommendTips"]) {
		UIView *parentView = self.superview;
		if (parentView) {
			parentView.hidden = YES;
		} else {
			self.hidden = YES;
		}
	}
}

%end

// 隐藏自己无公开作品的视图
%hook AWEProfileMixCollectionViewCell
- (void)layoutSubviews {
	%orig;
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHidePostView"]) {
		self.hidden = YES;
	}
}
%end

// 隐藏关注直播顶端
%hook AWENewLiveSkylightViewController

// 隐藏顶部直播视图 - 添加条件判断
- (void)showSkylight:(BOOL)arg0 animated:(BOOL)arg1 actionMethod:(unsigned long long)arg2 {
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHidenLiveView"]) {
		return;
	}
	%orig(arg0, arg1, arg2);
}

- (void)updateIsSkylightShowing:(BOOL)arg0 {
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHidenLiveView"]) {
		%orig(NO);
	} else {
		%orig(arg0);
	}
}

%end

// 隐藏同城顶端
%hook AWENearbyFullScreenViewModel

- (void)setShowSkyLight:(id)arg1 {
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideMenuView"]) {
		arg1 = nil;
	}
	%orig(arg1);
}

- (void)setHaveSkyLight:(id)arg1 {
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideMenuView"]) {
		arg1 = nil;
	}
	%orig(arg1);
}

%end

%hook AWEProfileTaskCardStyleListCollectionViewCell
- (void)layoutSubviews {
	%orig;
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHidePostView"]) {
		self.hidden = YES;
	}
}
%end

// 隐藏笔记
%hook AWECorrelationItemTag

- (void)layoutSubviews {
	%orig;
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideItemTag"]) {
		self.frame = CGRectMake(0, 0, 0, 0);
		self.hidden = YES;
	}
}

%end

// 隐藏话题
%hook AWEPlayInteractionTemplateButtonGroup
- (void)layoutSubviews {
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideTemplateGroup"]) {
		if ([self respondsToSelector:@selector(removeFromSuperview)]) {
			[self removeFromSuperview];
		}
		self.hidden = YES;
		return;
	}
	%orig;
}
%end

%hook AWEURLModel
%new
- (NSURL *)getDYYYSrcURLDownload {
    if (!self.originURLList || self.originURLList.count == 0) return nil;
    
    NSURL *bestURL = nil;
    
    for (NSString *url in self.originURLList) {
        if ([url containsString:@"watermark=0"] || 
            [url containsString:@"remove_watermark=1"] || 
            [url containsString:@"noWatermark=1"]) {
            bestURL = [NSURL URLWithString:url];
            break;
        }
    }
    
    if (!bestURL) {
        for (NSString *url in self.originURLList) {
            if ([url containsString:@"video_mp4"] || 
                [url hasSuffix:@".mp4"] || 
                [url hasSuffix:@".mov"] ||
                [url hasSuffix:@".m4v"] ||
                [url hasSuffix:@".avi"] ||
                [url hasSuffix:@".wmv"] ||
                [url hasSuffix:@".flv"] ||
                [url hasSuffix:@".mkv"] ||
                [url hasSuffix:@".webm"] ||
                [url containsString:@"/video/"] ||
                [url containsString:@"type=video"]) {
                bestURL = [NSURL URLWithString:url];
                break;
            }
            
            if ([url hasSuffix:@".jpeg"] || 
                [url hasSuffix:@".jpg"] ||
                [url hasSuffix:@".png"] ||
                [url hasSuffix:@".gif"] ||
                [url hasSuffix:@".webp"] ||
                [url hasSuffix:@".heic"] ||
                [url hasSuffix:@".tiff"] ||
                [url hasSuffix:@".bmp"] ||
                [url containsString:@"/image/"] ||
                [url containsString:@"type=image"]) {
                bestURL = [NSURL URLWithString:url];
                break;
            }
            
            if ([url hasSuffix:@".mp3"] || 
                [url hasSuffix:@".m4a"] ||
                [url hasSuffix:@".wav"] ||
                [url hasSuffix:@".aac"] ||
                [url hasSuffix:@".ogg"] ||
                [url hasSuffix:@".flac"] ||
                [url hasSuffix:@".alac"] ||
                [url hasSuffix:@".aiff"] ||
                [url containsString:@"/audio/"] ||
                [url containsString:@"type=audio"]) {
                bestURL = [NSURL URLWithString:url];
                break;
            }
        }
    }
    
    if (!bestURL) {
        NSString *highestRes = nil;
        int highestValue = 0;
        
        for (NSString *url in self.originURLList) {
            NSArray *resMarkers = @[@"1080p", @"720p", @"4k", @"2k", @"uhd", @"hd", @"high", @"best"];
            for (NSString *marker in resMarkers) {
                if ([url.lowercaseString containsString:marker.lowercaseString]) {
                    int value = 0;
                    if ([marker isEqualToString:@"4k"] || [marker isEqualToString:@"uhd"]) value = 4;
                    else if ([marker isEqualToString:@"2k"]) value = 3;
                    else if ([marker isEqualToString:@"1080p"]) value = 2;
                    else if ([marker isEqualToString:@"720p"] || [marker isEqualToString:@"hd"]) value = 1;
                    else value = 0;
                    
                    if (value > highestValue) {
                        highestValue = value;
                        highestRes = url;
                    }
                    break;
                }
            }
        }
        
        if (highestRes) {
            bestURL = [NSURL URLWithString:highestRes];
        }
    }
    
    if (!bestURL) {
        NSString *highestQuality = nil;
        int highestScore = 0;
        
        for (NSString *url in self.originURLList) {
            NSURLComponents *components = [NSURLComponents componentsWithString:url];
            for (NSURLQueryItem *item in components.queryItems) {
                if ([item.name.lowercaseString containsString:@"quality"] || 
                    [item.name.lowercaseString containsString:@"definition"] ||
                    [item.name.lowercaseString containsString:@"resolution"]) {
                    NSString *value = item.value.lowercaseString;
                    int score = 0;
                    
                    if ([value containsString:@"high"]) score += 3;
                    if ([value containsString:@"medium"]) score += 2;
                    if ([value containsString:@"low"]) score += 1;
                    
                    if (score > highestScore) {
                        highestScore = score;
                        highestQuality = url;
                    }
                }
            }
        }
        
        if (highestQuality) {
            bestURL = [NSURL URLWithString:highestQuality];
        }
    }
    
	if (!bestURL) {
		NSString *largestFile = nil;
		long long maxSize = 0;
		
		for (NSString *url in self.originURLList) {
			NSURLComponents *components = [NSURLComponents componentsWithString:url];
			for (NSURLQueryItem *item in components.queryItems) {
				if ([item.name.lowercaseString containsString:@"size"] || 
					[item.name.lowercaseString containsString:@"bitrate"] ||
					[item.name.lowercaseString containsString:@"rate"]) {
					long long size = [item.value longLongValue];
					if (size > maxSize) {
						maxSize = size;
						largestFile = url;
					}
				}
			}
		}
		
		if (largestFile) {
			bestURL = [NSURL URLWithString:largestFile];
		}
	}
    
    if (!bestURL && self.originURLList.count > 0) {
        bestURL = [NSURL URLWithString:self.originURLList.lastObject];
    }
    
    if (!bestURL && self.originURLList.count > 0) {
        bestURL = [NSURL URLWithString:self.originURLList.firstObject];
    }
    
    if (bestURL && bestURL.scheme && bestURL.host) {
        return bestURL;
    } else if (self.originURLList.count > 0) {
        return [NSURL URLWithString:self.originURLList.lastObject];
    }
    
    return nil;
}
%end

// 禁用点击首页刷新
%hook AWENormalModeTabBarGeneralButton

- (BOOL)enableRefresh {
	if ([self.accessibilityLabel isEqualToString:@"首页"]) {
		if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYDisableHomeRefresh"]) {
			return NO;
		}
	}
	return %orig;
}

%end

// 屏蔽版本更新
%hook AWEVersionUpdateManager

- (void)startVersionUpdateWorkflow:(id)arg1 completion:(id)arg2 {
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYNoUpdates"]) {
		if (arg2) {
			void (^completionBlock)(void) = arg2;
			completionBlock();
		}
	} else {
		%orig;
	}
}

- (id)workflow {
	return [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYNoUpdates"] ? nil : %orig;
}

- (id)badgeModule {
	return [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYNoUpdates"] ? nil : %orig;
}

%end

// 强制启用保存他人头像
%hook AFDProfileAvatarFunctionManager
- (BOOL)shouldShowSaveAvatarItem {
	BOOL shouldEnable = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYEnableSaveAvatar"];
	if (shouldEnable) {
		return YES;
	}
	return %orig;
}
%end

// 应用内推送毛玻璃效果
%hook AWEInnerNotificationWindow

- (id)initWithFrame:(CGRect)frame {
	id orig = %orig;
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYEnableNotificationTransparency"]) {
		[self setupBlurEffectForNotificationView];
	}
	return orig;
}

- (void)layoutSubviews {
	%orig;
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYEnableNotificationTransparency"]) {
		[self setupBlurEffectForNotificationView];
	}
}

- (void)didMoveToWindow {
	%orig;
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYEnableNotificationTransparency"]) {
		[self setupBlurEffectForNotificationView];
	}
}

- (void)didAddSubview:(UIView *)subview {
	%orig;
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYEnableNotificationTransparency"] && [NSStringFromClass([subview class]) containsString:@"AWEInnerNotificationContainerView"]) {
		[self setupBlurEffectForNotificationView];
	}
}

%new
- (void)setupBlurEffectForNotificationView {
	for (UIView *subview in self.subviews) {
		if ([NSStringFromClass([subview class]) containsString:@"AWEInnerNotificationContainerView"]) {
			[self applyBlurEffectToView:subview];
			break;
		}
	}
}

%new
- (void)applyBlurEffectToView:(UIView *)containerView {
	if (!containerView) {
		return;
	}

	containerView.backgroundColor = [UIColor clearColor];

	float userRadius = [[[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYNotificationCornerRadius"] floatValue];
	if (userRadius < 0 || userRadius > 50) {
		userRadius = 12;
	}

	containerView.layer.cornerRadius = userRadius;
	containerView.layer.masksToBounds = YES;

	for (UIView *subview in containerView.subviews) {
		if ([subview isKindOfClass:[UIVisualEffectView class]] && subview.tag == 999) {
			[subview removeFromSuperview];
		}
	}

	BOOL isDarkMode = [DYYYManager isDarkMode];
	UIBlurEffectStyle blurStyle = isDarkMode ? UIBlurEffectStyleDark : UIBlurEffectStyleLight;
	UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:blurStyle];
	UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];

	blurView.frame = containerView.bounds;
	blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	blurView.tag = 999;
	blurView.layer.cornerRadius = userRadius;
	blurView.layer.masksToBounds = YES;

	float userTransparency = [[[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYCommentBlurTransparent"] floatValue];
	if (userTransparency <= 0 || userTransparency > 1) {
		userTransparency = 0.5;
	}

	blurView.alpha = userTransparency;

	[containerView insertSubview:blurView atIndex:0];

	[self clearBackgroundRecursivelyInView:containerView];

	if (isDarkMode) {
		[self setLabelsColorWhiteInView:containerView];
	}
}

%new
- (void)setLabelsColorWhiteInView:(UIView *)view {
	for (UIView *subview in view.subviews) {
		if ([subview isKindOfClass:[UILabel class]]) {
			UILabel *label = (UILabel *)subview;
			NSString *text = label.text;

			if (![text isEqualToString:@"回复"] && (![text isEqualToString:@"查看"] && ![text isEqualToString:@"续火花"])) {
				label.textColor = [UIColor whiteColor];
			}
		}
		[self setLabelsColorWhiteInView:subview];
	}
}

%new
- (void)clearBackgroundRecursivelyInView:(UIView *)view {
	for (UIView *subview in view.subviews) {
		if ([subview isKindOfClass:[UIVisualEffectView class]] && subview.tag == 999 && [subview isKindOfClass:[UIButton class]]) {
			continue;
		}
		subview.backgroundColor = [UIColor clearColor];
		subview.opaque = NO;
		[self clearBackgroundRecursivelyInView:subview];
	}
}

%end

%hook AWESettingsViewModel

- (NSArray *)sectionDataArray {
    NSArray *originalSections = %orig;
    
    BOOL sectionExists = NO;
    for (AWESettingSectionModel *section in originalSections) {
        if ([section.sectionHeaderTitle isEqualToString:@"DYYY"]) {
            sectionExists = YES;
            break;
        }
    }
    
    if (!sectionExists) {
        AWESettingItemModel *dyyyItem = [[%c(AWESettingItemModel) alloc] init];
        dyyyItem.identifier = @"DYYY";
        dyyyItem.title = @"DYYY";
        dyyyItem.detail = @"v2.1-7++";
        dyyyItem.type = 0;
        dyyyItem.iconImageName = @"noticesettting_like";
        dyyyItem.cellType = 26;
        dyyyItem.colorStyle = 2;
        dyyyItem.isEnable = YES;
        
        dyyyItem.cellTappedBlock = ^{
            UIViewController *rootViewController = self.controllerDelegate;
            if (!rootViewController) {
                return;
            }
            
            DYYYSettingViewController *settingVC = [[DYYYSettingViewController alloc] init];
            if (rootViewController.navigationController) {
                [rootViewController.navigationController pushViewController:settingVC animated:YES];
            } else {
                UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:settingVC];
                navController.modalPresentationStyle = UIModalPresentationFullScreen;
                [rootViewController presentViewController:navController animated:YES completion:nil];
            }
        };
        
        AWESettingSectionModel *dyyySection = [[%c(AWESettingSectionModel) alloc] init];
        dyyySection.sectionHeaderTitle = @"DYYY";
        dyyySection.sectionHeaderHeight = 40;
        dyyySection.type = 0;
        dyyySection.itemArray = @[dyyyItem];
        
        NSMutableArray<AWESettingSectionModel *> *newSections = [NSMutableArray arrayWithArray:originalSections];
        [newSections insertObject:dyyySection atIndex:0];
        
        return newSections;
    }
    
    return originalSections;
}

%end


@interface AWEPlayInteractionTimestampElement (DYYYCitySelectorProtocol) <CitySelectorDelegate>
- (void)showCitySelector;
- (void)showDateTimeFormatSelector;
- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)citySelectorDidSelect:(NSString *)provinceCode 
                 provinceName:(NSString *)provinceName 
                     cityCode:(NSString *)cityCode 
                     cityName:(NSString *)cityName 
                 districtCode:(NSString *)districtCode 
                 districtName:(NSString *)districtName;
@end

%hook AWEPlayInteractionTimestampElement

static CLLocationManager *locationManager = nil;

+ (void)initialize {
    if (!locationManager) {
        locationManager = [[CLLocationManager alloc] init];
        [locationManager requestWhenInUseAuthorization];
    }
    // 设置默认 NSUserDefaults 值
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        @"DYYYisEnableArea": @YES,
        @"DYYYShowDateTime": @YES,
        @"DYYYisEnableAreaProvince": @YES,
        @"DYYYisEnableAreaCity": @YES,
        @"DYYYisEnableAreaDistrict": @YES,
        @"DYYYisEnableAreaStreet": @YES,
        @"DYYYDateTimeFormat_YMDHM": @YES // 默认启用年-月-日 时:分格式
    }];
}

- (id)timestampLabel {
    UILabel *label = %orig;
    
    // 准备第一行显示日期时间
    NSString *firstLine = @"";
    NSString *secondLine = @"";
    
    // 处理时间和日期显示
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYShowDateTime"]) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        
        // 根据子开关决定日期格式
        NSString *dateFormat = @"yyyy-MM-dd HH:mm"; // 默认格式
        
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYDateTimeFormat_YMDHM"]) {
            dateFormat = @"yyyy-MM-dd HH:mm";
        } else if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYDateTimeFormat_MDHM"]) {
            dateFormat = @"MM-dd HH:mm";
        } else if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYDateTimeFormat_HMS"]) {
            dateFormat = @"HH:mm:ss";
        } else if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYDateTimeFormat_HM"]) {
            dateFormat = @"HH:mm";
        } else if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYDateTimeFormat_YMD"]) {
            dateFormat = @"yyyy-MM-dd";
        } else {
            // 检查是否有旧的格式设置
            NSString *oldFormat = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYDateTimeFormat"];
            if (oldFormat && oldFormat.length > 0) {
                dateFormat = oldFormat;
            }
        }
        
        formatter.dateFormat = dateFormat;
        
        // 使用视频发布时间而不是当前时间
        NSDate *creationDate = nil;
        NSNumber *createTimeStamp = [self.model valueForKey:@"createTime"];
        if (createTimeStamp) {
            // 时间戳转换为日期
            creationDate = [NSDate dateWithTimeIntervalSince1970:[createTimeStamp doubleValue]];
        } else {
            // 回退到原始标签文本中可能包含的时间信息
            NSString *originalText = label.text;
            if (originalText && originalText.length > 0) {
                firstLine = originalText;
            } else {
                creationDate = [NSDate date]; // 作为最后的回退选项
            }
        }
        
        if (creationDate) {
            firstLine = [formatter stringFromDate:creationDate];
        }
    }
    
    // 处理自定义属地，放在第二行
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisEnableArea"]) {
        NSString *cityCode = self.model.cityCode;
        NSString *customCityCode = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYCustomCityCode"];
        
        // 检查是否使用自定义属地
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYEnableCustomArea"] && customCityCode) {
            cityCode = customCityCode;
        }
        
        CityManager *cityManager = [CityManager sharedInstance];
        NSString *locationPrefix = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYLocationPrefix"] ?: @"IP:";
        NSMutableString *location = [NSMutableString stringWithString:locationPrefix];
        
        // 生成四级地址
        NSString *fourLevelAddress = [cityManager generateRandomFourLevelAddressForCityCode:cityCode];
        
        if (fourLevelAddress.length > 0) {
            [location appendString:fourLevelAddress];
        } else {
            [location appendString:@"未知地区"];
        }
        
        // 设置第二行文本
        if (location.length > locationPrefix.length) {
            secondLine = location;
        }
    }
    
    // 如果有两行内容，设置为多行显示
    if (secondLine.length > 0) {
        label.numberOfLines = 2;
        label.textAlignment = NSTextAlignmentLeft;
        label.lineBreakMode = NSLineBreakByWordWrapping;
        
        // 组合成两行文本
        label.text = [NSString stringWithFormat:@"%@\n%@", firstLine, secondLine];
        
        // 动态调整标签大小
        CGSize textSize = [label.text boundingRectWithSize:CGSizeMake(label.frame.size.width, CGFLOAT_MAX)
                                                  options:NSStringDrawingUsesLineFragmentOrigin
                                               attributes:@{NSFontAttributeName: label.font}
                                                  context:nil].size;
        CGRect frame = label.frame;
        frame.size.height = textSize.height + 10;
        label.frame = frame;
        
        // 设置段落样式
        NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
        paragraphStyle.alignment = NSTextAlignmentLeft;
        paragraphStyle.lineBreakMode = NSLineBreakByWordWrapping;
        
        NSMutableAttributedString *attributedText = [[NSMutableAttributedString alloc] initWithString:label.text];
        [attributedText addAttribute:NSParagraphStyleAttributeName 
                              value:paragraphStyle 
                              range:NSMakeRange(0, label.text.length)];
        
        label.attributedText = attributedText;
    } else {
        label.numberOfLines = 1;
        label.text = firstLine;
        label.textAlignment = NSTextAlignmentLeft;
    }
    
    // 设置标签颜色
    NSString *labelColor = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYLabelColor"];
    if (labelColor.length > 0) {
        label.textColor = [DYYYManager colorWithHexString:labelColor];
    }
    
    // 添加长按手势
    if (!objc_getAssociatedObject(label, "hasLongPressGesture")) {
        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] 
                                                 initWithTarget:self 
                                                 action:@selector(handleLongPress:)];
        [label addGestureRecognizer:longPress];
        label.userInteractionEnabled = YES;
        objc_setAssociatedObject(label, "hasLongPressGesture", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    
    return label;
}

// 显示城市选择器
%new
- (void)showCitySelector {
    NSString *savedCityCode = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYCustomCityCode"];
    UIViewController *topVC = [DYYYManager getActiveTopController];
    if (topVC) {
        [[CityManager sharedInstance] showCitySelectorInViewController:topVC 
                                                             delegate:(id<CitySelectorDelegate>)self
                                                 initialSelectedCode:savedCityCode];
    } else {
        [DYYYManager showToast:@"无法打开选择器：找不到顶层视图控制器"];
    }
}

// 显示日期时间格式选择器 - 保留该方法用于长按菜单
%new
- (void)showDateTimeFormatSelector {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"选择日期时间格式" 
                                                                  message:@"请选择一种格式（也可在设置中选择）" 
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    
    NSArray *formats = @[
        @{@"name": @"年-月-日 时:分", @"format": @"yyyy-MM-dd HH:mm", @"key": @"DYYYDateTimeFormat_YMDHM"},
        @{@"name": @"月-日 时:分", @"format": @"MM-dd HH:mm", @"key": @"DYYYDateTimeFormat_MDHM"},
        @{@"name": @"时:分:秒", @"format": @"HH:mm:ss", @"key": @"DYYYDateTimeFormat_HMS"},
        @{@"name": @"时:分", @"format": @"HH:mm", @"key": @"DYYYDateTimeFormat_HM"},
        @{@"name": @"年-月-日", @"format": @"yyyy-MM-dd", @"key": @"DYYYDateTimeFormat_YMD"}
    ];
    
    for (NSDictionary *formatInfo in formats) {
        [alert addAction:[UIAlertAction actionWithTitle:formatInfo[@"name"]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
            // 关闭所有格式开关
            for (NSDictionary *format in formats) {
                [[NSUserDefaults standardUserDefaults] setBool:NO forKey:format[@"key"]];
            }
            
            // 打开选中的格式开关
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:formatInfo[@"key"]];
            
            // 保留旧的格式键以保持兼容性
            [[NSUserDefaults standardUserDefaults] setObject:formatInfo[@"format"] forKey:@"DYYYDateTimeFormat"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            
            [DYYYManager showToast:[NSString stringWithFormat:@"已设置日期时间格式: %@", formatInfo[@"name"]]];
        }]];
    }
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    UIViewController *topVC = [DYYYManager getActiveTopController];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        UIView *sourceView = topVC.view;
        alert.popoverPresentationController.sourceView = sourceView;
        alert.popoverPresentationController.sourceRect = CGRectMake(sourceView.bounds.size.width / 2, 
                                                                   sourceView.bounds.size.height / 2, 
                                                                   0, 0);
    }
    
    [topVC presentViewController:alert animated:YES completion:nil];
}

// 处理城市选择结果
%new
- (void)citySelectorDidSelect:(NSString *)provinceCode 
                 provinceName:(NSString *)provinceName 
                     cityCode:(NSString *)cityCode 
                     cityName:(NSString *)cityName 
                 districtCode:(NSString *)districtCode 
                 districtName:(NSString *)districtName {
    NSString *selectedCode = cityCode ?: provinceCode;
    if (selectedCode) {
        [[NSUserDefaults standardUserDefaults] setObject:selectedCode forKey:@"DYYYCustomCityCode"];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"DYYYEnableCustomArea"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        
        NSString *location = (provinceName.length > 0 && cityName.length > 0) 
            ? [NSString stringWithFormat:@"%@ %@", provinceName, cityName] 
            : (cityName ?: provinceName);
        [DYYYManager showToast:[NSString stringWithFormat:@"已设置属地为: %@", location]];
    }
}

// 处理长按事件
%new
- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"时间和属地设置" 
                                                                  message:@"请选择操作" 
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    
    // 时间日期选项
    BOOL dateTimeEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYShowDateTime"];
    NSString *dateTimeTitle = dateTimeEnabled ? @"关闭日期时间显示" : @"开启日期时间显示";
    
    [alert addAction:[UIAlertAction actionWithTitle:dateTimeTitle
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [[NSUserDefaults standardUserDefaults] setBool:!dateTimeEnabled forKey:@"DYYYShowDateTime"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [DYYYManager showToast:dateTimeEnabled ? @"已关闭日期时间显示" : @"已更新设置"];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"设置日期时间格式"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [self showDateTimeFormatSelector];
    }]];
    
    // 属地设置选项
    [alert addAction:[UIAlertAction actionWithTitle:@"选择自定义属地"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [self showCitySelector];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"使用默认属地" 
                                              style:UIAlertActionStyleDefault 
                                            handler:^(UIAlertAction *action) {
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"DYYYEnableCustomArea"];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"DYYYCustomCityCode"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [DYYYManager showToast:@"已恢复默认属地"];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" 
                                              style:UIAlertActionStyleCancel 
                                            handler:nil]];
    
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = gesture.view;
        alert.popoverPresentationController.sourceRect = gesture.view.bounds;
    }
    
    UIViewController *topVC = [DYYYManager getActiveTopController];
    [topVC presentViewController:alert animated:YES completion:nil];
}

+ (BOOL)shouldActiveWithData:(id)arg1 context:(id)arg2 {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisEnableArea"] || 
           [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYShowDateTime"];
}

%end

// 添加观察者来确保日期时间格式开关的互斥性
%hook NSUserDefaults

- (void)setBool:(BOOL)value forKey:(NSString *)defaultName {
    // 处理日期时间格式子开关的互斥性
    if ([defaultName hasPrefix:@"DYYYDateTimeFormat_"] && value) {
        NSArray *formatKeys = @[
            @"DYYYDateTimeFormat_YMDHM",
            @"DYYYDateTimeFormat_MDHM", 
            @"DYYYDateTimeFormat_HMS",
            @"DYYYDateTimeFormat_HM",
            @"DYYYDateTimeFormat_YMD"
        ];
        
        // 关闭其他格式开关
        for (NSString *key in formatKeys) {
            if (![key isEqualToString:defaultName]) {
                %orig(NO, key);
            }
        }
        
        // 设置相应的格式到原始的格式键
        NSDictionary *formatMapping = @{
            @"DYYYDateTimeFormat_YMDHM": @"yyyy-MM-dd HH:mm",
            @"DYYYDateTimeFormat_MDHM": @"MM-dd HH:mm",
            @"DYYYDateTimeFormat_HMS": @"HH:mm:ss",
            @"DYYYDateTimeFormat_HM": @"HH:mm",
            @"DYYYDateTimeFormat_YMD": @"yyyy-MM-dd"
        };
        
        NSString *format = formatMapping[defaultName];
        if (format) {
            [self setObject:format forKey:@"DYYYDateTimeFormat"];
        }
    }
    
    %orig;
}

%end

%ctor {
    %init;
    
    if (%c(AWECommentPanelHeaderSwiftImpl_CommentHeaderGeneralView)) {
        %init(CommentHeaderGeneralGroup);
    }
    
    if (%c(AWECommentPanelHeaderSwiftImpl_CommentHeaderGoodsView)) {
        %init(CommentHeaderGoodsGroup);
    }
    
    if (%c(AWECommentPanelHeaderSwiftImpl_CommentHeaderTemplateAnchorView)) {
        %init(CommentHeaderTemplateGroup);
    }
}