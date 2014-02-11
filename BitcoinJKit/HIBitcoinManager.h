//
//  HIBitcoinManager.h
//  BitcoinKit
//
//  Created by Bazyli Zygan on 11.07.2013.
//  Extended by Jonas Schnelli 2013

//  Copyright (c) 2013 Hive Developers. All rights reserved.
//

#import <Foundation/Foundation.h>

// define the nanobtc type
typedef int64_t nanobtc_t;

extern NSString * const kHIBitcoinManagerTransactionChangedNotification;            //<<< Transaction list update notification. Sent object is a NSString representation of the updated hash
extern NSString * const kHIBitcoinManagerStartedNotification;                       //<<< Manager start notification. Informs that manager is now ready to use
extern NSString * const kHIBitcoinManagerStoppedNotification;                       //<<< Manager stop notification. Informs that manager is now stopped and can't be used anymore

#define kHI_PREPARE_SEND_COINS_DID_FAIL_ENC -1
#define kHI_PREPARE_SEND_COINS_DID_FAIL_NOT_ENOUGHT_FUNDS -2
#define kHI_PREPARE_SEND_COINS_DID_FAIL_UNKNOWN -100

#define kHIBitcoinManagerCoinsReceivedNotification @"kJHIBitcoinManagerCoinsReceivedNotification"

/** HIBitcoinManager is a class responsible for managing all Bitcoin actions app should do 
 *
 *  Word of warning. One should not create this object. All access should be done
 *  via defaultManager class method that returns application-wide singleton to it.
 *  
 *  All properties are KVC enabled so one can register as an observer to them to monitor the changes.
 */
@interface HIBitcoinManager : NSObject

@property (nonatomic, copy) NSString *appSupportDirectoryIdentifier;                                         //<<< Specifies the support directory identifier. Warning! All changes to it has to be performed BEFORE start.
@property (nonatomic, copy) NSString *appName;                                         //<<< Specifies an App Name. The name will be used for data file/folder creation. Warning! All changes to it has to be performed BEFORE initialize.
@property (nonatomic, copy) NSURL *dataURL;                                         //<<< Specifies an URL path to a directory where HIBitcoinManager should store its data. Warning! All changes to it has to be performed BEFORE initialize.
@property (nonatomic, assign) BOOL testingNetwork;                                  //<<< Specifies if a manager is running on the testing network. Warning! All changes to it has to be performed BEFORE initialize.
@property (nonatomic, readonly) NSUInteger connections;                             //<<< Currently active connections to bitcoin network
@property (nonatomic, readonly) BOOL isRunning;                                     //<<< Flag indicating if NPBitcoinManager is currently running and connecting with the network
@property (nonatomic, readonly) uint64_t balance;                                   //<<< Actual balance of the wallet
@property (nonatomic, readonly) uint64_t balanceUnconfirmed;                        //<<< Actual balance of the wallet
@property (nonatomic, readonly) double syncProgress;                            //<<< Double value indicating the progress of network sync. Values are from 0.0 to 1.0.
@property (nonatomic, readonly) long currentBlockCount;                            //<<< Double value indicating the progress of network sync. Values are from 0.0 to 1.0.
@property (nonatomic, readonly) long totalBlocks;                            //<<< Double value indicating the progress of network sync. Values are from 0.0 to 1.0.
@property (nonatomic, readonly) NSUInteger peerCount;                            //<<< Integer value indicating how many peers are connected.
@property (nonatomic, readonly, getter = walletAddress) NSString *walletAddress;    //<<< Returns wallets main address. Creates one if none exists yet
@property (nonatomic, readonly, getter = allWalletAddresses) NSArray *allWalletAddresses;    //<<< Returns all wallet addresses.
@property (nonatomic, readonly) NSString *walletFileBase64String;    //<<< Returns the wallet file as base64 string.

@property (nonatomic, readonly, getter = isWalletEncrypted) BOOL isWalletEncrypted; //<<< Returns YES if wallet is encrypted. NO - otherwise
@property (nonatomic, readonly, getter = isWalletLocked) BOOL isWalletLocked;       //<<< Returns YES if wallet is currently locked. NO - otherwise
@property (nonatomic, readonly, getter = transactionCount) NSUInteger transactionCount; //<<< Returns global transaction cound for current wallet
@property (nonatomic, readonly, getter = lastBlockCreationTime) NSDate* lastBlockCreationTime; //<<< Returns the creation time of the last block in the SPVBlockStore
@property (nonatomic, assign) BOOL disableListening;                                //<<< Flag disabling listening on public IP address. To be used i.e. with tor proxy not to reveal real IP address. Warning! All changes to it has to be performed BEFORE initialize.

// Block that will be called when an exception is thrown on a background thread in JVM (e.g. while processing an
// incoming transaction or other blockchain update). If not set, the exception will just be thrown and will crash your
// app unless you install a global uncaught exception handler.
// Note: exceptions that are thrown while processing calls made from the Cocoa side will ignore this handler and will
// simply be thrown directly in the same thread.
@property (nonatomic, copy) void(^exceptionHandler)(NSException *exception);

@property (nonatomic, copy, readonly) NSString *decimalSeparator;
@property (nonatomic, copy, readonly) NSArray *availableFormats;
@property (nonatomic, copy) NSString *preferredFormat;
@property (nonatomic, copy) NSLocale *locale;

/** Class method returning application singleton to the manager.
 *
 * Please note not to create HIBitcoinManager objects in any other way.
 * This is due to bitcoind implementation that uses global variables that
 * currently allows us to create only one instance of this object.
 * Which should be more than enough anyway.
 *
 * @returns Initialized and ready manager object.
 */
