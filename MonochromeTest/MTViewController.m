//
//  MTViewController.m
//  MonochromeTest
//
//  Created by sakira on 2013/10/02.
//  Copyright (c) 2013年 sakira. All rights reserved.
//

#import "MTViewController.h"
#import "arm_neon.h"

static const unsigned int LoopCount = 100;
static const float r_lum_f = 0.299f;
static const float g_lum_f = 0.587f;
static const float b_lum_f = 0.114f;
static const unsigned int r_lum_i = 76;
static const unsigned int g_lum_i = 150;
static const unsigned int b_lum_i = 30;

@interface MTViewController ()

@end

@implementation MTViewController {
  __weak IBOutlet UIImageView *sourceImageView;
  __weak IBOutlet UIImageView *targetImageView;
  __weak IBOutlet UITextView *logView;
  
  NSData *sourceData;
  NSMutableData *targetData;
  int bitmapWidth, bitmapHeight;
  NSDate *startDate;
}

- (void)viewDidLoad {
  [super viewDidLoad];

  UIImage *img = [UIImage imageNamed:@"data.jpg"];
  sourceImageView.image = img;
  
  sourceData = [self dataOfImage:img];
  targetData = [NSMutableData dataWithLength:sourceData.length];
}

- (NSData*)dataOfImage:(UIImage*)img {
  CGImageRef cgimg = img.CGImage;
  int w = (int)CGImageGetWidth(cgimg);
  int h = (int)CGImageGetHeight(cgimg);
  bitmapWidth = w;
  bitmapHeight = h;
  
  NSMutableData *cdat = [NSMutableData dataWithLength:w * h * 4];
  CGContextRef cont;
  CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
  
  cont = CGBitmapContextCreate(cdat.mutableBytes,
                               w, h, 8, w * 4,
                               colorspace,
                               kCGImageAlphaNoneSkipFirst |
                               kCGBitmapByteOrder32Host);
  CGContextDrawImage(cont, CGRectMake(0, 0, w, h), cgimg);
  CGContextRelease(cont);
  CGColorSpaceRelease(colorspace);
  
  return cdat;
}

- (UIImage*)imageOfData:(NSData*)data {
  CGDataProviderRef providerref =
  CGDataProviderCreateWithData(NULL,
                               data.bytes, bitmapWidth * 4 * bitmapHeight, NULL);
  CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
  CGImageRef imgref =
  CGImageCreate(bitmapWidth, bitmapHeight, 8, 32, bitmapWidth * 4,
                colorspace,
                kCGImageAlphaFirst | kCGBitmapByteOrder32Host,
                providerref, NULL, NO, kCGRenderingIntentDefault);
  CGDataProviderRelease(providerref);
  
  UIImage *img = [UIImage imageWithCGImage:imgref];
  CGImageRelease(imgref);
  CGColorSpaceRelease(colorspace);
  
  return img;
}

- (void)startTimer:(NSString*)msg {
  startDate = [NSDate date];
}

- (void)stopTimer:(NSString*)msg {
  NSTimeInterval interval = - [startDate timeIntervalSinceNow];
  NSString *line = [NSString stringWithFormat:@"%d %@\n", (int)(interval * 1000), msg];
  line = [line stringByAppendingString:logView.text];
  logView.text = line;
}

- (void)mono_uchar {
  unsigned char const *inp = (unsigned char*)sourceData.bytes;
  unsigned char *outp = (unsigned char*)targetData.mutableBytes;
  int length4 = bitmapHeight * bitmapWidth * 4;
  int m;
  int r, g, b;
  for (int j = 0; j < LoopCount; j ++)
    for (int i = 0; i < length4; i += 4) {
      r = inp[i + 0];
      g = inp[i + 1];
      b = inp[i + 2];
      m = (r * r_lum_i + g * g_lum_i + b * b_lum_i) >> 8;
      outp[i + 3] = 0xff;
      outp[i + 0] = outp[i + 1] = outp[i + 2] = m ;
    }
}

