//
//  HIBitcoinManager.m
//  BitcoinKit
//
//  Created by Bazyli Zygan on 26.07.2013.
//  Extended by Jonas Schnelli 2013
//
//  Copyright (c) 2013 Hive Developers. All rights reserved.
//

#import "HIBitcoinManager.h"
#import <JavaVM/jni.h>

@interface HIBitcoinManager ()
{
    JavaVM *_vm;
    JNIEnv *_jniEnv;
    JavaVMInitArgs _vmArgs;
    jobject _managerObject;
    NSDateFormatter *_dateFormatter;
    BOOL _sending;
    
    uint64_t _lastBalance;
    NSTimer *_balanceChecker;
    
    NSString *_appSupportDirectoryIdentifier;
}

- (jclass)jClassForClass:(NSString *)class;
- (void)onBalanceChanged;
- (void)onSynchronizationChanged:(double)progress blockCount:(long)blockCount totalBlocks:(long)totalBlocks;
- (void)onPeerCountChanged:(int)peerCount;
- (void)onTransactionChanged:(NSString *)txid;
- (void)onTransactionSucceeded:(NSString *)txid;
- (void)onTransactionFailed;
- (void)checkBalance:(NSTimer *)timer;

- (uint64_t)balance:(int)type;

@property (strong) void(^sendCompletionBlock)(NSString *hash);

@end


JNIEXPORT void JNICALL onBalanceChanged
(JNIEnv *env, jobject thisobject)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [[HIBitcoinManager defaultManager] onBalanceChanged];
    [pool release];
}


JNIEXPORT void JNICALL onPeerCountChanged
(JNIEnv *env, jobject thisobject, jint peerCount)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [[HIBitcoinManager defaultManager] onPeerCountChanged:(int)peerCount];
    [pool release];
}

JNIEXPORT void JNICALL onSynchronizationUpdate
(JNIEnv *env, jobject thisobject, jdouble progress, jlong blockCount, jlong totalBlocks)
{
    NSLog(@"========== total: %ld", (long)totalBlocks);
    
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [[HIBitcoinManager defaultManager] onSynchronizationChanged:(double)progress blockCount:blockCount totalBlocks:totalBlocks];
    [pool release];
}

JNIEXPORT void JNICALL onTransactionChanged
(JNIEnv *env, jobject thisobject, jstring txid)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    if (txid)
    {
        const char *txc = (*env)->GetStringUTFChars(env, txid, NULL);
        
        NSString *bStr = [NSString stringWithUTF8String:txc];
        (*env)->ReleaseStringUTFChars(env, txid, txc);
        [[HIBitcoinManager defaultManager] onTransactionChanged:bStr];

    }
    
    [pool release];
}

JNIEXPORT void JNICALL onTransactionSucceeded
(JNIEnv *env, jobject thisobject, jstring txid)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    if (txid)
    {
        const char *txc = (*env)->GetStringUTFChars(env, txid, NULL);
        
        NSString *bStr = [NSString stringWithUTF8String:txc];
        (*env)->ReleaseStringUTFChars(env, txid, txc);
        [[HIBitcoinManager defaultManager] onTransactionSucceeded:bStr];
    }
    
    [pool release];
}

JNIEXPORT void JNICALL onTransactionFailed
(JNIEnv *env, jobject thisobject)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [[HIBitcoinManager defaultManager] onTransactionFailed];
    
    [pool release];
}


static JNINativeMethod methods[] = {
    {"onBalanceChanged",        "()V",                                     (void *)&onBalanceChanged},
    {"onTransactionChanged",    "(Ljava/lang/String;)V",                   (void *)&onTransactionChanged},
    {"onTransactionSuccess",    "(Ljava/lang/String;)V",                   (void *)&onTransactionSucceeded},
    {"onTransactionFailed",     "()V",                                     (void *)&onTransactionFailed},
    {"onPeerCountChanged",       "(I)V",                                     (void *)&onPeerCountChanged},
    {"onSynchronizationUpdate", "(DJJ)V",                                    (void *)&onSynchronizationUpdate}
};

