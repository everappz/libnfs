/*
 NFSContext.h

 Created by Artem Meleshko on 2026-03-22.

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
#import "NFSFileItem.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXTERN NSString *const LNFSErrorDomain;

@interface LNFSContext : NSObject

@property (nonatomic) NSTimeInterval timeout;
@property (nonatomic) int32_t uid;
@property (nonatomic) int32_t gid;

- (BOOL)isConnected;

// Connection
- (BOOL)connectToServer:(NSString *)server
                   port:(int)port
                 export:(NSString *)exportName
                  error:(NSError **)error;
- (BOOL)disconnectWithError:(NSError **)error;

// Stat
- (nullable LNFSFileItem *)statItemAtPath:(NSString *)path
                                    error:(NSError **)error;

// Statvfs
- (nullable NSDictionary<NSFileAttributeKey, id> *)statvfs64AtPath:(NSString *)path
                                                             error:(NSError **)error;

// Directory operations
- (BOOL)mkdirAtPath:(NSString *)path error:(NSError **)error;
- (BOOL)rmdirAtPath:(NSString *)path error:(NSError **)error;
- (nullable NSArray<LNFSFileItem *> *)contentsOfDirectoryAtPath:(NSString *)path
                                                          error:(NSError **)error;

// File operations
- (BOOL)unlinkAtPath:(NSString *)path error:(NSError **)error;
- (BOOL)renameFrom:(NSString *)oldPath to:(NSString *)newPath error:(NSError **)error;
- (BOOL)truncateAtPath:(NSString *)path offset:(uint64_t)offset error:(NSError **)error;
- (nullable NSString *)readlinkAtPath:(NSString *)path error:(NSError **)error;

// File I/O
- (nullable NSData *)readFileAtPath:(NSString *)path
                             offset:(int64_t)offset
                             length:(int64_t)length
                           progress:(BOOL(^ _Nullable)(int64_t bytes, int64_t total))progress
                              error:(NSError **)error;

- (BOOL)writeData:(NSData *)data
           toPath:(NSString *)path
         progress:(BOOL(^ _Nullable)(int64_t bytes))progress
            error:(NSError **)error;

// Streaming file I/O (avoids loading entire file into memory)
- (BOOL)readFileAtPath:(NSString *)path
             toFileURL:(NSURL *)localURL
              progress:(BOOL(^ _Nullable)(int64_t bytes, int64_t total))progress
                 error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