- (void)mono_int32 {
  uint32_t const *inp = (uint32_t*)sourceData.bytes;
  uint32_t *outp = (uint32_t*)targetData.mutableBytes;
  int length = bitmapHeight * bitmapWidth;
  uint32_t s;
  uint m;
  for (int j = 0; j < LoopCount; j ++)
    for (int i = 0; i < length; i ++) {
      s = inp[i];
      m = (((s >> 16) & 0xff) * b_lum_i +
           ((s >>  8) & 0xff) * g_lum_i +
           ((s >>  0) & 0xff) * r_lum_i) >> 8;
      outp[i] = 0xff000000 | m | (m << 8) | (m << 16);
    }
}

- (void)mono_int64 {
  uint64_t *inp = (uint64_t*)sourceData.bytes;
  uint64_t *outp = (uint64_t*)targetData.mutableBytes;
  const int length_2 = bitmapWidth * bitmapHeight >> 1;
  uint64_t s, m;
  for (uint j = 0; j < LoopCount; j ++) {
    for (uint i = 0; i < length_2; i ++) {
      s = inp[i];
      m = ((((s >> 16) & 0xff000000ff) * b_lum_i) +
           (((s >>  8) & 0xff000000ff) * g_lum_i) +
           (((s >>  0) & 0xff000000ff) * r_lum_i)) & 0xff000000ff00;
      outp[i] = 0xff000000ff000000 | (m << 8) | m | (m >> 8);
    }
  }
}

- (void)mono_int16x8 {
  const uint8_t *inp = (uint8_t*)sourceData.bytes;
  uint64_t *outp = (uint64_t*)targetData.mutableBytes;
  const uint length_2 = bitmapWidth * bitmapHeight >> 1;
  const uint16x8_t lum_i =
    vmovl_u8(vcreate_u8((0x0001000000010000 * b_lum_i) |
                        (0x0000010000000100 * g_lum_i) |
                        (0x0000000100000001 * r_lum_i)));
  
  uint16x8_t sv, mv;
  uint64_t m;
  for (uint j = 0; j < LoopCount; j ++)
    for (uint i = 0; i < length_2; i ++) {
      sv = vmovl_u8(vld1_u8(inp + i * 8));
      mv = vmulq_u16(sv, lum_i);
      mv = vshrq_n_u16(mv, 8);
      m = (uint64_t)vmovn_u16(mv);
      m = ((m >> 16) + (m >> 8) + m) & 0xff000000ff;
      outp[i] = 0xff000000ff000000 | (m * 0x010101);
    }
}

- (void)mono_float {
  uint32_t const *inp = (uint32_t*)sourceData.bytes;
  uint32_t *outp = (uint32_t*)targetData.mutableBytes;
  const unsigned int length = bitmapHeight * bitmapWidth;
  uint32_t s;
  float r, g, b;
  uint m;
  for (int j = 0; j < LoopCount; j ++)
    for (int i = 0; i < length; i ++) {
      s = inp[i];
      r = (float)(s & 0x0000ff);
      g = (float)(s & 0x00ff00);
      b = (float)(s & 0xff0000);
      m = (uint)(r * (r_lum_f / 0x0000ff * 255) +
                 g * (g_lum_f / 0x00ff00 * 255) +
                 b * (b_lum_f / 0xff0000 * 255));
      outp[i] = 0xff000000L | (m << 16) | (m << 8) | m;
    }
}

- (IBAction)ucharButtonPressed:(id)sender {
  [self startTimer:@"uchar"];
  [self mono_uchar];
  [self stopTimer:@"uchar"];
  targetImageView.image = [self imageOfData:targetData];
}

- (IBAction)int32ButtonPressed:(id)sender {
  [self startTimer:@"int32"];
  [self mono_int32];
  [self stopTimer:@"int32"];
  targetImageView.image = [self imageOfData:targetData];
}

- (IBAction)int64ButtonPressed:(id)sender {
  [self startTimer:@"int64"];
  [self mono_int64];
  [self stopTimer:@"int64"];
  targetImageView.image = [self imageOfData:targetData];
}

- (IBAction)int16x8ButtonPressed:(id)sender {
  [self startTimer:@"int16x8"];
  [self mono_int16x8];
  [self stopTimer:@"int16x8"];
  targetImageView.image = [self imageOfData:targetData];
}

- (IBAction)floatButtonPressed:(id)sender {
  [self startTimer:@"float"];
  [self mono_float];
  [self stopTimer:@"float"];
  targetImageView.image = [self imageOfData:targetData];
}

@end