NSString * const kHIBitcoinManagerTransactionChangedNotification = @"kJHIBitcoinManagerTransactionChangedNotification";
NSString * const kHIBitcoinManagerStartedNotification = @"kJHIBitcoinManagerStartedNotification";
NSString * const kHIBitcoinManagerStoppedNotification = @"kJHIBitcoinManagerStoppedNotification";

#define kHIDefaultAppSupportIdentifier @"com.Hive.BitcoinJKit"
#define kHIDefaultAppName @"bitcoinkit"

static HIBitcoinManager *_defaultManager = nil;

@implementation HIBitcoinManager

@synthesize appName = _appName;
@synthesize dataURL = _dataURL;
@synthesize connections = _connections;
@synthesize isRunning = _isRunning;
@synthesize balance = _balance;
@synthesize syncProgress = _syncProgress;
@synthesize peerCount = _peerCount;
@synthesize testingNetwork = _testingNetwork;
@synthesize enableMining = _enableMining;
@synthesize walletAddress;
@synthesize currentBlockCount=_currentBlockCount;
@synthesize totalBlocks=_totalBlocks;

+ (HIBitcoinManager *)defaultManager
{
    static dispatch_once_t oncePredicate;
    if (!_defaultManager)
        dispatch_once(&oncePredicate, ^{
            _defaultManager = [[self alloc] init];
        });
    
    return _defaultManager;
}

- (jclass)jClassForClass:(NSString *)class
{
    jclass cls = (*_jniEnv)->FindClass(_jniEnv, [class UTF8String]);
    
    if ((*_jniEnv)->ExceptionCheck(_jniEnv))
    {
        (*_jniEnv)->ExceptionDescribe(_jniEnv);
        (*_jniEnv)->ExceptionClear(_jniEnv);
        
        @throw [NSException exceptionWithName:@"Java exception" reason:@"Java VM raised an exception" userInfo:@{@"class": class}];
    }
    return cls;
}

- (void)setAppSupportDirectoryIdentifier:(NSString *)appSupportDirectoryIdentifier
{
    if(_appSupportDirectoryIdentifier != appSupportDirectoryIdentifier)
    {
        [_appSupportDirectoryIdentifier release];
        _appSupportDirectoryIdentifier = [appSupportDirectoryIdentifier retain];
        
        // set the new data url
        self.dataURL = [[[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] lastObject] URLByAppendingPathComponent:self.appSupportDirectoryIdentifier];
    }
}

- (NSString *)appSupportDirectoryIdentifier
{
    return _appSupportDirectoryIdentifier;
}

- (id)init
{
    self = [super init];
    if (self)
    {
        self.appSupportDirectoryIdentifier   = kHIDefaultAppSupportIdentifier;
        self.appName                         = kHIDefaultAppName;

        _dateFormatter = [[NSDateFormatter alloc] init];
        _dateFormatter.locale = [[[NSLocale alloc] initWithLocaleIdentifier:@"en_GB"] autorelease];
        _dateFormatter.dateFormat = @"EEE MMM dd HH:mm:ss zzz yyyy";
        _connections = 0;
        _balance = 0;
        _sending = NO;
        _syncProgress = 0.0;
        _testingNetwork = NO;
        _enableMining = NO;
        _isRunning = NO;
        
        self.dataURL = [[[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] lastObject] URLByAppendingPathComponent:self.appSupportDirectoryIdentifier];
        
        _vmArgs.version = JNI_VERSION_1_2;
        _vmArgs.nOptions = 1;
        _vmArgs.ignoreUnrecognized = JNI_TRUE;
        
        JavaVMOption options[_vmArgs.nOptions];
        _vmArgs.options = options;
        
//        options[0].optionString = (char*) "-Xbootclasspath:[bootJar]";
        NSBundle *myBundle = [NSBundle bundleWithIdentifier:@"com.hive.BitcoinJKit"];
        options[0].optionString = (char *)[[NSString stringWithFormat:@"-Djava.class.path=%@", [myBundle pathForResource:@"boot" ofType:@"jar"]] UTF8String];
        
        JavaVM* vm;
        void *env;
        JNI_CreateJavaVM(&vm, &env, &_vmArgs);
        _jniEnv = (JNIEnv *)(env);
        
        
        // We need to create the manager object
        jclass mgrClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];
        (*_jniEnv)->RegisterNatives(_jniEnv, mgrClass, methods, sizeof(methods)/sizeof(methods[0]));
        
        jmethodID constructorM = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "<init>", "()V");
        if (constructorM)
        {
            _managerObject = (*_jniEnv)->NewObject(_jniEnv, mgrClass, constructorM);
        }
        
        //_balanceChecker = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkBalance:) userInfo:nil repeats:YES];
    }
    
    return self;
}

