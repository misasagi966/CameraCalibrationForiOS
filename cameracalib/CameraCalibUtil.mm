//
//  CameraCalibUtil.m
//  cameracalib
//
//  Created by Ryota Nakai on 2015/11/11.
//  Copyright © 2015年 Ryota Nakai. All rights reserved.
//

#import "CameraCalibUtil.h"


@implementation CameraCalibUtil

@synthesize imageList;


+ (cv::Mat)cvMatFromUIImage:(UIImage *)image
{
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(image.CGImage);
    CGFloat cols = image.size.width;
    CGFloat rows = image.size.height;
    
    cv::Mat cvMat(rows, cols, CV_8UC4); // 8 bits per component, 4 channels
    
    CGContextRef contextRef = CGBitmapContextCreate(cvMat.data,                 // Pointer to  data
                                                    cols,                       // Width of bitmap
                                                    rows,                       // Height of bitmap
                                                    8,                          // Bits per component
                                                    cvMat.step[0],              // Bytes per row
                                                    colorSpace,                 // Colorspace
                                                    kCGImageAlphaNoneSkipLast |
                                                    kCGBitmapByteOrderDefault); // Bitmap info flags
    
    CGContextDrawImage(contextRef, CGRectMake(0, 0, cols, rows), image.CGImage);
    CGContextRelease(contextRef);
    CGColorSpaceRelease(colorSpace);
    
    return cvMat;
}

+ (UIImage *)UIImageFromCVMat:(cv::Mat)cvMat
{
    NSData *data = [NSData dataWithBytes:cvMat.data length:cvMat.elemSize()*cvMat.total()];
    CGColorSpaceRef colorSpace;
    
    if (cvMat.elemSize() == 1) {
        colorSpace = CGColorSpaceCreateDeviceGray();
    } else {
        colorSpace = CGColorSpaceCreateDeviceRGB();
    }
    
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    
    // Creating CGImage from cv::Mat
    CGImageRef imageRef = CGImageCreate(cvMat.cols,                                 //width
                                        cvMat.rows,                                 //height
                                        8,                                          //bits per component
                                        8 * cvMat.elemSize(),                       //bits per pixel
                                        cvMat.step[0],                              //bytesPerRow
                                        colorSpace,                                 //colorspace
                                        kCGImageAlphaNone|kCGBitmapByteOrderDefault,// bitmap info
                                        provider,                                   //CGDataProviderRef
                                        NULL,                                       //decode
                                        false,                                      //should interpolate
                                        kCGRenderingIntentDefault                   //intent
                                        );
    
    
    // Getting UIImage from CGImage
    UIImage *finalImage = [UIImage imageWithCGImage:imageRef];
    CGImageRelease(imageRef);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    
    return finalImage;
}
+ (UIImage *)GreyScaleFilter:(UIImage *)image
{
    
    cv::Mat srcMat = [self cvMatFromUIImage:image];
    cv::Mat greyMat;
    cv::cvtColor(srcMat, greyMat, CV_BGR2GRAY);
    return [self UIImageFromCVMat:greyMat];

}

- (int)SaveUIImageToArray:(UIImage *)image
{
    [self.imageList addObject:image];
    return 0;
}