+ (HIBitcoinManager *)defaultManager;

/** Starts the manager initializing all data and starting network sync. 
 *
 * One should start the manager only once. After configuring the singleton.
 */
- (void)initialize:(NSError **)error;
- (void)loadWallet:(NSError **)error;
- (void)startBlockchain:(NSError **)error;

/** Stops the manager and stores all up-to-date information in data folder
 *
 * One should stop the manager only once. At the shutdown procedure.
 * This is due to bitcoind implementation that uses too many globals.
 */
- (void)stop;

- (void)resyncBlockchain:(NSError **)error;

/** Returns transaction definition based on transaction hash
 *
 * @param hash NSString representation of transaction hash
 *
 * @returns NSDictionary definition of found transansaction. nil if not found
 */
- (NSDictionary *)transactionForHash:(NSString *)hash;

/** Returns transaction definition based on transaction hash
 *
 * WARNING: Because transaction are kept in maps in bitcoind the only way
 * to find an element at requested index is to iterate through all of elements
 * in front. DO NOT USE too often or your app will get absurdely slow
 *
 * @param index Index of the searched transaction
 *
 * @returns NSDictionary definition of found transansaction. nil if not found
 */
- (NSDictionary *)transactionAtIndex:(NSUInteger)index;

/** Returns an array of definitions of all transactions 
 *
 * @param max amount of transactions, use 0 for unlimited
 *
 * @returns Array of all transactions to this wallet
 */
- (NSArray *)allTransactions:(int)max;

/** Returns array of transactions from given range
 *
 * @param range Range of requested transactions
 *
 * @returns An array of transactions from requested range
 */
- (NSArray *)transactionsWithRange:(NSRange)range;

/** Checks if given address is valid address
 *
 * @param address Address string to be checked
 *
 * @returns YES if address is valid. NO - otherwise
 */
- (BOOL)isAddressValid:(NSString *)address;

/** Creates a new wallet protected with a password.
 *
 * Only call this if start returned kHIBitcoinManagerNoWallet.
 * It will fail if a wallet already exists.
 *
 * @param password The user password as an UTF-16-encoded string.
 */
- (void)createWalletWithPassword:(NSData *)password
                           error:(NSError **)error;
    
/** Creates a new ECKey
 *
 * @returns the new address string or nil if failed
 */
- (NSString *)addKey;

/** Sends amount of coins to receipent
 *
 * @param coins Amount of coins to be sent in satoshis
 * @param receipent Receipent address hash
 * @param comment optional comment string that will be bound to the transaction
 * @param complection Completion block where notification about created transaction hash will be sent
 *
 * @returns the fee in nanobtc as a long
 *
 */
- (void)prepareSendCoins:(nanobtc_t)coins toReceipent:(NSString *)receipent comment:(NSString *)comment password:(NSData *)password returnFee:(nanobtc_t *)feeRetVal error:(NSError **)error;

- (NSString *)commitPreparedTransaction:(NSError **)error;
- (void)clearSendRequest:(NSError **)error;

/** save the wallet to the given wallet store file
 *
 * @returns YES if save was successful, NO - otherwise
 */
- (BOOL)saveWallet;

/** Encrypts wallet with given passphrase
 *
 * @param passphrase NSString value of the passphrase to encrypt wallet with
 *
 * @returns YES if encryption was successful, NO - otherwise
 */
- (void)changeWalletPassword:(NSData *)fromPassword
                  toPassword:(NSData *)toPassword
                       error:(NSError **)error;

/** Removes wallet encryption with given passphrase
 *
 * @param passphrase NSString value of the passphrase to decrypt wallet with
 *
 * @returns YES if encryption was successful, NO - otherwise
 */
- (void)removeEncryption:(NSData *)password error:(NSError **)error;

/** Changes the encryption passphrase for the wallet
 *
 * @param oldpasswd Old passphrase that wallet is currently encrypted with
 * @param newpasswd New passphrase that wallet should be encrypted with
 *
 * @returns YES if recryption was successful, NO - otherwise
 */
- (BOOL)changeWalletEncryptionKeyFrom:(NSString *)oldpasswd to:(NSString *)newpasswd;

/** Unlocks wallet
 *
 * @param passwd Passphrase that wallet is locked with
 *
 * @returns YES if unlock was successful, NO - otherwise
 */
- (BOOL)unlockWalletWith:(NSString *)passwd;

/** Locks wallet */
- (void)lockWallet;

/** Exports wallet to given file URL
 *
 * @param exportURL NSURL to local file where wallet should be dumped to
 *
 * @returns YES if dump was successful. NO - otherwise
 */
- (BOOL)exportWalletWithPassphase:(NSString *)passphrase To:(NSURL *)exportURL;

/** Import wallet from given file URL
 *
 * @param importURL NSURL to local file from which to import wallet data
 *
 * @returns YES if import was successful. NO - otherwise
 */
- (BOOL)importWalletFrom:(NSURL *)importURL;

/** Formts nano btc (satoshis) to a nice NSString with the standard BTC unit
 *
 * @param NSInteger nanoBTC;
 *
 * @returns YES if import was successful. NO - otherwise
 */
- (NSString *)formatNanobtc:(nanobtc_t)nanoBtc;
- (NSString *)formatNanobtc:(nanobtc_t)nanoBtcValue withDesignator:(BOOL)designator;
- (nanobtc_t)nanoBtcFromString:(NSString *)userAmount format:(NSString *)format;

/** Checks if the wallet is encryped
 *
 * @returns YES if wallet is encryped. NO - otherwise
 */
- (BOOL)isWalletEncrypted;

@end
 