- (void)dealloc
{
    [self stop];
    self.sendCompletionBlock = nil;
    [super dealloc];
}

- (void)start
{
    [[NSFileManager defaultManager] createDirectoryAtURL:_dataURL withIntermediateDirectories:YES attributes:0 error:NULL];
    
    jclass mgrClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];
    
    // Find testing network method in the class
    jmethodID testingM = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "setTestingNetwork", "(Z)V");
    
    if (testingM == NULL)
        return;
    
    (*_jniEnv)->CallVoidMethod(_jniEnv, _managerObject, testingM, _testingNetwork);
    if ((*_jniEnv)->ExceptionCheck(_jniEnv))
    {
        (*_jniEnv)->ExceptionDescribe(_jniEnv);
        (*_jniEnv)->ExceptionClear(_jniEnv);
    }
  
    
    // Now set the folder
    jmethodID setDataDirM = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "setDataDirectory", "(Ljava/lang/String;)V");
    if (setDataDirM == NULL)
        return;
    
    (*_jniEnv)->CallVoidMethod(_jniEnv, _managerObject, setDataDirM, (*_jniEnv)->NewStringUTF(_jniEnv, _dataURL.path.UTF8String));
    if ((*_jniEnv)->ExceptionCheck(_jniEnv))
    {
        (*_jniEnv)->ExceptionDescribe(_jniEnv);
        (*_jniEnv)->ExceptionClear(_jniEnv);
    }
    
    // Now set the app name
    jmethodID setAppNameM = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "setAppName", "(Ljava/lang/String;)V");
    if (setAppNameM == NULL)
        return;
    
    (*_jniEnv)->CallVoidMethod(_jniEnv, _managerObject, setAppNameM, (*_jniEnv)->NewStringUTF(_jniEnv, _appName.UTF8String));
    if ((*_jniEnv)->ExceptionCheck(_jniEnv))
    {
        (*_jniEnv)->ExceptionDescribe(_jniEnv);
        (*_jniEnv)->ExceptionClear(_jniEnv);
    }

    
    // We're ready! Let's start
    jmethodID startM = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "start", "()V");
    
    if (startM == NULL)
        return;
    
    (*_jniEnv)->CallVoidMethod(_jniEnv, _managerObject, startM);
    if ((*_jniEnv)->ExceptionCheck(_jniEnv))
    {
        (*_jniEnv)->ExceptionDescribe(_jniEnv);
        (*_jniEnv)->ExceptionClear(_jniEnv);
    }
    [self willChangeValueForKey:@"isRunning"];
    _isRunning = YES;
    [self didChangeValueForKey:@"isRunning"];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kHIBitcoinManagerStartedNotification object:self];
    [self willChangeValueForKey:@"walletAddress"];
    [self didChangeValueForKey:@"walletAddress"];
}

