/*
 NFSClient.h

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

@interface LNFSClient : NSObject

- (instancetype)initWithHost:(NSString *)host port:(int)port;

@property (nonatomic) NSTimeInterval timeout;
@property (nonatomic) int32_t uid;
@property (nonatomic) int32_t gid;

#pragma mark - Connection

- (BOOL)isConnected;

- (NSString *_Nullable)exportName;

- (void)connectToExport:(NSString *)exportName
             completion:(void(^)(NSError *))completion;

- (void)disconnectFromExportGracefully:(BOOL)gracefully
                            completion:(void(^)(NSError * _Nullable error))completion;

- (void)listExportsWithCompletion:(void(^)(NSArray<NSString *> * _Nullable exports,
                                           NSError * _Nullable error))completion;

#pragma mark - Directory operations

- (void)contentsOfDirectoryAtPath:(NSString *)path
                        recursive:(BOOL)recursive
                       completion:(void(^)(NSArray<LNFSFileItem *> *, NSError *))completion;

- (void)createDirectoryAtPath:(NSString *)path
                   completion:(void(^)(NSError *))completion;

- (void)removeDirectoryAtPath:(NSString *)path
                    recursive:(BOOL)recursive
                   completion:(void(^)(NSError * _Nullable error))completion;

#pragma mark - File attributes

- (void)attributesOfItemAtPath:(NSString *)path
                    completion:(void(^)(LNFSFileItem * _Nullable item,
                                        NSError * _Nullable error))completion;

- (void)attributesOfFileSystemForPath:(NSString *)path
                           completion:(void(^)(NSDictionary<NSFileAttributeKey, id> * _Nullable attrs,
                                               NSError * _Nullable error))completion;

- (void)destinationOfSymbolicLinkAtPath:(NSString *)path
                             completion:(void(^)(NSString * _Nullable destination,
                                                 NSError * _Nullable error))completion;

#pragma mark - File operations

- (void)removeFileAtPath:(NSString *)path
              completion:(void(^)(NSError * _Nullable error))completion;

- (void)removeItemAtPath:(NSString *)path
              completion:(void(^)(NSError * _Nullable error))completion;

- (void)moveItemAtPath:(NSString *)from
                toPath:(NSString *)to
            completion:(void(^)(NSError * _Nullable error))completion;

- (void)truncateFileAtPath:(NSString *)path
                  toOffset:(uint64_t)offset
                completion:(void(^)(NSError * _Nullable error))completion;

#pragma mark - Read / Write

- (void)contentsAtPath:(NSString *)path
              progress:(BOOL(^ _Nullable)(int64_t bytes, int64_t total))progress
            completion:(void(^)(NSData * _Nullable data,
                                NSError * _Nullable error))completion;

- (void)contentsAtPath:(NSString *)path
                offset:(int64_t)offset
                length:(int64_t)length
              progress:(BOOL(^ _Nullable)(int64_t bytes, int64_t total))progress
            completion:(void(^)(NSData * _Nullable data,
                                NSError * _Nullable error))completion;

- (void)writeData:(NSData *)data
           toPath:(NSString *)path
         progress:(BOOL(^ _Nullable)(int64_t bytes))progress
       completion:(void(^)(NSError * _Nullable error))completion;

- (void)uploadItemAtURL:(NSURL *)url
                 toPath:(NSString *)path
               progress:(BOOL(^ _Nullable)(int64_t bytes))progress
             completion:(void(^)(NSError * _Nullable error))completion;

- (void)downloadItemAtPath:(NSString *)path
                     toURL:(NSURL *)url
                  progress:(BOOL(^ _Nullable)(int64_t bytes, int64_t total))progress
                completion:(void(^)(NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
