#import <Foundation/Foundation.h>
#import "NFSClient.h"
#import "NFSFileItem.h"

// Define RUN_SERVER_TESTS to enable full server test suite.
// By default only a quick installation-verification test runs.
#ifdef RUN_SERVER_TESTS

// Test server configuration
static NSString *const kServerURL = @"nfs://192.168.18.149";
static NSString *const kExport = @"/volume1/test";

static int gPassed = 0;
static int gFailed = 0;

static CFAbsoluteTime gSuiteStart;
static CFAbsoluteTime gGroupStart;

static void PASS(NSString *name) {
    NSLog(@"  [PASS] %@", name);
    gPassed++;
}

static void FAIL(NSString *name, NSString *reason) {
    NSLog(@"  [FAIL] %@ - %@", name, reason);
    gFailed++;
}

static void GROUP(NSString *name) {
    gGroupStart = CFAbsoluteTimeGetCurrent();
    NSLog(@"--- %@ ---", name);
}

static void GROUP_END(void) {
    CFAbsoluteTime elapsed = CFAbsoluteTimeGetCurrent() - gGroupStart;
    NSLog(@"  (%.3f s)", elapsed);
}

#pragma mark - Helpers

static void waitForCompletion(void (^block)(dispatch_semaphore_t sem)) {
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    block(sem);
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));
}

static void waitForCompletionTimeout(int64_t seconds, void (^block)(dispatch_semaphore_t sem)) {
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    block(sem);
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, seconds * NSEC_PER_SEC));
}

#pragma mark - Tests

static void testClientInit(void) {
    GROUP(@"Client Initialization Tests");

    NSURL *url = [NSURL URLWithString:kServerURL];
    LNFSClient *client = [[LNFSClient alloc] initWithURL:url];

    if (client) {
        PASS(@"initWithURL");
    } else {
        FAIL(@"initWithURL", @"returned nil");
    }

    client.timeout = 30.0;
    if (client.timeout == 30.0) {
        PASS(@"set/get timeout");
    } else {
        FAIL(@"set/get timeout", [NSString stringWithFormat:@"expected 30.0, got %.1f", client.timeout]);
    }

    if (client.uid >= 0) {
        PASS(@"uid property");
    } else {
        FAIL(@"uid property", @"invalid uid");
    }

    if (client.gid >= 0) {
        PASS(@"gid property");
    } else {
        FAIL(@"gid property", @"invalid gid");
    }
    GROUP_END();
}

static void testFileItemInit(void) {
    GROUP(@"FileItem Initialization Tests");

    LNFSFileItem *item = [[LNFSFileItem alloc] init];
    if (item) {
        PASS(@"LNFSFileItem alloc/init");
    } else {
        FAIL(@"LNFSFileItem alloc/init", @"returned nil");
    }
    GROUP_END();
}

static void testListExports(LNFSClient *client) {
    GROUP(@"List Exports Tests");

    __block NSArray<NSString *> *foundExports = nil;
    __block NSError *foundError = nil;

    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client listExportsWithCompletion:^(NSArray<NSString *> *exports, NSError *error) {
            foundExports = exports;
            foundError = error;
            dispatch_semaphore_signal(sem);
        }];
    });

    if (foundError) {
        FAIL(@"listExports", foundError.localizedDescription);
    } else if (!foundExports || foundExports.count == 0) {
        FAIL(@"listExports", @"no exports found");
    } else {
        PASS(@"listExports");
        NSLog(@"    Found %lu exports:", (unsigned long)foundExports.count);
        for (NSString *exp in foundExports) {
            NSLog(@"      %@", exp);
        }
    }

    BOOL containsExport = NO;
    for (NSString *exp in foundExports) {
        if ([exp isEqualToString:kExport]) {
            containsExport = YES;
            break;
        }
    }
    if (containsExport) {
        PASS(@"listExports contains test export");
    } else {
        FAIL(@"listExports contains test export",
                  [NSString stringWithFormat:@"export %@ not found in list", kExport]);
    }
    GROUP_END();
}

static void testConnect(LNFSClient *client) {
    GROUP(@"Connection Tests");

    __block NSError *connectError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client connectToExport:kExport completion:^(NSError *error) {
            connectError = error;
            dispatch_semaphore_signal(sem);
        }];
    });

    if (connectError) {
        FAIL(@"connectToExport", connectError.localizedDescription);
    } else {
        PASS(@"connectToExport");
    }
    GROUP_END();
}