- (NSArray *)allWalletAddresses
{
    jclass mgrClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];
    jmethodID allAddressesM = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "getAllWalletAddressesJSON", "()Ljava/lang/String;");
    
    if (allAddressesM)
    {
        jstring wa = (*_jniEnv)->CallObjectMethod(_jniEnv, _managerObject, allAddressesM);
        
        const char *waStr = (*_jniEnv)->GetStringUTFChars(_jniEnv, wa, NULL);
        
        NSString *str = [NSString stringWithUTF8String:waStr];
        (*_jniEnv)->ReleaseStringUTFChars(_jniEnv, wa, waStr);
        
        NSArray *addresses = [NSJSONSerialization JSONObjectWithData:[str dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
        
        return addresses;
    }
    
    return nil;
}

- (NSString *)walletAddress
{
    jclass mgrClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];    
    jmethodID walletM = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "getWalletAddress", "()Ljava/lang/String;");
    
    if (walletM)
    {
        jstring wa = (*_jniEnv)->CallObjectMethod(_jniEnv, _managerObject, walletM);
        
        const char *waStr = (*_jniEnv)->GetStringUTFChars(_jniEnv, wa, NULL);
        
        NSString *str = [NSString stringWithUTF8String:waStr];
        (*_jniEnv)->ReleaseStringUTFChars(_jniEnv, wa, waStr);
        
        return str;
    }
    
    return nil;
}

- (NSString *)base64Wallet
{
    jclass mgrClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];
    jmethodID walletM = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "getWalletAddress", "()Ljava/lang/String;");
    
    if (walletM)
    {
        jstring wa = (*_jniEnv)->CallObjectMethod(_jniEnv, _managerObject, walletM);
        
        const char *waStr = (*_jniEnv)->GetStringUTFChars(_jniEnv, wa, NULL);
        
        NSString *str = [NSString stringWithUTF8String:waStr];
        (*_jniEnv)->ReleaseStringUTFChars(_jniEnv, wa, waStr);
        
        return str;
    }
    
    return nil;
}

- (NSString *)walletFileBase64String
{
    jclass mgrClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];
    jmethodID walletM = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "getWalletFileBase64String", "()Ljava/lang/String;");
    
    if (walletM)
    {
        jstring wa = (*_jniEnv)->CallObjectMethod(_jniEnv, _managerObject, walletM);
        
        if(!wa)
        {
            return nil;
        }
        const char *waStr = (*_jniEnv)->GetStringUTFChars(_jniEnv, wa, NULL);
        
        NSString *str = [NSString stringWithUTF8String:waStr];
        (*_jniEnv)->ReleaseStringUTFChars(_jniEnv, wa, waStr);
        
        return str;
    }
    
    return nil;
}

- (void)stop
{
    [_balanceChecker invalidate];
    _balanceChecker = nil;
    jclass mgrClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];    
    // We're ready! Let's start
    jmethodID stopM = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "stop", "()V");
    
    if (stopM == NULL)
        return;
    
    (*_jniEnv)->CallVoidMethod(_jniEnv, _managerObject, stopM);
    if ((*_jniEnv)->ExceptionCheck(_jniEnv))
    {
        (*_jniEnv)->ExceptionDescribe(_jniEnv);
        (*_jniEnv)->ExceptionClear(_jniEnv);
    }
    
    [self willChangeValueForKey:@"isRunning"];
    _isRunning = NO;
    [self didChangeValueForKey:@"isRunning"];
    [[NSNotificationCenter defaultCenter] postNotificationName:kHIBitcoinManagerStoppedNotification object:self];
}

- (NSDictionary *)modifiedTransactionForTransaction:(NSDictionary *)transaction
{
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithDictionary:transaction];
    NSDate *date = [_dateFormatter dateFromString:transaction[@"time"]];
    if (date)
        d[@"time"] = date;
    else
        d[@"time"] = [NSDate dateWithTimeIntervalSinceNow:0];

    return d;
}

