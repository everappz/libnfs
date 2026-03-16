/*
   Copyright (C) 2025 libnfs contributors

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU Lesser General Public License as published by
   the Free Software Foundation; either version 2.1 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public License
   along with this program; if not, see <http://www.gnu.org/licenses/>.
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