static void testDirectoryOperations(LNFSClient *client, NSString *testDir) {
    GROUP(@"Directory Operations Tests");

    // mkdir
    __block NSError *mkdirError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client createDirectoryAtPath:testDir completion:^(NSError *error) {
            mkdirError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (mkdirError) {
        FAIL(@"createDirectoryAtPath", mkdirError.localizedDescription);
    } else {
        PASS(@"createDirectoryAtPath");
    }

    // Stat the directory
    __block LNFSFileItem *dirItem = nil;
    __block NSError *statError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client attributesOfItemAtPath:testDir completion:^(LNFSFileItem *item, NSError *error) {
            dirItem = item;
            statError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (statError) {
        FAIL(@"stat directory", statError.localizedDescription);
    } else if (!dirItem.isDirectory) {
        FAIL(@"stat directory", @"not reported as directory");
    } else {
        PASS(@"stat directory");
    }

    // Create a subdirectory
    NSString *subDir = [testDir stringByAppendingPathComponent:@"subdir"];
    __block NSError *subMkdirError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client createDirectoryAtPath:subDir completion:^(NSError *error) {
            subMkdirError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (subMkdirError) {
        FAIL(@"createDirectoryAtPath (subdirectory)", subMkdirError.localizedDescription);
    } else {
        PASS(@"createDirectoryAtPath (subdirectory)");
    }

    // List directory contents
    __block NSArray<LNFSFileItem *> *items = nil;
    __block NSError *lsError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client contentsOfDirectoryAtPath:testDir recursive:NO completion:^(NSArray<LNFSFileItem *> *result, NSError *error) {
            items = result;
            lsError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (lsError) {
        FAIL(@"contentsOfDirectoryAtPath (non-recursive)", lsError.localizedDescription);
    } else if (!items) {
        FAIL(@"contentsOfDirectoryAtPath (non-recursive)", @"returned nil");
    } else {
        BOOL foundSubdir = NO;
        for (LNFSFileItem *item in items) {
            if ([item.name isEqualToString:@"subdir"]) {
                foundSubdir = YES;
                break;
            }
        }
        if (foundSubdir) {
            PASS(@"contentsOfDirectoryAtPath (non-recursive)");
        } else {
            FAIL(@"contentsOfDirectoryAtPath (non-recursive)", @"subdir not found in listing");
        }
    }

    // Remove subdirectory (non-recursive)
    __block NSError *rmdirError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client removeDirectoryAtPath:subDir recursive:NO completion:^(NSError *error) {
            rmdirError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (rmdirError) {
        FAIL(@"removeDirectoryAtPath (non-recursive)", rmdirError.localizedDescription);
    } else {
        PASS(@"removeDirectoryAtPath (non-recursive)");
    }

    // Verify subdirectory is gone
    __block NSError *statGoneError = nil;
    __block LNFSFileItem *goneItem = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client attributesOfItemAtPath:subDir completion:^(LNFSFileItem *item, NSError *error) {
            goneItem = item;
            statGoneError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (statGoneError) {
        PASS(@"verify directory removed (stat fails)");
    } else {
        FAIL(@"verify directory removed (stat fails)", @"stat succeeded on removed dir");
    }
    GROUP_END();
}

static void testFileWriteAndRead(LNFSClient *client, NSString *testDir) {
    GROUP(@"File Write/Read Tests");

    NSString *filePath = [testDir stringByAppendingPathComponent:@"testfile.txt"];
    NSString *testContent = @"Hello from libnfs ObjC wrapper test!";
    NSData *testData = [testContent dataUsingEncoding:NSUTF8StringEncoding];

    // Write file
    __block NSError *writeError = nil;
    __block int64_t writtenBytes = 0;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client writeData:testData toPath:filePath progress:^BOOL(int64_t bytes) {
            writtenBytes = bytes;
            return YES;
        } completion:^(NSError *error) {
            writeError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (writeError) {
        FAIL(@"writeData", writeError.localizedDescription);
    } else {
        PASS(@"writeData");
    }

    if (writtenBytes == (int64_t)testData.length) {
        PASS(@"writeData progress callback");
    } else {
        FAIL(@"writeData progress callback",
                  [NSString stringWithFormat:@"expected %lu bytes, got %lld",
                   (unsigned long)testData.length, writtenBytes]);
    }

    // Read file (full)
    __block NSData *readData = nil;
    __block NSError *readError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client contentsAtPath:filePath progress:^BOOL(int64_t bytes, int64_t total) {
            return YES;
        } completion:^(NSData *data, NSError *error) {
            readData = data;
            readError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (readError) {
        FAIL(@"contentsAtPath (full read)", readError.localizedDescription);
    } else if (!readData) {
        FAIL(@"contentsAtPath (full read)", @"returned nil data");
    } else if (![readData isEqualToData:testData]) {
        FAIL(@"contentsAtPath (full read)",
                  [NSString stringWithFormat:@"data mismatch: read %lu bytes, expected %lu",
                   (unsigned long)readData.length, (unsigned long)testData.length]);
    } else {
        PASS(@"contentsAtPath (full read)");
    }

    // Read file with offset/length
    __block NSData *partialData = nil;
    __block NSError *partialError = nil;
    int64_t readOffset = 6; // skip "Hello "
    int64_t readLength = 4; // read "from"
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client contentsAtPath:filePath offset:readOffset length:readLength progress:nil
                    completion:^(NSData *data, NSError *error) {
            partialData = data;
            partialError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (partialError) {
        FAIL(@"contentsAtPath (offset/length)", partialError.localizedDescription);
    } else if (!partialData) {
        FAIL(@"contentsAtPath (offset/length)", @"returned nil");
    } else {
        NSString *partialStr = [[NSString alloc] initWithData:partialData encoding:NSUTF8StringEncoding];
        if ([partialStr isEqualToString:@"from"]) {
            PASS(@"contentsAtPath (offset/length)");
        } else {
            FAIL(@"contentsAtPath (offset/length)",
                      [NSString stringWithFormat:@"expected 'from', got '%@'", partialStr]);
        }
    }
    GROUP_END();
}

static void testStatOperations(LNFSClient *client, NSString *testDir) {
    GROUP(@"Stat Operations Tests");

    NSString *filePath = [testDir stringByAppendingPathComponent:@"testfile.txt"];

    // attributesOfItemAtPath
    __block LNFSFileItem *fileItem = nil;
    __block NSError *statError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client attributesOfItemAtPath:filePath completion:^(LNFSFileItem *item, NSError *error) {
            fileItem = item;
            statError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (statError) {
        FAIL(@"attributesOfItemAtPath (file)", statError.localizedDescription);
    } else if (!fileItem) {
        FAIL(@"attributesOfItemAtPath (file)", @"returned nil");
    } else {
        PASS(@"attributesOfItemAtPath (file)");
    }

    // Verify file properties
    if (fileItem) {
        if (fileItem.isRegularFile) {
            PASS(@"fileItem.isRegularFile");
        } else {
            FAIL(@"fileItem.isRegularFile", @"not reported as regular file");
        }

        if (!fileItem.isDirectory) {
            PASS(@"fileItem.isDirectory == NO for file");
        } else {
            FAIL(@"fileItem.isDirectory == NO for file", @"reported as directory");
        }

        if (!fileItem.isSymbolicLink) {
            PASS(@"fileItem.isSymbolicLink == NO for file");
        } else {
            FAIL(@"fileItem.isSymbolicLink == NO for file", @"reported as symlink");
        }

        if (fileItem.fileSize > 0) {
            PASS(@"fileItem.fileSize > 0");
        } else {
            FAIL(@"fileItem.fileSize > 0",
                      [NSString stringWithFormat:@"size = %lld", fileItem.fileSize]);
        }

        if (fileItem.inode > 0) {
            PASS(@"fileItem.inode > 0");
        } else {
            FAIL(@"fileItem.inode > 0", @"inode is 0");
        }

        if (fileItem.nlink >= 1) {
            PASS(@"fileItem.nlink >= 1");
        } else {
            FAIL(@"fileItem.nlink >= 1",
                      [NSString stringWithFormat:@"nlink = %u", fileItem.nlink]);
        }

        if (fileItem.mode > 0) {
            PASS(@"fileItem.mode > 0");
        } else {
            FAIL(@"fileItem.mode > 0", @"mode is 0");
        }

        if (fileItem.modificationDate) {
            PASS(@"fileItem.modificationDate not nil");
        } else {
            FAIL(@"fileItem.modificationDate not nil", @"nil");
        }

        if (fileItem.accessDate) {
            PASS(@"fileItem.accessDate not nil");
        } else {
            FAIL(@"fileItem.accessDate not nil", @"nil");
        }

        if (fileItem.creationDate) {
            PASS(@"fileItem.creationDate not nil");
        } else {
            FAIL(@"fileItem.creationDate not nil", @"nil");
        }

        if ([fileItem.name isEqualToString:@"testfile.txt"]) {
            PASS(@"fileItem.name");
        } else {
            FAIL(@"fileItem.name",
                      [NSString stringWithFormat:@"expected 'testfile.txt', got '%@'", fileItem.name]);
        }
    }

    // Stat the root
    __block LNFSFileItem *rootItem = nil;
    __block NSError *rootStatError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client attributesOfItemAtPath:@"/" completion:^(LNFSFileItem *item, NSError *error) {
            rootItem = item;
            rootStatError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (rootStatError) {
        FAIL(@"attributesOfItemAtPath (root)", rootStatError.localizedDescription);
    } else if (!rootItem || !rootItem.isDirectory) {
        FAIL(@"attributesOfItemAtPath (root)", @"root should be a directory");
    } else {
        PASS(@"attributesOfItemAtPath (root)");
    }
    GROUP_END();
}

static void testStatvfs(LNFSClient *client) {
    GROUP(@"Statvfs Tests");

    __block NSDictionary *attrs = nil;
    __block NSError *error = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client attributesOfFileSystemForPath:@"/" completion:^(NSDictionary<NSFileAttributeKey,id> *result, NSError *err) {
            attrs = result;
            error = err;
            dispatch_semaphore_signal(sem);
        }];
    });

    if (error) {
        FAIL(@"attributesOfFileSystemForPath", error.localizedDescription);
    } else if (!attrs) {
        FAIL(@"attributesOfFileSystemForPath", @"returned nil");
    } else {
        PASS(@"attributesOfFileSystemForPath");
    }

    if (attrs[NSFileSystemSize]) {
        NSNumber *size = attrs[NSFileSystemSize];
        if ([size unsignedLongLongValue] > 0) {
            PASS(@"NSFileSystemSize > 0");
        } else {
            FAIL(@"NSFileSystemSize > 0", @"zero");
        }
    } else {
        FAIL(@"NSFileSystemSize > 0", @"missing key");
    }

    if (attrs[NSFileSystemFreeSize]) {
        PASS(@"NSFileSystemFreeSize present");
    } else {
        FAIL(@"NSFileSystemFreeSize present", @"missing key");
    }

    if (attrs[NSFileSystemNodes]) {
        PASS(@"NSFileSystemNodes present");
    } else {
        FAIL(@"NSFileSystemNodes present", @"missing key");
    }

    if (attrs[NSFileSystemFreeNodes]) {
        PASS(@"NSFileSystemFreeNodes present");
    } else {
        FAIL(@"NSFileSystemFreeNodes present", @"missing key");
    }
    GROUP_END();
}

static void testTruncate(LNFSClient *client, NSString *testDir) {
    GROUP(@"Truncate Tests");

    NSString *filePath = [testDir stringByAppendingPathComponent:@"trunctest.txt"];

    // Write a file first
    NSData *data = [@"Hello, World! This is a truncate test." dataUsingEncoding:NSUTF8StringEncoding];
    __block NSError *writeError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client writeData:data toPath:filePath progress:nil completion:^(NSError *error) {
            writeError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (writeError) {
        FAIL(@"truncate: write setup", writeError.localizedDescription);
        return;
    }

    // Truncate to 5 bytes
    __block NSError *truncError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client truncateFileAtPath:filePath toOffset:5 completion:^(NSError *error) {
            truncError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (truncError) {
        FAIL(@"truncateFileAtPath", truncError.localizedDescription);
    } else {
        PASS(@"truncateFileAtPath");
    }

    // Verify size
    __block LNFSFileItem *item = nil;
    __block NSError *statError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client attributesOfItemAtPath:filePath completion:^(LNFSFileItem *result, NSError *error) {
            item = result;
            statError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (statError) {
        FAIL(@"truncate verify size", statError.localizedDescription);
    } else if (item.fileSize != 5) {
        FAIL(@"truncate verify size",
                  [NSString stringWithFormat:@"expected 5, got %lld", item.fileSize]);
    } else {
        PASS(@"truncate verify size");
    }

    // Read truncated content
    __block NSData *readData = nil;
    __block NSError *readError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client contentsAtPath:filePath progress:nil completion:^(NSData *data, NSError *error) {
            readData = data;
            readError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (readError) {
        FAIL(@"truncate verify content", readError.localizedDescription);
    } else {
        NSString *content = [[NSString alloc] initWithData:readData encoding:NSUTF8StringEncoding];
        if ([content isEqualToString:@"Hello"]) {
            PASS(@"truncate verify content");
        } else {
            FAIL(@"truncate verify content",
                      [NSString stringWithFormat:@"expected 'Hello', got '%@'", content]);
        }
    }

    // Cleanup
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client removeFileAtPath:filePath completion:^(NSError *error) {
            dispatch_semaphore_signal(sem);
        }];
    });
    GROUP_END();
}

static void testRename(LNFSClient *client, NSString *testDir) {
    GROUP(@"Rename Tests");

    NSString *origPath = [testDir stringByAppendingPathComponent:@"rename_orig.txt"];
    NSString *newPath = [testDir stringByAppendingPathComponent:@"rename_new.txt"];
    NSString *testContent = @"rename test content";
    NSData *data = [testContent dataUsingEncoding:NSUTF8StringEncoding];

    // Create file
    __block NSError *writeError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client writeData:data toPath:origPath progress:nil completion:^(NSError *error) {
            writeError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (writeError) {
        FAIL(@"rename: write setup", writeError.localizedDescription);
        return;
    }

    // Rename
    __block NSError *renameError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client moveItemAtPath:origPath toPath:newPath completion:^(NSError *error) {
            renameError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (renameError) {
        FAIL(@"moveItemAtPath", renameError.localizedDescription);
    } else {
        PASS(@"moveItemAtPath");
    }

    // Verify old path is gone
    __block NSError *statOldError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client attributesOfItemAtPath:origPath completion:^(LNFSFileItem *item, NSError *error) {
            statOldError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (statOldError) {
        PASS(@"rename: old path gone");
    } else {
        FAIL(@"rename: old path gone", @"old path still exists");
    }

    // Verify new path exists and content matches
    __block NSData *readData = nil;
    __block NSError *readError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client contentsAtPath:newPath progress:nil completion:^(NSData *data, NSError *error) {
            readData = data;
            readError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (readError) {
        FAIL(@"rename: verify new path content", readError.localizedDescription);
    } else {
        NSString *content = [[NSString alloc] initWithData:readData encoding:NSUTF8StringEncoding];
        if ([content isEqualToString:testContent]) {
            PASS(@"rename: verify new path content");
        } else {
            FAIL(@"rename: verify new path content",
                      [NSString stringWithFormat:@"expected '%@', got '%@'", testContent, content]);
        }
    }

    // Cleanup
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client removeFileAtPath:newPath completion:^(NSError *error) {
            dispatch_semaphore_signal(sem);
        }];
    });
    GROUP_END();
}

static void testUnlink(LNFSClient *client, NSString *testDir) {
    GROUP(@"Unlink Tests");

    NSString *filePath = [testDir stringByAppendingPathComponent:@"unlink_test.txt"];
    NSData *data = [@"delete me" dataUsingEncoding:NSUTF8StringEncoding];

    // Create file
    __block NSError *writeError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client writeData:data toPath:filePath progress:nil completion:^(NSError *error) {
            writeError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (writeError) {
        FAIL(@"unlink: write setup", writeError.localizedDescription);
        return;
    }

    // Remove file
    __block NSError *removeError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client removeFileAtPath:filePath completion:^(NSError *error) {
            removeError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (removeError) {
        FAIL(@"removeFileAtPath", removeError.localizedDescription);
    } else {
        PASS(@"removeFileAtPath");
    }

    // Verify gone
    __block NSError *statError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client attributesOfItemAtPath:filePath completion:^(LNFSFileItem *item, NSError *error) {
            statError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (statError) {
        PASS(@"unlink: verify file gone");
    } else {
        FAIL(@"unlink: verify file gone", @"file still exists");
    }
    GROUP_END();
}

static void testRemoveItem(LNFSClient *client, NSString *testDir) {
    GROUP(@"RemoveItem Tests");

    // Test removeItemAtPath on a file
    NSString *filePath = [testDir stringByAppendingPathComponent:@"removeitem_file.txt"];
    NSData *data = [@"remove item test" dataUsingEncoding:NSUTF8StringEncoding];

    __block NSError *writeError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client writeData:data toPath:filePath progress:nil completion:^(NSError *error) {
            writeError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (writeError) {
        FAIL(@"removeItem: write setup", writeError.localizedDescription);
        return;
    }

    __block NSError *removeError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client removeItemAtPath:filePath completion:^(NSError *error) {
            removeError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (removeError) {
        FAIL(@"removeItemAtPath (file)", removeError.localizedDescription);
    } else {
        PASS(@"removeItemAtPath (file)");
    }

    // Test removeItemAtPath on a directory with contents
    NSString *dirPath = [testDir stringByAppendingPathComponent:@"removeitem_dir"];
    NSString *innerFile = [dirPath stringByAppendingPathComponent:@"inner.txt"];

    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client createDirectoryAtPath:dirPath completion:^(NSError *error) {
            dispatch_semaphore_signal(sem);
        }];
    });
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client writeData:data toPath:innerFile progress:nil completion:^(NSError *error) {
            dispatch_semaphore_signal(sem);
        }];
    });

    __block NSError *removeDirError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client removeItemAtPath:dirPath completion:^(NSError *error) {
            removeDirError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (removeDirError) {
        FAIL(@"removeItemAtPath (directory with contents)", removeDirError.localizedDescription);
    } else {
        PASS(@"removeItemAtPath (directory with contents)");
    }
    GROUP_END();
}

static void testRecursiveDirectory(LNFSClient *client, NSString *testDir) {
    GROUP(@"Recursive Directory Tests");

    NSString *recursiveDir = [testDir stringByAppendingPathComponent:@"recursive_test"];
    NSString *sub1 = [recursiveDir stringByAppendingPathComponent:@"sub1"];
    NSString *sub2 = [recursiveDir stringByAppendingPathComponent:@"sub2"];
    NSData *data = [@"recursive test" dataUsingEncoding:NSUTF8StringEncoding];

    // Create structure
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client createDirectoryAtPath:recursiveDir completion:^(NSError *error) {
            dispatch_semaphore_signal(sem);
        }];
    });
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client createDirectoryAtPath:sub1 completion:^(NSError *error) {
            dispatch_semaphore_signal(sem);
        }];
    });
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client createDirectoryAtPath:sub2 completion:^(NSError *error) {
            dispatch_semaphore_signal(sem);
        }];
    });
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client writeData:data toPath:[sub1 stringByAppendingPathComponent:@"file1.txt"]
                 progress:nil completion:^(NSError *error) {
            dispatch_semaphore_signal(sem);
        }];
    });
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client writeData:data toPath:[sub2 stringByAppendingPathComponent:@"file2.txt"]
                 progress:nil completion:^(NSError *error) {
            dispatch_semaphore_signal(sem);
        }];
    });

    // Test recursive listing
    __block NSArray<LNFSFileItem *> *allItems = nil;
    __block NSError *lsError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client contentsOfDirectoryAtPath:recursiveDir recursive:YES
                               completion:^(NSArray<LNFSFileItem *> *items, NSError *error) {
            allItems = items;
            lsError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (lsError) {
        FAIL(@"contentsOfDirectoryAtPath (recursive)", lsError.localizedDescription);
    } else if (!allItems) {
        FAIL(@"contentsOfDirectoryAtPath (recursive)", @"returned nil");
    } else {
        // Should have: sub1, sub2, file1.txt, file2.txt = 4 items
        if (allItems.count >= 4) {
            PASS(@"contentsOfDirectoryAtPath (recursive)");
        } else {
            FAIL(@"contentsOfDirectoryAtPath (recursive)",
                      [NSString stringWithFormat:@"expected >= 4 items, got %lu", (unsigned long)allItems.count]);
        }
    }

    // Test recursive directory removal
    __block NSError *rmError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client removeDirectoryAtPath:recursiveDir recursive:YES completion:^(NSError *error) {
            rmError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (rmError) {
        FAIL(@"removeDirectoryAtPath (recursive)", rmError.localizedDescription);
    } else {
        PASS(@"removeDirectoryAtPath (recursive)");
    }

    // Verify gone
    __block NSError *verifyError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client attributesOfItemAtPath:recursiveDir completion:^(LNFSFileItem *item, NSError *error) {
            verifyError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (verifyError) {
        PASS(@"recursive remove: verify gone");
    } else {
        FAIL(@"recursive remove: verify gone", @"directory still exists");
    }
    GROUP_END();
}

static void testLargeFileReadWrite(LNFSClient *client, NSString *testDir) {
    GROUP(@"Large File Read/Write Tests");

    NSString *filePath = [testDir stringByAppendingPathComponent:@"largefile.bin"];

    // Generate 1 MB of random data
    NSUInteger size = 1 * 1024 * 1024;
    NSMutableData *originalData = [NSMutableData dataWithLength:size];
    arc4random_buf([originalData mutableBytes], size);

    // Write
    __block NSError *writeError = nil;
    __block BOOL progressCalled = NO;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client writeData:originalData toPath:filePath progress:^BOOL(int64_t bytes) {
            progressCalled = YES;
            return YES;
        } completion:^(NSError *error) {
            writeError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (writeError) {
        FAIL(@"large file write (1 MB)", writeError.localizedDescription);
    } else {
        PASS(@"large file write (1 MB)");
    }
    if (progressCalled) {
        PASS(@"large file write progress called");
    } else {
        FAIL(@"large file write progress called", @"progress never called");
    }

    // Read back
    __block NSData *readData = nil;
    __block NSError *readError = nil;
    __block BOOL readProgressCalled = NO;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client contentsAtPath:filePath progress:^BOOL(int64_t bytes, int64_t total) {
            readProgressCalled = YES;
            return YES;
        } completion:^(NSData *data, NSError *error) {
            readData = data;
            readError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (readError) {
        FAIL(@"large file read (1 MB)", readError.localizedDescription);
    } else if (![readData isEqualToData:originalData]) {
        FAIL(@"large file read (1 MB)",
                  [NSString stringWithFormat:@"data mismatch: read %lu bytes, expected %lu",
                   (unsigned long)readData.length, (unsigned long)originalData.length]);
    } else {
        PASS(@"large file read (1 MB)");
    }
    if (readProgressCalled) {
        PASS(@"large file read progress called");
    } else {
        FAIL(@"large file read progress called", @"progress never called");
    }

    // Verify stat size
    __block LNFSFileItem *item = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client attributesOfItemAtPath:filePath completion:^(LNFSFileItem *result, NSError *error) {
            item = result;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (item && item.fileSize == (int64_t)size) {
        PASS(@"large file stat size matches");
    } else {
        FAIL(@"large file stat size matches",
                  [NSString stringWithFormat:@"expected %lu, got %lld",
                   (unsigned long)size, item ? item.fileSize : -1]);
    }

    // Cleanup
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client removeFileAtPath:filePath completion:^(NSError *error) {
            dispatch_semaphore_signal(sem);
        }];
    });
    GROUP_END();
}

static void testUploadDownload(LNFSClient *client, NSString *testDir) {
    GROUP(@"Upload/Download Tests");

    // Create a temp local file
    NSString *tempDir = NSTemporaryDirectory();
    NSString *localUploadPath = [tempDir stringByAppendingPathComponent:@"libnfs_upload_test.txt"];
    NSString *localDownloadPath = [tempDir stringByAppendingPathComponent:@"libnfs_download_test.txt"];
    NSString *remotePath = [testDir stringByAppendingPathComponent:@"uploaded_file.txt"];
    NSString *content = @"Upload/download test content with special chars: é à ü ñ 你好";
    NSData *data = [content dataUsingEncoding:NSUTF8StringEncoding];

    [data writeToFile:localUploadPath atomically:YES];

    // Upload
    __block NSError *uploadError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client uploadItemAtURL:[NSURL fileURLWithPath:localUploadPath]
                         toPath:remotePath
                       progress:nil
                     completion:^(NSError *error) {
            uploadError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (uploadError) {
        FAIL(@"uploadItemAtURL", uploadError.localizedDescription);
    } else {
        PASS(@"uploadItemAtURL");
    }

    // Download
    // Remove any previous download
    [[NSFileManager defaultManager] removeItemAtPath:localDownloadPath error:nil];

    __block NSError *downloadError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client downloadItemAtPath:remotePath
                             toURL:[NSURL fileURLWithPath:localDownloadPath]
                          progress:nil
                        completion:^(NSError *error) {
            downloadError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (downloadError) {
        FAIL(@"downloadItemAtPath", downloadError.localizedDescription);
    } else {
        PASS(@"downloadItemAtPath");
    }

    // Verify downloaded content
    NSData *downloadedData = [NSData dataWithContentsOfFile:localDownloadPath];
    if (downloadedData && [downloadedData isEqualToData:data]) {
        PASS(@"upload/download content matches");
    } else {
        FAIL(@"upload/download content matches", @"data mismatch");
    }

    // Cleanup
    [[NSFileManager defaultManager] removeItemAtPath:localUploadPath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:localDownloadPath error:nil];
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client removeFileAtPath:remotePath completion:^(NSError *error) {
            dispatch_semaphore_signal(sem);
        }];
    });
    GROUP_END();
}

static void testLargeUploadDownload(LNFSClient *client, NSString *testDir) {
    GROUP(@"Large Upload/Download Tests (50 MB)");

    NSString *tempDir = NSTemporaryDirectory();
    NSString *localUploadPath = [tempDir stringByAppendingPathComponent:@"libnfs_50mb_upload.bin"];
    NSString *localDownloadPath = [tempDir stringByAppendingPathComponent:@"libnfs_50mb_download.bin"];
    NSString *remotePath = [testDir stringByAppendingPathComponent:@"large_50mb.bin"];
    NSUInteger fileSize = 50 * 1024 * 1024;

    // Generate 50 MB of random data and write to local file
    NSMutableData *originalData = [NSMutableData dataWithLength:fileSize];
    arc4random_buf([originalData mutableBytes], fileSize);
    [originalData writeToFile:localUploadPath atomically:YES];

    // Upload
    __block NSError *uploadError = nil;
    __block int64_t uploadLastBytes = 0;
    waitForCompletionTimeout(300, ^(dispatch_semaphore_t sem) {
        [client uploadItemAtURL:[NSURL fileURLWithPath:localUploadPath]
                         toPath:remotePath
                       progress:^BOOL(int64_t bytes) {
            uploadLastBytes = bytes;
            return YES;
        } completion:^(NSError *error) {
            uploadError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (uploadError) {
        FAIL(@"upload 50 MB file", uploadError.localizedDescription);
    } else {
        PASS(@"upload 50 MB file");
    }
    if (uploadLastBytes == (int64_t)fileSize) {
        PASS(@"upload 50 MB progress reports all bytes");
    } else {
        FAIL(@"upload 50 MB progress reports all bytes",
             [NSString stringWithFormat:@"expected %lu, got %lld",
              (unsigned long)fileSize, uploadLastBytes]);
    }

    // Verify remote size
    __block LNFSFileItem *remoteItem = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client attributesOfItemAtPath:remotePath completion:^(LNFSFileItem *item, NSError *error) {
            remoteItem = item;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (remoteItem && remoteItem.fileSize == (int64_t)fileSize) {
        PASS(@"upload 50 MB remote size matches");
    } else {
        FAIL(@"upload 50 MB remote size matches",
             [NSString stringWithFormat:@"expected %lu, got %lld",
              (unsigned long)fileSize, remoteItem ? remoteItem.fileSize : -1]);
    }

    // Download
    [[NSFileManager defaultManager] removeItemAtPath:localDownloadPath error:nil];

    __block NSError *downloadError = nil;
    __block int64_t downloadLastBytes = 0;
    __block int64_t downloadTotal = 0;
    waitForCompletionTimeout(300, ^(dispatch_semaphore_t sem) {
        [client downloadItemAtPath:remotePath
                             toURL:[NSURL fileURLWithPath:localDownloadPath]
                          progress:^BOOL(int64_t bytes, int64_t total) {
            downloadLastBytes = bytes;
            downloadTotal = total;
            return YES;
        } completion:^(NSError *error) {
            downloadError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (downloadError) {
        FAIL(@"download 50 MB file", downloadError.localizedDescription);
    } else {
        PASS(@"download 50 MB file");
    }
    if (downloadLastBytes == (int64_t)fileSize) {
        PASS(@"download 50 MB progress reports all bytes");
    } else {
        FAIL(@"download 50 MB progress reports all bytes",
             [NSString stringWithFormat:@"expected %lu, got %lld",
              (unsigned long)fileSize, downloadLastBytes]);
    }

    // Verify downloaded content matches original
    NSData *downloadedData = [NSData dataWithContentsOfFile:localDownloadPath];
    if (downloadedData && downloadedData.length == fileSize && [downloadedData isEqualToData:originalData]) {
        PASS(@"50 MB upload/download data integrity");
    } else {
        FAIL(@"50 MB upload/download data integrity",
             [NSString stringWithFormat:@"download size=%lu, expected=%lu, match=%d",
              (unsigned long)(downloadedData ? downloadedData.length : 0),
              (unsigned long)fileSize,
              downloadedData ? [downloadedData isEqualToData:originalData] : -1]);
    }

    // Cleanup
    [[NSFileManager defaultManager] removeItemAtPath:localUploadPath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:localDownloadPath error:nil];
    waitForCompletionTimeout(60, ^(dispatch_semaphore_t sem) {
        [client removeFileAtPath:remotePath completion:^(NSError *error) {
            dispatch_semaphore_signal(sem);
        }];
    });
    GROUP_END();
}

static void testDisconnectAndReconnect(LNFSClient *client) {
    GROUP(@"Disconnect/Reconnect Tests");

    // Disconnect
    __block NSError *disconnectError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client disconnectFromExport:kExport gracefully:YES completion:^(NSError *error) {
            disconnectError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (disconnectError) {
        FAIL(@"disconnectFromExport", disconnectError.localizedDescription);
    } else {
        PASS(@"disconnectFromExport");
    }

    // Operations should fail when disconnected
    __block NSError *failError = nil;
    __block NSArray *failItems = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client contentsOfDirectoryAtPath:@"/" recursive:NO completion:^(NSArray<LNFSFileItem *> *items, NSError *error) {
            failError = error;
            failItems = items;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (failError) {
        PASS(@"operations fail when disconnected");
    } else {
        FAIL(@"operations fail when disconnected", @"operation succeeded when should have failed");
    }

    // Reconnect
    __block NSError *reconnectError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client connectToExport:kExport completion:^(NSError *error) {
            reconnectError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (reconnectError) {
        FAIL(@"reconnect after disconnect", reconnectError.localizedDescription);
    } else {
        PASS(@"reconnect after disconnect");
    }

    // Verify operations work again
    __block NSError *verifyError = nil;
    __block LNFSFileItem *verifyItem = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client attributesOfItemAtPath:@"/" completion:^(LNFSFileItem *item, NSError *error) {
            verifyItem = item;
            verifyError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (verifyError) {
        FAIL(@"operations work after reconnect", verifyError.localizedDescription);
    } else if (verifyItem && verifyItem.isDirectory) {
        PASS(@"operations work after reconnect");
    } else {
        FAIL(@"operations work after reconnect", @"unexpected result");
    }
    GROUP_END();
}

static void testErrorCases(LNFSClient *client) {
    GROUP(@"Error Handling Tests");

    // Stat non-existent path
    __block NSError *statError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client attributesOfItemAtPath:@"/nonexistent_path_12345" completion:^(LNFSFileItem *item, NSError *error) {
            statError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (statError) {
        PASS(@"stat non-existent path returns error");
    } else {
        FAIL(@"stat non-existent path returns error", @"no error returned");
    }

    // Read non-existent file
    __block NSError *readError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client contentsAtPath:@"/nonexistent_file_12345.txt" progress:nil
                    completion:^(NSData *data, NSError *error) {
            readError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (readError) {
        PASS(@"read non-existent file returns error");
    } else {
        FAIL(@"read non-existent file returns error", @"no error returned");
    }

    // Remove non-existent file
    __block NSError *removeError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client removeFileAtPath:@"/nonexistent_file_12345.txt" completion:^(NSError *error) {
            removeError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (removeError) {
        PASS(@"remove non-existent file returns error");
    } else {
        FAIL(@"remove non-existent file returns error", @"no error returned");
    }

    // Rmdir non-existent directory
    __block NSError *rmdirError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client removeDirectoryAtPath:@"/nonexistent_dir_12345" recursive:NO completion:^(NSError *error) {
            rmdirError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (rmdirError) {
        PASS(@"rmdir non-existent dir returns error");
    } else {
        FAIL(@"rmdir non-existent dir returns error", @"no error returned");
    }

    // List non-existent directory
    __block NSError *lsError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client contentsOfDirectoryAtPath:@"/nonexistent_dir_12345" recursive:NO
                               completion:^(NSArray<LNFSFileItem *> *items, NSError *error) {
            lsError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (lsError) {
        PASS(@"list non-existent dir returns error");
    } else {
        FAIL(@"list non-existent dir returns error", @"no error returned");
    }

    // Readlink non-existent path
    __block NSError *readlinkError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client destinationOfSymbolicLinkAtPath:@"/nonexistent_link_12345"
                                     completion:^(NSString *dest, NSError *error) {
            readlinkError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (readlinkError) {
        PASS(@"readlink non-existent path returns error");
    } else {
        FAIL(@"readlink non-existent path returns error", @"no error returned");
    }

    // Truncate non-existent file
    __block NSError *truncError = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client truncateFileAtPath:@"/nonexistent_file_12345.txt" toOffset:0
                        completion:^(NSError *error) {
            truncError = error;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (truncError) {
        PASS(@"truncate non-existent file returns error");
    } else {
        FAIL(@"truncate non-existent file returns error", @"no error returned");
    }
    GROUP_END();
}

static void testDisconnect(LNFSClient *client) {
    GROUP(@"Final Disconnect");

    __block NSError *error = nil;
    waitForCompletion(^(dispatch_semaphore_t sem) {
        [client disconnectFromExport:kExport gracefully:YES completion:^(NSError *err) {
            error = err;
            dispatch_semaphore_signal(sem);
        }];
    });
    if (error) {
        FAIL(@"final disconnect", error.localizedDescription);
    } else {
        PASS(@"final disconnect");
    }
    GROUP_END();
}

#endif // RUN_SERVER_TESTS

#pragma mark - Main

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSLog(@"libnfs pod installation test");

        NSURL *url = [NSURL URLWithString:@"nfs://localhost"];
        LNFSClient *client = [[LNFSClient alloc] initWithURL:url];
        if (!client) {
            NSLog(@"[FAIL] LNFSClient creation failed");
            return 1;
        }
        NSLog(@"[PASS] LNFSClient created successfully");

        if (![LNFSFileItem class]) {
            NSLog(@"[FAIL] LNFSFileItem class not available");
            return 1;
        }
        NSLog(@"[PASS] LNFSFileItem class available");

        client.timeout = 10.0;
        if (client.timeout != 10.0) {
            NSLog(@"[FAIL] Client timeout property failed");
            return 1;
        }
        NSLog(@"[PASS] Client timeout property works");

        NSLog(@"All installation tests passed");

#ifdef RUN_SERVER_TESTS
        gSuiteStart = CFAbsoluteTimeGetCurrent();
        NSLog(@"=== libnfs ObjC Wrapper Test Suite ===");
        NSLog(@"Server: %@", kServerURL);
        NSLog(@"Export: %@", kExport);
        NSLog(@"");

        NSString *testDir = [NSString stringWithFormat:@"/objctest_%u", arc4random_uniform(100000)];

        testClientInit();
        testFileItemInit();

        NSURL *serverURL = [NSURL URLWithString:kServerURL];
        LNFSClient *serverClient = [[LNFSClient alloc] initWithURL:serverURL];
        serverClient.timeout = 30.0;
        serverClient.uid = 0;
        serverClient.gid = 0;

        testListExports(serverClient);
        testConnect(serverClient);
        testDirectoryOperations(serverClient, testDir);
        testFileWriteAndRead(serverClient, testDir);
        testStatOperations(serverClient, testDir);
        testStatvfs(serverClient);
        testTruncate(serverClient, testDir);
        testRename(serverClient, testDir);
        testUnlink(serverClient, testDir);
        testRemoveItem(serverClient, testDir);
        testRecursiveDirectory(serverClient, testDir);
        testLargeFileReadWrite(serverClient, testDir);
        testUploadDownload(serverClient, testDir);
        testLargeUploadDownload(serverClient, testDir);
        testDisconnectAndReconnect(serverClient);
        testErrorCases(serverClient);

        GROUP(@"Cleanup");
        __block NSError *cleanupError = nil;
        waitForCompletion(^(dispatch_semaphore_t sem) {
            [serverClient removeItemAtPath:testDir completion:^(NSError *error) {
                cleanupError = error;
                dispatch_semaphore_signal(sem);
            }];
        });
        if (cleanupError) {
            waitForCompletion(^(dispatch_semaphore_t sem) {
                [serverClient removeFileAtPath:[testDir stringByAppendingPathComponent:@"testfile.txt"]
                              completion:^(NSError *error) {
                    dispatch_semaphore_signal(sem);
                }];
            });
            waitForCompletion(^(dispatch_semaphore_t sem) {
                [serverClient removeDirectoryAtPath:testDir recursive:YES completion:^(NSError *error) {
                    dispatch_semaphore_signal(sem);
                }];
            });
        }
        NSLog(@"  Cleanup done (dir: %@)", testDir);
        GROUP_END();

        testDisconnect(serverClient);

        CFAbsoluteTime totalElapsed = CFAbsoluteTimeGetCurrent() - gSuiteStart;
        NSLog(@"");
        NSLog(@"=== Test Results ===");
        NSLog(@"  Passed: %d", gPassed);
        NSLog(@"  Failed: %d", gFailed);
        NSLog(@"  Total:  %d", gPassed + gFailed);
        NSLog(@"  Time:   %.3f s", totalElapsed);
        NSLog(@"===================");

        if (gFailed > 0) {
            NSLog(@"SOME TESTS FAILED!");
            return 1;
        }
        NSLog(@"ALL SERVER TESTS PASSED!");
#endif // RUN_SERVER_TESTS
    }
    return 0;
}