- (NSDictionary *)transactionForHash:(NSString *)hash
{
    jclass mgrClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];
    // We're ready! Let's start
    jmethodID tM = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "getTransaction", "(Ljava/lang/String;)Ljava/lang/String;");
    
    if (tM == NULL)
        return nil;
    

    jstring transString = (*_jniEnv)->CallObjectMethod(_jniEnv, _managerObject, tM, (*_jniEnv)->NewStringUTF(_jniEnv, hash.UTF8String));
    
    if (transString)
    {
        const char *transChars = (*_jniEnv)->GetStringUTFChars(_jniEnv, transString, NULL);
        
        NSString *bStr = [NSString stringWithUTF8String:transChars];
        (*_jniEnv)->ReleaseStringUTFChars(_jniEnv, transString, transChars);
        
        return [self modifiedTransactionForTransaction:[NSJSONSerialization JSONObjectWithData:[bStr dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL]];
        
    }
    
    return nil;
}

- (NSDictionary *)transactionAtIndex:(NSUInteger)index
{
    jclass mgrClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];
    // We're ready! Let's start
    jmethodID tM = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "getTransaction", "(I)Ljava/lang/String;");
    
    if (tM == NULL)
        return nil;
    
    
    jstring transString = (*_jniEnv)->CallObjectMethod(_jniEnv, _managerObject, tM, index);
    
    if (transString)
    {
        const char *transChars = (*_jniEnv)->GetStringUTFChars(_jniEnv, transString, NULL);
        
        NSString *bStr = [NSString stringWithUTF8String:transChars];
        (*_jniEnv)->ReleaseStringUTFChars(_jniEnv, transString, transChars);
        
        return [self modifiedTransactionForTransaction:[NSJSONSerialization JSONObjectWithData:[bStr dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL]];
        
    }
    
    return nil;
}

- (NSArray *)allTransactions:(int)max
{
    jclass mgrClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];
    // We're ready! Let's start
    jmethodID tM = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "getAllTransactions", "(I)Ljava/lang/String;");
    
    if (tM == NULL)
        return nil;
    
    jstring transString = (*_jniEnv)->CallObjectMethod(_jniEnv, _managerObject, tM, (jint)max);
    
    if (transString)
    {
        const char *transChars = (*_jniEnv)->GetStringUTFChars(_jniEnv, transString, NULL);
        
        NSString *bStr = [NSString stringWithUTF8String:transChars];
        (*_jniEnv)->ReleaseStringUTFChars(_jniEnv, transString, transChars);
        
        NSArray *ts = [NSJSONSerialization JSONObjectWithData:[bStr dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
        NSMutableArray *mts = [NSMutableArray array];
        
        for (NSDictionary *t in ts)
        {
            [mts addObject:[self modifiedTransactionForTransaction:t]];
        }
        
        return mts;
        
        
    }
    
    return nil;
}

- (NSArray *)transactionsWithRange:(NSRange)range
{
    jclass mgrClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];
    // We're ready! Let's start
    jmethodID tM = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "getTransaction", "(II)Ljava/lang/String;");
    
    if (tM == NULL)
        return nil;
    
    
    jstring transString = (*_jniEnv)->CallObjectMethod(_jniEnv, _managerObject, tM, range.location, range.length);
    
    if (transString)
    {
        const char *transChars = (*_jniEnv)->GetStringUTFChars(_jniEnv, transString, NULL);
        
        NSString *bStr = [NSString stringWithUTF8String:transChars];
        (*_jniEnv)->ReleaseStringUTFChars(_jniEnv, transString, transChars);
        
        NSArray *ts = [NSJSONSerialization JSONObjectWithData:[bStr dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
        NSMutableArray *mts = [NSMutableArray array];
        
        for (NSDictionary *t in ts)
        {
            [mts addObject:[self modifiedTransactionForTransaction:t]];
        }
        
        return mts;

        
        
    }
    
    return nil;
}

- (BOOL)isAddressValid:(NSString *)address
{
    jclass mgrClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];
    // We're ready! Let's start
    jmethodID aV = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "isAddressValid", "(Ljava/lang/String;)Z");
    
    if (aV == NULL)
        return NO;
    
    jboolean valid = (*_jniEnv)->CallBooleanMethod(_jniEnv, _managerObject, aV, (*_jniEnv)->NewStringUTF(_jniEnv, address.UTF8String));
    return valid;
}

