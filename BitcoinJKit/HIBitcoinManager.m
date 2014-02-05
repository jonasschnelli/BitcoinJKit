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
#import "HIBitcoinErrorCodes.h"
#import "HIBitcoinInternalErrorCodes.h"

#import <JavaVM/jni.h>

@interface HIBitcoinManager ()
{
    JavaVM *_vm;
    JNIEnv *_jniEnv;
    JavaVMInitArgs _vmArgs;
    jobject _managerObject;
    jclass _managerClass;
    NSDateFormatter *_dateFormatter;
    BOOL _sending;
    
    uint64_t _lastBalance;
    NSTimer *_balanceChecker;
    
    NSString *_appSupportDirectoryIdentifier;
}

@property (nonatomic, strong) NSArray *availableBitcoinFormats;

- (jclass)jClassForClass:(NSString *)class;
- (void)onBalanceChanged;
- (void)onSynchronizationChanged:(double)progress blockCount:(long)blockCount totalBlocks:(long)totalBlocks;
- (void)onPeerCountChanged:(int)peerCount;
- (void)onTransactionChanged:(NSString *)txid;
- (void)onTransactionSucceeded:(NSString *)txid;
- (void)onCoinsReceived:(NSString *)txid;
- (void)onWalletChanged;
- (void)onTransactionFailed;
- (void)handleJavaException:(jthrowable)exception useExceptionHandler:(BOOL)useHandler error:(NSError **)returnedError;
- (void)checkBalance:(NSTimer *)timer;

- (uint64_t)balance:(int)type;

@property (strong) void(^sendCompletionBlock)(NSString *hash);

@end

#pragma mark - Helper functions for conversion

NSString * NSStringFromJString(JNIEnv *env, jstring javaString)
{
    const char *chars = (*env)->GetStringUTFChars(env, javaString, NULL);
    NSString *objcString = [NSString stringWithUTF8String:chars];
    (*env)->ReleaseStringUTFChars(env, javaString, chars);
    
    return objcString;
}

jstring JStringFromNSString(JNIEnv *env, NSString *string)
{
    return (*env)->NewStringUTF(env, [string UTF8String]);
}

jarray JCharArrayFromNSData(JNIEnv *env, NSData *data)
{
    jsize length = (jsize)(data.length / sizeof(jchar));
    jcharArray charArray = (*env)->NewCharArray(env, length);
    (*env)->SetCharArrayRegion(env, charArray, 0, length, data.bytes);
    return charArray;
}

JNIEXPORT void JNICALL onBalanceChanged (JNIEnv *env, jobject thisobject)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [[HIBitcoinManager defaultManager] onBalanceChanged];
    [pool release];
}


JNIEXPORT void JNICALL onPeerCountChanged (JNIEnv *env, jobject thisobject, jint peerCount)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [[HIBitcoinManager defaultManager] onPeerCountChanged:(int)peerCount];
    [pool release];
}

JNIEXPORT void JNICALL onSynchronizationUpdate (JNIEnv *env, jobject thisobject, jdouble progress, jlong blockCount, jlong totalBlocks)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [[HIBitcoinManager defaultManager] onSynchronizationChanged:(double)progress blockCount:blockCount totalBlocks:totalBlocks];
    [pool release];
}

JNIEXPORT void JNICALL onTransactionChanged (JNIEnv *env, jobject thisobject, jstring txid)
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


JNIEXPORT void JNICALL onWalletChanged (JNIEnv *env, jobject thisobject)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [[HIBitcoinManager defaultManager] onWalletChanged];
    [pool release];
}

JNIEXPORT void JNICALL onCoinsReceived (JNIEnv *env, jobject thisobject, jstring txid)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    if (txid)
    {
        const char *txc = (*env)->GetStringUTFChars(env, txid, NULL);
        
        NSString *bStr = [NSString stringWithUTF8String:txc];
        (*env)->ReleaseStringUTFChars(env, txid, txc);
        [[HIBitcoinManager defaultManager] onCoinsReceived:bStr];
        
    }
    
    [pool release];
}