- (int)CameraCalibration
{
    int i, j, k;
    int corner_count, found;
    int p_count[IMAGE_NUM];
    IplImage *src_img[IMAGE_NUM];
    CvSize pattern_size = cvSize (PAT_COL, PAT_ROW);
    CvPoint3D32f objects[ALL_POINTS];
    CvPoint2D32f *corners = (CvPoint2D32f *) cvAlloc (sizeof (CvPoint2D32f) * ALL_POINTS);
    CvMat object_points;
    CvMat image_points;
    CvMat point_counts;
    CvMat *intrinsic = cvCreateMat (3, 3, CV_32FC1);
    CvMat *rotation = cvCreateMat (1, 3, CV_32FC1);
    CvMat *translation = cvCreateMat (1, 3, CV_32FC1);
    CvMat *distortion = cvCreateMat (1, 4, CV_32FC1);
    
    // (1)キャリブレーション画像の読み込み
    for (i = 0; i < IMAGE_NUM; i++) {
        src_img[i] = [OpenCVUtil IplImageFromUIImage:[self.imageList objectAtIndex:i]];
    }
    
    // (2)3次元空間座標の設定
    for (i = 0; i < IMAGE_NUM; i++) {
        for (j = 0; j < PAT_ROW; j++) {
            for (k = 0; k < PAT_COL; k++) {
                objects[i * PAT_SIZE + j * PAT_COL + k].x = j * CHESS_SIZE;
                objects[i * PAT_SIZE + j * PAT_COL + k].y = k * CHESS_SIZE;
                objects[i * PAT_SIZE + j * PAT_COL + k].z = 0.0;
            }
        }
    }
    cvInitMatHeader (&object_points, ALL_POINTS, 3, CV_32FC1, objects);
    
    
    // (3)チェスボード（キャリブレーションパターン）のコーナー検出
    int found_num = 0;
    for (i = 0; i < IMAGE_NUM; i++) {
        found = cvFindChessboardCorners (src_img[i], pattern_size, &corners[i * PAT_SIZE], &corner_count);
        fprintf (stderr, "%02d...", i);
        if (found) {
            fprintf (stderr, "ok\n");
            found_num++;
        }
        else {
            fprintf (stderr, "fail\n");
        }
        // (4)コーナー位置をサブピクセル精度に修正，描画
        IplImage *src_gray = cvCreateImage (cvGetSize (src_img[i]), IPL_DEPTH_8U, 1);
        cvFindCornerSubPix (src_gray, &corners[i * PAT_SIZE], corner_count,
                            cvSize (3, 3), cvSize (-1, -1), cvTermCriteria (CV_TERMCRIT_ITER | CV_TERMCRIT_EPS, 20, 0.03));
        p_count[i] = corner_count;
    }
    
    if (found_num != IMAGE_NUM)
        return -1;
    cvInitMatHeader (&image_points, ALL_POINTS, 1, CV_32FC2, corners);
    cvInitMatHeader (&point_counts, IMAGE_NUM, 1, CV_32SC1, p_count);
    
    // (5)内部パラメータ，歪み係数の推定
    cvCalibrateCamera2 (&object_points, &image_points, &point_counts, cvSize (src_img[0]->width, src_img[0]->height), intrinsic, distortion);
    
    // (6)外部パラメータの推定
    CvMat sub_image_points, sub_object_points;
    int base = 0;
    cvGetRows (&image_points, &sub_image_points, base * PAT_SIZE, (base + 1) * PAT_SIZE);
    cvGetRows (&object_points, &sub_object_points, base * PAT_SIZE, (base + 1) * PAT_SIZE);
    cvFindExtrinsicCameraParams2 (&sub_object_points, &sub_image_points, intrinsic, distortion, rotation, translation);
    
    // (7)XMLファイルへの書き出し
    std::cout<<src_img[0]->width<<", "<<src_img[0]->height<<std::endl<<std::endl;
    [CameraCalibUtil PrintCameraMatrix: intrinsic];
    [CameraCalibUtil PrintCameraMatrix: rotation];
    [CameraCalibUtil PrintCameraMatrix: translation];
    [CameraCalibUtil PrintCameraMatrix: distortion];

    for (i = 0; i < IMAGE_NUM; i++) {
        cvReleaseImage (&src_img[i]);
    }

    return 0;
}


+ (void)PrintCameraMatrix:(CvMat *)matrix
{
    
    for(int y = 0; y < matrix->rows; ++y){
        for(int x = 0; x < matrix->cols; ++x){
            std::cout << matrix->data.fl[y*matrix->rows+x]<< ", ";
        }
        std::cout << "\r\r " << std::endl;
    }
    std::cout << std::endl;
}
+ (UIImage *)FindAndDrawChessBoardCorner:(UIImage *)image
{
    
    int corner_count=0, found=0, checkflag;
    IplImage *srcImage = [OpenCVUtil IplImageFromUIImage:image];
    CvSize pattern_size = cvSize (PAT_COL, PAT_ROW);
    CvPoint2D32f *corners = (CvPoint2D32f *) cvAlloc (sizeof (CvPoint2D32f) * ALL_POINTS);
    IplImage *src_gray = cvCreateImage (cvGetSize (srcImage), IPL_DEPTH_8U, 1);
    cvCvtColor (srcImage, src_gray, CV_BGR2GRAY);
    checkflag = cvCheckChessboard (src_gray, pattern_size);
    if(checkflag)
        found = cvFindChessboardCorners (srcImage, pattern_size, &corners[PAT_SIZE], &corner_count);
        if (found) {
            cvDrawChessboardCorners (srcImage, pattern_size, &corners[PAT_SIZE], corner_count, found);
            
            IplImage *dstImage = cvCreateImage(cvGetSize(srcImage), IPL_DEPTH_8U, 3);
            // CGImage用にBGRに変換
            cvCvtColor(src_gray, dstImage, CV_GRAY2BGR);
            UIImage *effectedImage =[OpenCVUtil UIImageFromIplImage:srcImage];
            cvFree(&corners);
            cvReleaseImage(&srcImage);
            cvReleaseImage(&src_gray);
            cvReleaseImage(&dstImage);
            return effectedImage;
        }
        else {
            cvFree(&corners);
            cvReleaseImage(&srcImage);
            cvReleaseImage(&src_gray);
            return NULL;
        }
}

@end