- (NSString *)commitPreparedTransaction
{
    jclass mgrClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];
    // We're ready! Let's start
    jmethodID commitTXM = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "commitSendRequest", "()Ljava/lang/String;");
    
    if (commitTXM == NULL)
    {
        return nil;
    }
    
    jstring txHashString = (*_jniEnv)->CallObjectMethod(_jniEnv, _managerObject, commitTXM);
    
    if (txHashString)
    {
        const char *tsHashChars = (*_jniEnv)->GetStringUTFChars(_jniEnv, txHashString, NULL);
        
        NSString *txHashNSString = [NSString stringWithUTF8String:tsHashChars];
        (*_jniEnv)->ReleaseStringUTFChars(_jniEnv, txHashString, tsHashChars);
        return txHashNSString;
    }
    
    return nil;
}
- (NSInteger)prepareSendCoins:(uint64_t)coins toReceipent:(NSString *)receipent comment:(NSString *)comment
{
    jclass mgrClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];
    // We're ready! Let's start
    jmethodID sendM = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "createSendRequest", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;");
    
    if (sendM == NULL)
    {
        return kHI_PREPARE_SEND_COINS_DID_FAIL;
    }
    
    jstring feeString = (*_jniEnv)->CallObjectMethod(_jniEnv, _managerObject, sendM, (*_jniEnv)->NewStringUTF(_jniEnv, [[NSString stringWithFormat:@"%lld", coins] UTF8String]),
                                                         (*_jniEnv)->NewStringUTF(_jniEnv, receipent.UTF8String));
    
    if (feeString)
    {
        const char *feeChars = (*_jniEnv)->GetStringUTFChars(_jniEnv, feeString, NULL);
        
        NSString *fStr = [NSString stringWithUTF8String:feeChars];
        (*_jniEnv)->ReleaseStringUTFChars(_jniEnv, feeString, feeChars);
 
 
        if([fStr isEqualToString:@""])
        {
            return kHI_PREPARE_SEND_COINS_DID_FAIL;
        }
        
        return [fStr longLongValue];
    }
    
    return kHI_PREPARE_SEND_COINS_DID_FAIL;
}

- (BOOL)encryptWalletWith:(NSString *)passwd
{
    return NO;
}

- (BOOL)changeWalletEncryptionKeyFrom:(NSString *)oldpasswd to:(NSString *)newpasswd
{
    return NO;
}

- (BOOL)unlockWalletWith:(NSString *)passwd
{
    return NO;
}

- (void)lockWallet
{
    
}

- (BOOL)exportWalletTo:(NSURL *)exportURL
{
    return NO;
}

- (BOOL)importWalletFrom:(NSURL *)importURL
{
    return NO;
}

- (uint64_t)balance
{
    return [self balance:0];
}

- (uint64_t)balanceUnconfirmed
{
    return [self balance:1];
}

- (uint64_t)balance:(int)type
{
    jclass mgrClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];
    // We're ready! Let's start
    jmethodID balanceM = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "getBalanceString", "(I)Ljava/lang/String;");
    
    if (balanceM == NULL)
        return 0;
    
    jstring balanceString = (*_jniEnv)->CallObjectMethod(_jniEnv, _managerObject, balanceM, (jint)type);
    
    if (balanceString)
    {
        const char *balanceChars = (*_jniEnv)->GetStringUTFChars(_jniEnv, balanceString, NULL);
        
        NSString *bStr = [NSString stringWithUTF8String:balanceChars];
        (*_jniEnv)->ReleaseStringUTFChars(_jniEnv, balanceString, balanceChars);
        
        return [bStr longLongValue];
    }
    
    return 0;
}