JNIEXPORT void JNICALL onTransactionSucceeded (JNIEnv *env, jobject thisobject, jstring txid)
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

JNIEXPORT void JNICALL onException(JNIEnv *env, jobject thisobject, jthrowable jexception)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [[HIBitcoinManager defaultManager] handleJavaException:jexception useExceptionHandler:YES error:NULL];
    [pool release];
}

JNIEXPORT void JNICALL onTransactionFailed (JNIEnv *env, jobject thisobject)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [[HIBitcoinManager defaultManager] onTransactionFailed];
    
    [pool release];
}

JNIEXPORT void JNICALL receiveLogFromJVM(JNIEnv *env, jobject thisobject, jstring fileName, jstring methodName,
                                         int lineNumber, jint level, jstring msg)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    const char *fileNameString = (*env)->GetStringUTFChars(env, fileName, NULL);
    const char *methodNameString = (*env)->GetStringUTFChars(env, methodName, NULL);
    
    NSLog(@"%@", (NSString *)NSStringFromJString(env, msg));
    
    (*env)->ReleaseStringUTFChars(env, fileName, fileNameString);
    (*env)->ReleaseStringUTFChars(env, methodName, methodNameString);
    [pool release];
}

static JNINativeMethod methods[] = {
    {"onBalanceChanged",        "()V",                                     (void *)&onBalanceChanged},
    {"onTransactionChanged",    "(Ljava/lang/String;)V",                   (void *)&onTransactionChanged},
    {"onHICoinsReceived",       "(Ljava/lang/String;)V",                   (void *)&onCoinsReceived},
    {"onHIWalletChanged",       "()V",                                     (void *)&onWalletChanged},
    {"onTransactionSuccess",    "(Ljava/lang/String;)V",                   (void *)&onTransactionSucceeded},
    {"onTransactionFailed",     "()V",                                     (void *)&onTransactionFailed},
    {"onPeerCountChanged",       "(I)V",                                   (void *)&onPeerCountChanged},
    {"onSynchronizationUpdate", "(DJJ)V",                                  (void *)&onSynchronizationUpdate}
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

- (jmethodID)jMethodWithName:(char *)name signature:(char *)signature
{
    jmethodID method = (*_jniEnv)->GetMethodID(_jniEnv, _managerClass, name, signature);
    
    if (method == NULL)
    {
        @throw [NSException exceptionWithName:@"Java exception"
                                       reason:[NSString stringWithFormat:@"Method not found: %s (%s)", name, signature]
                                     userInfo:nil];
    }
    
    return method;
}

- (BOOL)callBooleanMethodWithName:(char *)name signature:(char *)signature, ...
{
    jmethodID method = [self jMethodWithName:name signature:signature];
    
    va_list args;
    va_start(args, signature);
    jboolean result = (*_jniEnv)->CallBooleanMethodV(_jniEnv, _managerObject, method, args);
    va_end(args);
    
    [self handleJavaExceptions:NULL];
    
    return result;
}

- (int)callIntegerMethodWithName:(char *)name signature:(char *)signature, ...
{
    jmethodID method = [self jMethodWithName:name signature:signature];
    
    va_list args;
    va_start(args, signature);
    jint result = (*_jniEnv)->CallIntMethodV(_jniEnv, _managerObject, method, args);
    va_end(args);
    
    [self handleJavaExceptions:NULL];
    
    return result;
}

- (long)callLongMethodWithName:(char *)name signature:(char *)signature, ...
{
    jmethodID method = [self jMethodWithName:name signature:signature];
    
    va_list args;
    va_start(args, signature);
    jlong result = (*_jniEnv)->CallLongMethodV(_jniEnv, _managerObject, method, args);
    va_end(args);
    
    [self handleJavaExceptions:NULL];
    
    return result;
}

- (jobject)callObjectMethodWithName:(char *)name error:(NSError **)error signature:(char *)signature, ...
{
    jmethodID method = [self jMethodWithName:name signature:signature];
    
    va_list args;
    va_start(args, signature);
    jobject result = (*_jniEnv)->CallObjectMethodV(_jniEnv, _managerObject, method, args);
    va_end(args);
    
    [self handleJavaExceptions:error];
    
    return result;
}

- (void)callVoidMethodWithName:(char *)name error:(NSError **)error signature:(char *)signature, ...
{
    jmethodID method = [self jMethodWithName:name signature:signature];
    
    va_list args;
    va_start(args, signature);
    (*_jniEnv)->CallVoidMethodV(_jniEnv, _managerObject, method, args);
    va_end(args);
    
    [self handleJavaExceptions:error];
}


- (void)handleJavaExceptions:(NSError **)error
{
    if ((*_jniEnv)->ExceptionCheck(_jniEnv))
    {
        // get the exception object
        jthrowable exception = (*_jniEnv)->ExceptionOccurred(_jniEnv);
        
        [self handleJavaException:exception useExceptionHandler:NO error:error];
    }
    else if (error)
    {
        *error = nil;
    }
}

- (void)handleJavaException:(jthrowable)exception useExceptionHandler:(BOOL)useHandler error:(NSError **)returnedError
{
    BOOL callerWantsToHandleErrors = returnedError != nil;
    
    if (callerWantsToHandleErrors)
    {
        *returnedError = nil;
    }
    
    // exception has to be cleared if it exists
    (*_jniEnv)->ExceptionClear(_jniEnv);
    
    // try to get exception details from Java
    // note: we need to do this on the main thread - if this is called from a background thread,
    // the toString() call returns nil and throws a new exception (java.lang.StackOverflowException)
    dispatch_block_t processException = ^{
        NSError *error = [NSError errorWithDomain:@"BitcoinKit"
                                             code:[self errorCodeForJavaException:exception]
                                         userInfo:[self createUserInfoForJavaException:exception]];
        
        NSString *exceptionClass = [self getJavaExceptionClassName:exception];
        
        NSLog(@"Java exception caught (%@): %@\n%@",
              exceptionClass,
              error.userInfo[NSLocalizedFailureReasonErrorKey],
              error.userInfo[@"stackTrace"] ?: @"");
        
        if (callerWantsToHandleErrors && error.code != kHIBitcoinManagerUnexpectedError)
        {
            *returnedError = error;
        }
        else
        {
            NSException *exception = [NSException exceptionWithName:@"Java exception"
                                                             reason:error.userInfo[NSLocalizedFailureReasonErrorKey]
                                                           userInfo:error.userInfo];
            if (useHandler && self.exceptionHandler)
            {
                self.exceptionHandler(exception);
            }
            else
            {
                @throw exception;
            }
        }
    };
    
    if (dispatch_get_current_queue() != dispatch_get_main_queue())
    {
        // run the above code synchronously on the main thread,
        // otherwise Java GC can clean up the exception object and we get a memory access error
        dispatch_sync(dispatch_get_main_queue(), processException);
    }
    else
    {
        // if this is the main thread, we can't use dispatch_sync or the whole thing will lock up
        processException();
    }
}

- (NSInteger)errorCodeForJavaException:(jthrowable)exception
{
    NSString *exceptionClass = [self getJavaExceptionClassName:exception];
    if ([exceptionClass isEqual:@"com.google.bitcoin.store.UnreadableWalletException"])
    {
        return kHIBitcoinManagerUnreadableWallet;
    }
    else if ([exceptionClass isEqual:@"com.google.bitcoin.store.BlockStoreException"])
    {
        return kHIBitcoinManagerBlockStoreError;
    }
    else if ([exceptionClass isEqual:@"java.lang.IllegalArgumentException"])
    {
        return kHIIllegalArgumentException;
    }
    else if ([exceptionClass isEqual:@"com.hive.bitcoinkit.NoWalletException"])
    {
        return kHIBitcoinManagerNoWallet;
    }
    else if ([exceptionClass isEqual:@"com.hive.bitcoinkit.ExistingWalletException"])
    {
        return kHIBitcoinManagerWalletExists;
    }
    else if ([exceptionClass isEqual:@"com.hive.bitcoinkit.WrongPasswordException"])
    {
        return kHIBitcoinManagerWrongPassword;
    }
    else
    {
        return kHIBitcoinManagerUnexpectedError;
    }
}

- (NSString *)getJavaExceptionClassName:(jthrowable)exception
{
    jclass exceptionClass = (*_jniEnv)->GetObjectClass(_jniEnv, exception);
    jmethodID getClassMethod = (*_jniEnv)->GetMethodID(_jniEnv, exceptionClass, "getClass", "()Ljava/lang/Class;");
    jobject classObject = (*_jniEnv)->CallObjectMethod(_jniEnv, exception, getClassMethod);
    jobject class = (*_jniEnv)->GetObjectClass(_jniEnv, classObject);
    jmethodID getNameMethod = (*_jniEnv)->GetMethodID(_jniEnv, class, "getName", "()Ljava/lang/String;");
    jstring name = (*_jniEnv)->CallObjectMethod(_jniEnv, exceptionClass, getNameMethod);
    return NSStringFromJString(_jniEnv, name);
}

- (NSDictionary *)createUserInfoForJavaException:(jthrowable)exception
{
    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    userInfo[NSLocalizedFailureReasonErrorKey] = [self getJavaExceptionMessage:exception] ?: @"Java VM raised an exception";
    
    NSString *stackTrace = [self getJavaExceptionStackTrace:exception];
    if (stackTrace)
    {
        userInfo[@"stackTrace"] = stackTrace;
    }
    return userInfo;
}

- (NSString *)getJavaExceptionMessage:(jthrowable)exception
{
    jclass exceptionClass = (*_jniEnv)->GetObjectClass(_jniEnv, exception);
    
    if (exceptionClass)
    {
        jmethodID toStringMethod = (*_jniEnv)->GetMethodID(_jniEnv, exceptionClass, "toString", "()Ljava/lang/String;");
        
        if (toStringMethod)
        {
            jstring description = (*_jniEnv)->CallObjectMethod(_jniEnv, exception, toStringMethod);
            
            if ((*_jniEnv)->ExceptionCheck(_jniEnv))
            {
                (*_jniEnv)->ExceptionDescribe(_jniEnv);
                (*_jniEnv)->ExceptionClear(_jniEnv);
            }
            
            if (description)
            {
                return NSStringFromJString(_jniEnv, description);
            }
        }
    }
    
    return nil;
}

- (NSString *)getJavaExceptionStackTrace:(jthrowable)exception
{
    jmethodID stackTraceMethod = (*_jniEnv)->GetMethodID(_jniEnv, _managerClass, "getExceptionStackTrace",
                                                         "(Ljava/lang/Throwable;)Ljava/lang/String;");
    
    if (stackTraceMethod)
    {
        jstring stackTrace = (*_jniEnv)->CallObjectMethod(_jniEnv, _managerObject, stackTraceMethod, exception);
        
        if ((*_jniEnv)->ExceptionCheck(_jniEnv))
        {
            (*_jniEnv)->ExceptionDescribe(_jniEnv);
            (*_jniEnv)->ExceptionClear(_jniEnv);
        }
        
        if (stackTrace)
        {
            return NSStringFromJString(_jniEnv, stackTrace);
        }
    }
    
    return nil;
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

- (void)createWalletWithPassword:(NSData *)password
                           error:(NSError **)error
{
    jarray charArray = JCharArrayFromNSData(_jniEnv, password);
    
    *error = nil;
    [self callVoidMethodWithName:"createWallet"
                           error:error
                       signature:"([C)V", charArray];
    
    [self zeroCharArray:charArray size:(jsize)(password.length / sizeof(jchar))];
    
    if (!*error)
    {
        [self didStart];
    }
}
    
- (id)init
{
    self = [super init];
    if (self)
    {
        self.locale = [NSLocale currentLocale];
        self.availableBitcoinFormats = @[@"BTC", @"mBTC", @"µBTC"];;
        
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
        _managerClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];
        (*_jniEnv)->RegisterNatives(_jniEnv, _managerClass, methods, sizeof(methods)/sizeof(methods[0]));
        
        JNINativeMethod loggerMethod;
        loggerMethod.name = "receiveLogFromJVM";
        loggerMethod.signature = "(Ljava/lang/String;Ljava/lang/String;IILjava/lang/String;)V";
        loggerMethod.fnPtr = &receiveLogFromJVM;
        
        jclass loggerClass = [self jClassForClass:@"org/slf4j/impl/CocoaLogger"];
        (*_jniEnv)->RegisterNatives(_jniEnv, loggerClass, &loggerMethod, 1);
        
        jmethodID constructorM = (*_jniEnv)->GetMethodID(_jniEnv, _managerClass, "<init>", "()V");
        if (constructorM)
        {
            _managerObject = (*_jniEnv)->NewObject(_jniEnv, _managerClass, constructorM);
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

- (void)resyncBlockchain:(NSError **)error
{
    NSString *blockchainFilename = [_appName stringByAppendingString:@".spvchain"];
    NSString *blockchainFilePath = [_dataURL.path stringByAppendingPathComponent:blockchainFilename];
    if([[NSFileManager defaultManager] fileExistsAtPath:blockchainFilePath])
    {
        [[NSFileManager defaultManager] removeItemAtPath:blockchainFilePath error:nil];
    }
    
    [self startBlockchain:error];
}

- (void)initialize:(NSError **)error
{
    [[NSFileManager defaultManager] createDirectoryAtURL:_dataURL withIntermediateDirectories:YES attributes:0 error:NULL];

    if(!_testingNetwork)
    {
        // check if there is a need to copy the checkpoint file
        NSString *checkpointFilename = [_appName stringByAppendingString:@".checkpoints"];
        NSString *checkpointFilePath = [_dataURL.path stringByAppendingPathComponent:checkpointFilename];
        
        if(![[NSFileManager defaultManager] fileExistsAtPath:checkpointFilePath])
        {
            // copy checkpoint file from the bundle
            [[NSFileManager defaultManager] copyItemAtPath:[[NSBundle mainBundle] pathForResource:@"checkpoints" ofType:@""] toPath:checkpointFilePath error:nil];
        }
    }
    
    [self callVoidMethodWithName:"setTestingNetwork" error:NULL signature:"(Z)V", _testingNetwork];
    
    // Now set the folder
    [self callVoidMethodWithName:"setDataDirectory" error:NULL signature:"(Ljava/lang/String;)V",
     JStringFromNSString(_jniEnv, self.dataURL.path)];
    
    // Now set the app name
    [self callVoidMethodWithName:"setAppName" error:NULL signature:"(Ljava/lang/String;)V",
     JStringFromNSString(_jniEnv, _appName)];
}

- (void)loadWallet:(NSError **)error
{
    // We're ready! Let's start
    [self callVoidMethodWithName:"loadWallet" error:error signature:"()V"];
}
    
- (void)startBlockchain:(NSError **)error
{
    // We're ready! Let's start
    [self callVoidMethodWithName:"startBlockchain" error:error signature:"()V"];
    
    if (!error || !*error)
    {
        [self didStart];
    }
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

#pragma mark - Wallet Stack

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

- (void)didStart
{
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

- (BOOL)saveWallet
{
    jclass mgrClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];
    // We're ready! Let's start
    jmethodID saveMethode = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "saveWallet", "()V");
    
    if (saveMethode == NULL)
        return NO;
    
    (*_jniEnv)->CallVoidMethod(_jniEnv, _managerObject, saveMethode);
    
    return YES;
}

- (BOOL)isWalletEncrypted
{
    jclass mgrClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];
    // We're ready! Let's start
    jmethodID isEncMethode = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "isWalletEncrypted", "()Z");
    
    if (isEncMethode == NULL)
        return NO;
    
    jboolean valid = (*_jniEnv)->CallBooleanMethod(_jniEnv, _managerObject, isEncMethode);
    return valid;
}

- (void)changeWalletPassword:(NSData *)fromPassword
                  toPassword:(NSData *)toPassword
                       error:(NSError **)error
{
    jarray fromCharArray = fromPassword ? JCharArrayFromNSData(_jniEnv, fromPassword) : NULL;
    jarray toCharArray = JCharArrayFromNSData(_jniEnv, toPassword);
    
    [self callVoidMethodWithName:"changeWalletPassword"
                           error:error
                       signature:"([C[C)V", fromCharArray, toCharArray];
    
    if (fromCharArray)
    {
        [self zeroCharArray:fromCharArray size:(jsize)(fromPassword.length / sizeof(jchar))];
    }
    
    [self zeroCharArray:toCharArray size:(jsize)(toPassword.length / sizeof(jchar))];
}

- (void)zeroCharArray:(jarray)charArray size:(jsize)size {
    jchar zero[size];
    memset(zero, 0, size * sizeof(jchar));
    (*_jniEnv)->SetCharArrayRegion(_jniEnv, charArray, 0, size, zero);
}

- (BOOL)removeEncryption:(NSString *)passphrase
{
    jclass mgrClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];
    // We're ready! Let's start
    jmethodID encMethode = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "decryptWallet", "(Ljava/lang/String;)Z");
    
    if (encMethode == NULL)
        return NO;
    
    jboolean success = (*_jniEnv)->CallBooleanMethod(_jniEnv, _managerObject, encMethode, (*_jniEnv)->NewStringUTF(_jniEnv, passphrase.UTF8String));
    
    return success;
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

- (BOOL)exportWalletWithPassphase:(NSString *)passphrase To:(NSURL *)exportURL
{
    jclass mgrClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];
    // We're ready! Let's start
    jmethodID tM = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "getWalletDump", "(Ljava/lang/String;)Ljava/lang/String;");
    
    if (tM == NULL)
        return NO;
    
    jstring passphraseJString = nil;
    
    if(passphrase)
    {
        passphraseJString = (*_jniEnv)->NewStringUTF(_jniEnv, passphrase.UTF8String);
    }
    
    jstring walletDrumpString = (*_jniEnv)->CallObjectMethod(_jniEnv, _managerObject, tM, passphraseJString);
    
    if (walletDrumpString)
    {
        const char *walletDrumpChars = (*_jniEnv)->GetStringUTFChars(_jniEnv, walletDrumpString, NULL);
        
        NSString *bStr = [NSString stringWithUTF8String:walletDrumpChars];
        (*_jniEnv)->ReleaseStringUTFChars(_jniEnv, walletDrumpString, walletDrumpChars);
        
        NSError *error = nil;
        [bStr writeToFile:exportURL.path atomically:YES encoding:NSUTF8StringEncoding error:&error];
        if(error) {
            return NO;
        }
        
        NSLog(@"%@", bStr);
        return YES;
    }
    
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

