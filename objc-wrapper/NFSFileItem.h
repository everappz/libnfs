/*
 NFSFileItem.h

 Created by Artem Meleshko on 2026-03-16.

 MIT License

 Copyright (c) 2026 Artem Meleshko

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.

 While NFSClient source code shipped with project is MIT licensed,
 but libnfs which is LGPL v2.1.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LNFSFileItem : NSObject

@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *path;
@property (nonatomic, readonly) BOOL isDirectory;
@property (nonatomic, readonly) BOOL isRegularFile;
@property (nonatomic, readonly) BOOL isSymbolicLink;
@property (nonatomic, readonly) int64_t fileSize;
@property (nonatomic, readonly, copy) NSDate *modificationDate;
@property (nonatomic, readonly, copy) NSDate *accessDate;
@property (nonatomic, readonly, copy) NSDate *creationDate;
@property (nonatomic, readonly) uint64_t inode;
@property (nonatomic, readonly) uint32_t nlink;
@property (nonatomic, readonly) uint32_t mode;

@end

NS_ASSUME_NONNULL_END
