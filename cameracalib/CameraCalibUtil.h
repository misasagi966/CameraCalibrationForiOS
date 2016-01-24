//
//  CameraCalibUtil.h
//  cameracalib
//
//  Created by Ryota Nakai on 2015/11/11.
//  Copyright © 2015年 Ryota Nakai. All rights reserved.
//


#define IMAGE_NUM  (25)         /* 画像数 */
#define PAT_ROW    (7)          /* パターンの行数 */
#define PAT_COL    (11)         /* パターンの列数 */
#define PAT_SIZE   (PAT_ROW*PAT_COL)
#define ALL_POINTS (IMAGE_NUM*PAT_SIZE)
#define CHESS_SIZE (24.0)       /* パターン1マスの1辺サイズ[mm] */

#import <Foundation/Foundation.h>
#import "OpenCVUtil.h"

/**
 キャリブレーション用ユーティリティクラス
 */
@interface CameraCalibUtil : NSObject

//@property (copy, nonatomic) NSMutableArray *imageList; //UIImageを保存する

@property (strong, retain) NSMutableArray *imageList;


/**
 `UIImage`インスタンスをOpenCV画像データに変換するメソッド
 
 @param     image       `UIImage`インスタンス
 @return    `IplImage`インスタンス
 */

+ (cv::Mat)cvMatFromUIImage:(UIImage *)image;
+ (UIImage *)UIImageFromCVMat:(cv::Mat)cvMat;
+ (UIImage *)GreyScaleFilter:(UIImage *)image;
- (int)CameraCalibration;
+ (void)PrintCameraMatrix:(CvMat *)matrix;
- (int)SaveUIImageToArray:(UIImage *)image;
+ (UIImage *)FindAndDrawChessBoardCorner:(UIImage *)image;

@end