#pragma mark - transaction/blockchain stack

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
- (NSInteger)prepareSendCoins:(uint64_t)coins toReceipent:(NSString *)receipent comment:(NSString *)comment password:(NSString *)password
{
    
    jstring passwordJString = NULL;
    if(password)
    {
        passwordJString = (*_jniEnv)->NewStringUTF(_jniEnv, password.UTF8String);
    }
    
    jclass mgrClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];
    // We're ready! Let's start
    jmethodID sendM = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "createSendRequest", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;");
    
    if (sendM == NULL)
    {
        return kHI_PREPARE_SEND_COINS_DID_FAIL_UNKNOWN;
    }
    
    jstring feeString = (*_jniEnv)->CallObjectMethod(_jniEnv, _managerObject, sendM, (*_jniEnv)->NewStringUTF(_jniEnv, [[NSString stringWithFormat:@"%lld", coins] UTF8String]),
                                                     (*_jniEnv)->NewStringUTF(_jniEnv, receipent.UTF8String),
                                                     passwordJString);
    
    if (feeString)
    {
        const char *feeChars = (*_jniEnv)->GetStringUTFChars(_jniEnv, feeString, NULL);
        
        NSString *fStr = [NSString stringWithUTF8String:feeChars];
        (*_jniEnv)->ReleaseStringUTFChars(_jniEnv, feeString, feeChars);
 
 
        if([fStr isEqualToString:@""])
        {
            return kHI_PREPARE_SEND_COINS_DID_FAIL_UNKNOWN;
        }
        else if([fStr isEqualToString:[NSString stringWithFormat:@"%d", kHI_PREPARE_SEND_COINS_DID_FAIL_UNKNOWN]])
        {
            return kHI_PREPARE_SEND_COINS_DID_FAIL_UNKNOWN;
        }
        else if([fStr isEqualToString:[NSString stringWithFormat:@"%d", kHI_PREPARE_SEND_COINS_DID_FAIL_ENC]])
        {
            return kHI_PREPARE_SEND_COINS_DID_FAIL_ENC;
        }
        else if([fStr isEqualToString:[NSString stringWithFormat:@"%d", kHI_PREPARE_SEND_COINS_DID_FAIL_NOT_ENOUGHT_FUNDS]])
        {
            return kHI_PREPARE_SEND_COINS_DID_FAIL_NOT_ENOUGHT_FUNDS;
        }
        
        return [fStr longLongValue];
    }
    
    return kHI_PREPARE_SEND_COINS_DID_FAIL_UNKNOWN;
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

