/*
 NFSFileItem.m

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

#import "NFSFileItem.h"
#include <sys/stat.h>

@interface LNFSFileItem ()

@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, copy) NSString *path;
@property (nonatomic, readwrite) BOOL isDirectory;
@property (nonatomic, readwrite) BOOL isRegularFile;
@property (nonatomic, readwrite) BOOL isSymbolicLink;
@property (nonatomic, readwrite) int64_t fileSize;
@property (nonatomic, readwrite, copy) NSDate *modificationDate;
@property (nonatomic, readwrite, copy) NSDate *accessDate;
@property (nonatomic, readwrite, copy) NSDate *creationDate;
@property (nonatomic, readwrite) uint64_t inode;
@property (nonatomic, readwrite) uint32_t nlink;
@property (nonatomic, readwrite) uint32_t mode;

@end

@implementation LNFSFileItem

+ (instancetype)itemWithName:(NSString *)name
                        path:(NSString *)path
                        mode:(uint64_t)nfsMode
                        size:(uint64_t)size
                       inode:(uint64_t)inode
                       nlink:(uint64_t)nlink
                       atime:(uint64_t)atime
                   atimeNsec:(uint64_t)atimeNsec
                       mtime:(uint64_t)mtime
                   mtimeNsec:(uint64_t)mtimeNsec
                       ctime:(uint64_t)ctime
                   ctimeNsec:(uint64_t)ctimeNsec
{
    LNFSFileItem *item = [[LNFSFileItem alloc] init];
    item.name = name;
    item.path = path;
    item.mode = (uint32_t)nfsMode;
    item.fileSize = (int64_t)size;
    item.inode = inode;
    item.nlink = (uint32_t)nlink;

    // Fix bug #1 from Swift NFSKit: properly mask with S_IFMT before comparing
    uint64_t fileType = nfsMode & S_IFMT;
    item.isDirectory = (fileType == S_IFDIR);
    item.isRegularFile = (fileType == S_IFREG);
    item.isSymbolicLink = (fileType == S_IFLNK);

    item.accessDate = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)atime + (NSTimeInterval)atimeNsec / 1e9];
    item.modificationDate = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)mtime + (NSTimeInterval)mtimeNsec / 1e9];
    item.creationDate = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)ctime + (NSTimeInterval)ctimeNsec / 1e9];

    return item;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %@ (%@)>", NSStringFromClass([self class]), self.name,
            self.isDirectory ? @"dir" : (self.isSymbolicLink ? @"symlink" : @"file")];
}

@end