- (void)checkBalance:(NSTimer *)timer
{
    uint64_t currentBalance = [self balance];
    if (_lastBalance != currentBalance)
    {
        [self onBalanceChanged];
        _lastBalance = currentBalance;
    }
}

- (NSUInteger)transactionCount
{
    jclass mgrClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];
    // We're ready! Let's start
    jmethodID tCM = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "getTransactionCount", "()I");
    
    if (tCM == NULL)
        return 0;
    
    jint c = (*_jniEnv)->CallIntMethod(_jniEnv, _managerObject, tCM);
    
    return (NSUInteger)c;
}

#pragma mark - Key Stack

- (NSString *)addKey
{
    jclass mgrClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];
    // We're ready! Let's start
    jmethodID addKeyM = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "addKey", "()Ljava/lang/String;");
    
    if (addKeyM == NULL)
    return nil;
    
    jstring newKeyString = (*_jniEnv)->CallObjectMethod(_jniEnv, _managerObject, addKeyM);
    
    if (newKeyString)
    {
        const char *newKeyStringC = (*_jniEnv)->GetStringUTFChars(_jniEnv, newKeyString, NULL);
        
        NSString *newKeyStringNS = [NSString stringWithUTF8String:newKeyStringC];
        (*_jniEnv)->ReleaseStringUTFChars(_jniEnv, newKeyString, newKeyStringC);
        
        return newKeyStringNS;
    }
    
    return nil;
}

#pragma mark - Callbacks

- (void)onBalanceChanged
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self willChangeValueForKey:@"balance"];
        [self didChangeValueForKey:@"balance"];
    });
}

- (void)onPeerCountChanged:(int)peerCount
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self willChangeValueForKey:@"peerCount"];
        _peerCount = (NSUInteger)peerCount;
        [self didChangeValueForKey:@"peerCount"];
    });
}

- (void)onSynchronizationChanged:(double)progress blockCount:(long)blockCount totalBlocks:(long)totalBlocks
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self willChangeValueForKey:@"syncProgress"];
        if(progress >= 0)
        {
            _syncProgress = (double)progress;
        }
        
        if(blockCount > 0)
        {
            _currentBlockCount = blockCount;
        }
        if(totalBlocks > 0)
        {
            _totalBlocks = totalBlocks;
        }
        [self didChangeValueForKey:@"syncProgress"];
    });
}

- (void)onTransactionChanged:(NSString *)txid
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self willChangeValueForKey:@"balance"];
        [[NSNotificationCenter defaultCenter] postNotificationName:kHIBitcoinManagerTransactionChangedNotification object:txid];
        [self didChangeValueForKey:@"balance"];
    });
}

- (void)onTransactionSucceeded:(NSString *)txid
{
    dispatch_async(dispatch_get_main_queue(), ^{
        _sending = NO;
        if (self.sendCompletionBlock)
        {
            self.sendCompletionBlock(txid);
        }
        [self.sendCompletionBlock release];
        self.sendCompletionBlock = nil;
    });
}

- (void)onTransactionFailed
{
    dispatch_async(dispatch_get_main_queue(), ^{
        _sending = NO;
        if (self.sendCompletionBlock)
        {
            self.sendCompletionBlock(nil);
        }
   
        [self.sendCompletionBlock release];
        self.sendCompletionBlock = nil;
    });
}

#pragma mark helpers
- (NSString *)formatNanobtc:(NSInteger)nanoBtc
{
    //TODO: nice and configurable
    return [NSString stringWithFormat:@"%.6g ฿", (double)nanoBtc/100000000];
}

@end