- (NSDate *)lastBlockCreationTime
{
    jclass mgrClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];
    // We're ready! Let's start
    jmethodID tCM = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "getLastBlockCreationTime", "()J");
    
    if (tCM == NULL)
        return 0;
    
    jlong c = (*_jniEnv)->CallLongMethod(_jniEnv, _managerObject, tCM);
    if(c == 0)
    {
        return nil;
    }
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:c];
    return date;
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
    if(_syncProgress < 1.0)
    {
        // don't update transactions during the sync process because it will end up in rebuilding the gui muliple times per second
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self willChangeValueForKey:@"balance"];
        [[NSNotificationCenter defaultCenter] postNotificationName:kHIBitcoinManagerTransactionChangedNotification object:txid];
        [self didChangeValueForKey:@"balance"];
    });
}

- (void)onCoinsReceived:(NSString *)txid
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self willChangeValueForKey:@"balance"];
        [[NSNotificationCenter defaultCenter] postNotificationName:kHIBitcoinManagerCoinsReceivedNotification object:txid];
        [self didChangeValueForKey:@"balance"];
    });
}
    
- (void)onWalletChanged
{
    dispatch_async(dispatch_get_main_queue(), ^{
        // currently do nothing on this because it will use a lot of cpu during the sync
        
        //[self willChangeValueForKey:@"walletstate"];
        //[self didChangeValueForKey:@"walletstate"];
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


- (NSString *)decimalSeparator {
    return [self createNumberFormatterWithFormat:@"BTC"].decimalSeparator;
}

- (NSString *)preferredFormat {
    NSString *currency = [[NSUserDefaults standardUserDefaults] stringForKey:kBitcoinKitFormatPreferenceKey];
    return [self.availableFormats containsObject:currency] ? currency : @"mBTC";
}

- (void)setPreferredFormat:(NSString *)preferredFormat {
    NSString *oldValue = self.preferredFormat;
    if (![oldValue isEqualToString:preferredFormat]) {
        [[NSUserDefaults standardUserDefaults] setObject:preferredFormat
                                                  forKey:kBitcoinKitFormatPreferenceKey];
        [[NSNotificationCenter defaultCenter] postNotificationName:kBitcoinKitFormatChangeNotification
                                                            object:self
                                                          userInfo:nil];
    }
}

- (NSString *)stringWithDesignatorForBitcoin:(nanobtc_t)nanoBtcValue {
    return [NSString stringWithFormat:@"%@ %@", [self stringForBitcoin:nanoBtcValue], self.preferredFormat];
}

- (NSString *)stringForBitcoin:(nanobtc_t)nanoBtcValue {
    return [self stringForBitcoin:nanoBtcValue withFormat:self.preferredFormat];
}

- (NSString *)stringForBitcoin:(nanobtc_t)nanoBtcValue withFormat:(NSString *)format {
    bool isNeg = NO;
    if(nanoBtcValue < 0)
    {
        isNeg = YES;
        nanoBtcValue = -nanoBtcValue;
    }
    NSNumberFormatter *formatter = [self createNumberFormatterWithFormat:format];
    NSDecimalNumber *number = [NSDecimalNumber decimalNumberWithMantissa:nanoBtcValue
                                      exponent:-8
                                    isNegative:isNeg];
    number = [number decimalNumberByMultiplyingByPowerOf10:[self shiftForFormat:format]];
    
    return [formatter stringFromNumber:number];
}

- (NSNumberFormatter *)createNumberFormatterWithFormat:(NSString *)format {
    // Do not use the formatter's multiplier! It causes rounding errors!
    NSNumberFormatter *formatter = [NSNumberFormatter new];
    formatter.locale = _locale;
    formatter.generatesDecimalNumbers = YES;
    formatter.minimum = @0;
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.minimumIntegerDigits = 1;
    if ([format isEqualToString:@"BTC"]) {
        formatter.minimumFractionDigits = 2;
        formatter.maximumFractionDigits = 8;
    } else if ([format isEqualToString:@"mBTC"]) {
        formatter.minimumFractionDigits = 0;
        formatter.maximumFractionDigits = 5;
    } else if ([format isEqualToString:@"µBTC"]) {
        formatter.minimumFractionDigits = 0;
        formatter.maximumFractionDigits = 2;
    } else if ([format isEqualToString:@"satoshi"]) {
        formatter.minimumFractionDigits = 0;
        formatter.maximumFractionDigits = 0;
    } else {
        @throw [self createUnknownFormatException:format];
    }
    return formatter;
}

- (NSException *)createUnknownFormatException:(NSString *)format {
    return [NSException exceptionWithName:@"UnknownBitcoinFormatException"
                                   reason:[NSString stringWithFormat:@"Unknown Bitcoin format %@", format]
                                 userInfo:nil];
}

- (int)shiftForFormat:(NSString *)format {
    if ([format isEqualToString:@"BTC"]) {
        return 0;
    } else if ([format isEqualToString:@"mBTC"]) {
        return 3;
    } else if ([format isEqualToString:@"µBTC"]) {
        return 6;
    } else if ([format isEqualToString:@"satoshi"]) {
        return 8;
    } else {
        @throw [self createUnknownFormatException:format];
    }
}


- (NSString *)formatNanobtc:(nanobtc_t)nanoBtcValue
{
    return [self stringForBitcoin:nanoBtcValue];
}

- (NSString *)formatNanobtc:(nanobtc_t)nanoBtcValue withDesignator:(BOOL)designator
{
    return [self stringWithDesignatorForBitcoin:nanoBtcValue];
}

@end
