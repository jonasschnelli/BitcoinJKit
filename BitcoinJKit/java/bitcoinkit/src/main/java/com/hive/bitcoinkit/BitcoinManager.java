package com.hive.bitcoinkit;

import static com.google.bitcoin.core.Utils.bytesToHexString;

import com.google.bitcoin.core.*;
import com.google.bitcoin.crypto.KeyCrypter;
import com.google.bitcoin.crypto.KeyCrypterException;
import com.google.bitcoin.crypto.KeyCrypterScrypt;
import com.google.bitcoin.net.discovery.DnsDiscovery;
import com.google.bitcoin.params.MainNetParams;
import com.google.bitcoin.params.RegTestParams;
import com.google.bitcoin.params.TestNet3Params;
import com.google.bitcoin.script.Script;
import com.google.bitcoin.store.BlockStore;
import com.google.bitcoin.store.BlockStoreException;
import com.google.bitcoin.store.SPVBlockStore;
import com.google.bitcoin.store.UnreadableWalletException;
import com.google.bitcoin.store.WalletProtobufSerializer;
import com.google.bitcoin.utils.BriefLogFormatter;
import com.google.bitcoin.utils.Threading;
import com.google.common.util.concurrent.*;

import org.spongycastle.util.encoders.Base64;
import org.spongycastle.crypto.params.KeyParameter;

import java.io.ByteArrayOutputStream;
import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.math.BigInteger;
import java.net.InetAddress;
import java.nio.charset.Charset;
import java.util.List;
import java.util.concurrent.TimeUnit;
import java.util.HashSet;
import java.text.SimpleDateFormat;
import java.util.Arrays;
import java.util.Date;
import java.util.TimeZone;
import java.util.concurrent.TimeUnit;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.impl.CocoaLogger;
import java.nio.CharBuffer;

public class BitcoinManager implements PeerEventListener, Thread.UncaughtExceptionHandler, TransactionConfidence.Listener {
	private NetworkParameters networkParams;
	private Wallet wallet;
	private String dataDirectory;
    private String appName = "bitcoinkit";
    private PeerGroup peerGroup;
    private BlockStore blockStore;
    private BlockChain chain;
    private File walletFile;
    private int blocksToDownload;
    private int storedChainHeight;
    private int broadcastMinTransactions = -1;
    private HashSet<Transaction> trackedTransactions;
    
    private Wallet.SendRequest pendingSendRequest;
    
    private static final Logger log = LoggerFactory.getLogger(BitcoinManager.class);
    
    /* --- Initialization & configuration --- */
    
    public BitcoinManager()
    {
        Threading.uncaughtExceptionHandler = this;
        trackedTransactions = new HashSet<Transaction>();
        ((CocoaLogger) log).setLevel(CocoaLogger.HILoggerLevelDebug);
    }
    
    /* --- Thread.UncaughtExceptionHandler --- */
    
    public void uncaughtException(Thread thread, Throwable exception)
    {
        onException(exception);
    }
    
    public String getExceptionStackTrace(Throwable exception)
    {
        StringBuilder buffer = new StringBuilder();
        
        for (StackTraceElement line : exception.getStackTrace())
        {
            buffer.append("at " + line.toString() + "\n");
        }
        
        return buffer.toString();
    }
    
	public void setTestingNetwork(boolean testing)
	{
		if (testing)
		{
            broadcastMinTransactions = 1;
			this.networkParams = TestNet3Params.get();
		}
		else
		{
            broadcastMinTransactions = -1; // std
			this.networkParams = MainNetParams.get();
		}
	}
	
	public void setDataDirectory(String path)
	{
		dataDirectory = path;
	}

    public String getDataDirectory()
    {
        return dataDirectory;
    }

    public void setAppName(String newAppName)
    {
        appName = newAppName;
    }

    public String getAppName()
    {
        return appName;
    }
	
	public String getWalletAddress()
	{
		ECKey ecKey = wallet.getKeys().get(0);
		return ecKey.toAddress(networkParams).toString();
	}

    public String getAllWalletAddressesJSON()
    {
        StringBuffer conns = new StringBuffer();
        conns.append("[");
        for(ECKey key: wallet.getKeys())
        {
            conns.append("\"" + key.toAddress(networkParams).toString() + "\",");
        }
        if(conns.substring(conns.length() -1).equals(","))
        {
            conns.deleteCharAt(conns.length() -1);
        }
        conns.append("]");
        return conns.toString();
    }
	
	public BigInteger getBalance(int type)
	{
        if(type == 0)
        {
            return wallet.getBalance(Wallet.BalanceType.AVAILABLE);
        }
        else
        {
            return wallet.getBalance(Wallet.BalanceType.ESTIMATED);
        }
	}
    
    public String getBalanceString(int type)
    {
        if (wallet != null)
            return getBalance(type).toString();
        
        return null;
    }
	
	private String getJSONFromTransaction(Transaction tx)
	{
		if (tx != null)
		{
			try {
				String confidence = "building";
				StringBuffer conns = new StringBuffer();
				int connCount = 0;
				
				if (tx.getConfidence().getConfidenceType() == TransactionConfidence.ConfidenceType.PENDING)
					confidence = "pending";
				
				conns.append("[");
				
				if (tx.getInputs().size() > 0 && tx.getValue(wallet).compareTo(BigInteger.ZERO) > 0)
				{
					TransactionInput in = tx.getInput(0);
					if (connCount > 0)
	                	conns.append(", ");
					
					conns.append("{ ");
					try {
		                Script scriptSig = in.getScriptSig();
		                if (scriptSig.getChunks().size() == 2)
		                	conns.append("\"address\": \"" + scriptSig.getFromAddress(networkParams).toString() + "\"");
		                
		                conns.append(" ,\"category\": \"received\" }");
		                
		                connCount++;
		            } catch (Exception e) {
		              
		            }
				}
				
				if (tx.getOutputs().size() > 0 && tx.getValue(wallet).compareTo(BigInteger.ZERO) < 0)
				{
					TransactionOutput out = tx.getOutput(0);
						
					if (connCount > 0)
	                	conns.append(", ");
					
					conns.append("{ ");
					try {
		                Script scriptPubKey = out.getScriptPubKey();
		                if (scriptPubKey.isSentToAddress()) 
		                    conns.append(" \"address\": \"" + scriptPubKey.getToAddress(networkParams).toString() + "\"");
		                
		                conns.append(" ,\"category\": \"sent\" }");
		                
		                connCount++;
		            } catch (Exception e) {
		              
		            }
				}
				conns.append("]");
				//else if (tx.get)
				return "{ \"amount\": " + tx.getValue(wallet) + 
						", \"txid\": \"" + tx.getHashAsString()  + "\"" +
						", \"time\": \""  + tx.getUpdateTime() + "\"" + 
						", \"confidence\": \""   +confidence + "\"" +
						", \"details\": "   + conns.toString() +						
						"}";
			
			} catch (ScriptException e) {
				// TODO Auto-generated catch block
				e.printStackTrace();
			}
		}
		
		return null;
	}
	
	public int getTransactionCount()
	{
        if(wallet == null)
        {
            return 0;
        }
		return wallet.getTransactionsByTime().size();
	}
    
    public String getAllTransactions(int max)
    {
        long transactionCount = getTransactionCount();
        
        if(max > 0 && transactionCount > max)
        {
            // cut transactions
            return getTransactions(0, max);
        }
        return getTransactions(0, getTransactionCount());
    }
	
	public String getTransaction(String tx)
	{
        if(wallet == null)
        {
            return null;
        }
		Sha256Hash hash = new Sha256Hash(tx);
		return getJSONFromTransaction(wallet.getTransaction(hash));
	}
	
	public String getTransaction(int idx)
	{	
		return getJSONFromTransaction(wallet.getTransactionsByTime().get(idx));
	}
	
	public String getTransactions(int from, int count)
	{
        if(wallet == null)
        {
            return null;
        }
		List<Transaction> transactions = wallet.getTransactionsByTime();
		
		if (from >= transactions.size())
			return null;
		
		int to = (from + count < transactions.size()) ? from + count : transactions.size();
		
		StringBuffer txs = new StringBuffer();
		txs.append("[\n");
		boolean first = true;
		for (; from < to; from++)
		{
			if (first)
				first = false;
			else
				txs.append("\n,");
			
			txs.append(getJSONFromTransaction(transactions.get(from)));
		}
		txs.append("]\n");
		
		return txs.toString();
	}

    public String addKey()
    {
        boolean couldCreateKey = wallet.addKey(new ECKey());
        if(couldCreateKey)
        {
            ECKey ecKey = wallet.getKeys().get(wallet.getKeys().size()-1);
            return ecKey.toAddress(networkParams).toString();
        }
        return null;
    }

    public void clearSendRequest()
    {
        pendingSendRequest = null;
    }
    
    public String commitSendRequest()
    {
        if(pendingSendRequest == null)
        {
            return "";
        }
        
        try {
            wallet.commitTx(pendingSendRequest.tx);
            ListenableFuture<Transaction> future;
            if(broadcastMinTransactions < 0)
            {
                future = peerGroup.broadcastTransaction(pendingSendRequest.tx);
            }
            else
            {
                future = peerGroup.broadcastTransaction(pendingSendRequest.tx, broadcastMinTransactions);
            }
            
            Futures.addCallback(future, new FutureCallback<Transaction>() {
                public void onSuccess(Transaction transaction) {
                    onTransactionSuccess(pendingSendRequest.tx.getHashAsString());
                }
                
                public void onFailure(Throwable throwable) {
                    onTransactionFailed();
                    throwable.printStackTrace();
                }
            });
            
            return pendingSendRequest.tx.getHashAsString();
            
        } catch (Exception e) {
            return "";
        }
        
    }
    
    /**
     * creates and stores a sendRequest and return the required fee
     */
	public String createSendRequest(String amount, final String sendToAddressString, String passphrase)
	{
        clearSendRequest();
        
        try {
            BigInteger value = new BigInteger(amount);
            Address sendToAddress = new Address(networkParams, sendToAddressString);

            pendingSendRequest = Wallet.SendRequest.to(sendToAddress, value);
            
            // if there is a passphrase set, try to encrypt
            if(passphrase != null && wallet != null && wallet.isEncrypted())
            {
                
                // set the AES key if the password was set
                org.spongycastle.crypto.params.KeyParameter keyParams = wallet.getKeyCrypter().deriveKey(passphrase);
                if(keyParams == null)
                {
                    System.err.println("\n\n+++ keyparams is null\n\n");
                }
                pendingSendRequest.aesKey = keyParams;
            }
            wallet.completeTx(pendingSendRequest);
            return pendingSendRequest.fee.toString();
            
        } catch (KeyCrypterException e) {
            e.printStackTrace();
            
            for (StackTraceElement ste : Thread.currentThread().getStackTrace()) {
                System.err.println(ste);
            }
            
            return "-1"; // = crypter error
        }
        catch (InsufficientMoneyException e)
        {
            e.printStackTrace();
            return "-100"; // = unknown error
        }
        catch (Exception e)
        {
            e.printStackTrace();
           return "-100"; // = unknown error
        }
        
	}
    
    public boolean isAddressValid(String address)
    {
        try {
            Address addr = new Address(networkParams, address);
            return (addr != null);
        }
        catch (Exception e)
        {
            return false;
        }
    }

    /**
     * Returns the whole wallet file as base64 string to store into OS keychain, etc.
     */
    public String getWalletFileBase64String()
    {
        if(wallet == null)
        {
            return null;
        }
        
        ByteArrayOutputStream stream = new ByteArrayOutputStream();
        String base64Wallet = null;
        try {
            wallet.saveToFileStream(stream);
            base64Wallet = new String(Base64.encode(stream.toByteArray()), Charset.forName("UTF-8"));
        } catch (IOException e) {
            //TODO
            e.printStackTrace();
        }

         return base64Wallet;
    }
	
    /**
     * returns the seconds (timestamp) of the last block creation time
     */
    public long getLastBlockCreationTime()
    {
        if(chain != null)
        {
            StoredBlock chainHead = chain.getChainHead();
            if(chainHead != null)
            {
                Block blockHeader = chainHead.getHeader();
                if(blockHeader != null)
                {
                    return blockHeader.getTimeSeconds();
                }
            }
        }
        return 0;
    }
    
    /**
     * check if wallet is encrypted
     */
    public boolean isWalletEncrypted()
    {
        if(wallet != null)
        {
            return wallet.isEncrypted();
        }
        return false;
    }
    
    /**
     * encrypt your wallet
     */
    private void encryptWallet(char[] utf16Password, Wallet wallet)
    {
        KeyCrypterScrypt keyCrypter = new KeyCrypterScrypt();
        KeyParameter aesKey = deriveKeyAndWipePassword(utf16Password, keyCrypter);
        try
        {
            wallet.encrypt(keyCrypter, aesKey);
        }
        finally
        {
            wipeAesKey(aesKey);
        }
    }
    
    private KeyParameter aesKeyForPassword(char[] utf16Password) throws WrongPasswordException
    {
        KeyCrypter keyCrypter = wallet.getKeyCrypter();
        if (keyCrypter == null)
        {
            throw new WrongPasswordException("Wallet is not protected.");
        }
        return deriveKeyAndWipePassword(utf16Password, keyCrypter);
    }
    
    private KeyParameter deriveKeyAndWipePassword(char[] utf16Password, KeyCrypter keyCrypter)
    {
        try
        {
            return keyCrypter.deriveKey(CharBuffer.wrap(utf16Password));
        }
        finally
        {
            Arrays.fill(utf16Password, '\0');
        }
    }
    
    private void wipeAesKey(KeyParameter aesKey)
    {
        if (aesKey != null)
        {
            Arrays.fill(aesKey.getKey(), (byte) 0);
        }
    }
    
    /**
     * decrypt your wallet
     */
    private void decryptWallet(char[] oldUtf16Password) throws WrongPasswordException
    {
        KeyParameter oldAesKey = aesKeyForPassword(oldUtf16Password);
        try
        {
            wallet.decrypt(oldAesKey);
        }
        catch (KeyCrypterException e)
        {
            throw new WrongPasswordException(e);
        }
        finally
        {
            wipeAesKey(oldAesKey);
        }
    }
    
    public void changeWalletPassword(char[] oldUtf16Password, char[] newUtf16Password) throws WrongPasswordException
    {
        updateLastWalletChange(wallet);
        
        if (isWalletEncrypted())
        {
            decryptWallet(oldUtf16Password);
        }
        
        encryptWallet(newUtf16Password, wallet);
    }
    
    /**
     * decrypt your wallet
     */
    public String getWalletDump(String passphrase)
    {
        try
        {
            StringBuilder walletDump = new StringBuilder(2048);
            List<ECKey> keys = wallet.getKeys();// toStringWithPrivate()
            for(ECKey key: keys)
            {
                ECKey keyToPlayWith = key;
                
                if(wallet.isEncrypted() && passphrase != null)
                {
                    org.spongycastle.crypto.params.KeyParameter keyParams = wallet.getKeyCrypter().deriveKey(passphrase);
                    
                    ECKey decryptedKey = key.decrypt(wallet.getKeyCrypter(),keyParams);
                    if(decryptedKey != null)
                    {
                        keyToPlayWith = decryptedKey;
                    }
                }
                
                walletDump.append(keyToPlayWith.toStringWithPrivate()+"\n");
            }
            
            return walletDump.toString();
        }
        catch (Exception e)
        {
            return null;
        }
    }
    
    /**
     * save your wallet
     */
    public void saveWallet()
    {
        if(wallet != null)
        {
            try
            {
                wallet.saveToFile(walletFile);
            }
            catch (Exception e)
            {
                // TODO: error case
            }
        }
    }
    
    public void createWallet(char[] utf16Password) throws IOException, BlockStoreException, ExistingWalletException
    {
        if (walletFile == null)
        {
            walletFile = new File(dataDirectory + "/"+ appName +".wallet");
        }
        else if (walletFile.exists())
        {
            throw new ExistingWalletException("Trying to create a wallet even though one exists: " + walletFile);
        }
        
        wallet = new Wallet(networkParams);
        wallet.addExtension(new LastWalletChangeExtension());
        updateLastWalletChange(wallet);
        wallet.addKey(new ECKey());
        
        if (utf16Password != null)
        {
            encryptWallet(utf16Password, wallet);
        }
        
        wallet.saveToFile(walletFile);
        
        useWallet(wallet);
    }
    
    private void useWallet(Wallet wallet) throws IOException
    {
        this.wallet = wallet;
        
        //make wallet autosave
        wallet.autosaveToFile(walletFile, 1, TimeUnit.SECONDS, null);
        
        // We want to know when the balance changes.
        wallet.addEventListener(new AbstractWalletEventListener() {
            @Override
            public void onCoinsReceived(Wallet w, Transaction tx, BigInteger prevBalance, BigInteger newBalance) {
                assert !newBalance.equals(BigInteger.ZERO);
                
                // TODO: check if the isPending thing is required
                if (!tx.isPending()) return;
                
                onHICoinsReceived(tx.getHashAsString());
            }
            
            @Override
            public void onWalletChanged(Wallet wallet) {
                onHIWalletChanged();
            }
            
            @Override
            public void onTransactionConfidenceChanged(Wallet wallet, Transaction tx)
            {
                onTransactionChanged(tx.getHashAsString());
            }
            
        });
    }
    
    
    /* --- Keeping last wallet change date --- */
    
    public void updateLastWalletChange(Wallet wallet)
    {
        LastWalletChangeExtension ext =
        (LastWalletChangeExtension) wallet.getExtensions().get(LastWalletChangeExtension.EXTENSION_ID);
        
        ext.setLastWalletChangeDate(new Date());
    }
    
    public Date getLastWalletChange()
    {
        if (wallet == null)
        {
            return null;
        }
        
        LastWalletChangeExtension ext =
        (LastWalletChangeExtension) wallet.getExtensions().get(LastWalletChangeExtension.EXTENSION_ID);
        
        return ext.getLastWalletChangeDate();
    }
    
    public long getLastWalletChangeTimestamp()
    {
        Date date = getLastWalletChange();
        return (date != null) ? date.getTime() : 0;
    }
    
    
    /**
     * start the bitcoinj app layer
     */
	public void loadWallet() throws NoWalletException,UnreadableWalletException, IOException
	{
        if(wallet == null)
        {
            // if no wallet is loaded, try to load the default wallet
            try {
                if (walletFile == null)
                {
                    walletFile = new File(dataDirectory + "/"+ appName +".wallet");
                }
                if (walletFile.exists())
                {
                    wallet = Wallet.loadFromFile(walletFile);
                    useWallet(wallet);
                }
                else {
                    throw new NoWalletException("No wallet file found at: " + walletFile);
                }
            } catch (UnreadableWalletException e) {
                throw e;
            }
        }
    }
    
    /**
     * start the bitcoinj app layer
     */
	public void startBlockchain() throws BlockStoreException, NoWalletException,UnreadableWalletException, IOException
	{
        
        File chainFile = new File(dataDirectory + "/" + appName + ".spvchain");
        storedChainHeight = 0;
        
        loadWallet();
        
        if(!chainFile.exists())
        {
            wallet.clearTransactions(0);
        }

        // get the oldest key (for the checkpoint file)
        long oldestKey = 0;
        for(ECKey key: wallet.getKeys())
        {
            long keyAge = key.getCreationTimeSeconds();
            if(oldestKey == 0 || keyAge < oldestKey)
            {
                oldestKey = keyAge;
            }
        }
        
        String oldestKeyString = String.valueOf(oldestKey);
        System.err.println("+++oldest key: "+oldestKeyString);
        
        // Load the block chain, if there is one stored locally. If it's going to be freshly created, checkpoint it.
        boolean chainExistedAlready = chainFile.exists();
        blockStore = new SPVBlockStore(networkParams, chainFile);
        if (!chainExistedAlready && oldestKey > 0) {
            File checkpointsFile = new File(dataDirectory + "/" + appName + ".checkpoints");
            if (checkpointsFile.exists()) {
                System.err.println("+++using the checkpoint file");
                try {
                    FileInputStream stream = new FileInputStream(checkpointsFile);
                    CheckpointManager.checkpoint(networkParams, stream, blockStore, oldestKey);
                }
                catch (Exception e) {
                    // TODO
                }
            }
        }
     
        chain = new BlockChain(networkParams, wallet, blockStore);
        // Connect to the localhost node. One minute timeout since we won't try any other peers

        
        peerGroup = new PeerGroup(networkParams, chain);
        
        try {
            if (networkParams == RegTestParams.get()) {
                peerGroup.addAddress(InetAddress.getLocalHost());
            } else {
                peerGroup.addPeerDiscovery(new DnsDiscovery(networkParams));
            }
        }
        catch (Exception e) {
            // TODO
        }
        peerGroup.addEventListener(new AbstractPeerEventListener() {
            @Override
            public void onPeerConnected(Peer peer, int peerCount) {
                super.onPeerConnected(peer, peerCount);
                onPeerCountChanged(peerCount);
                
                // inform app about the expected height
                onSynchronizationUpdate(-1, -1, peerGroup.getMostCommonChainHeight());
            }
            
            @Override
            public void onPeerDisconnected(Peer peer, int peerCount) {
                super.onPeerDisconnected(peer, peerCount);
                onPeerCountChanged(peerCount);
            }
        });
            
        peerGroup.addWallet(wallet);
        
        
        // inform the app over the current chains height; if there is a chain and already loaded blocks
        if(chain != null)
        {
            StoredBlock chainHead = chain.getChainHead();
            if(chainHead != null)
            {
                storedChainHeight = chainHead.getHeight();
                onSynchronizationUpdate(0.0, storedChainHeight, -1);
            }
        }
        
        peerGroup.start();

        // inform about the balance
        onBalanceChanged();

        peerGroup.startBlockChainDownload(this);
	}
	
    /**
     * stop the bitcoinj app layer
     */
	public void stop()
	{
		try {
            System.out.print("Shutting down ... ");
            peerGroup.stopAndWait();
            wallet.saveToFile(walletFile);
            blockStore.close();
            System.out.print("done ");
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
	}
	
    /**
     * TODO
     */
	public void walletExport(String path)
	{
		
	}
	
	/* Implementing native callbacks here */
	
	public native void onTransactionChanged(String txid);
    
	public native void onTransactionFailed();
	
    public native void onTransactionSuccess(String txid);
    
    public native void onHICoinsReceived(String txid);
    
    public native void onHIWalletChanged();
    
	public native void onSynchronizationUpdate(double progress, long blockCount, long blockHeight);
	
	public native void onPeerCountChanged(int peersConnected);
	
	public native void onBalanceChanged();
	
    public native void onException(Throwable exception);
    
	/* Implementing peer listener */
	public void onBlocksDownloaded(Peer peer, Block block, int blocksLeft)
	{
		int downloadedSoFar = blocksToDownload - blocksLeft;
		if (blocksToDownload == 0)
        {
			onSynchronizationUpdate(1.0, storedChainHeight+downloadedSoFar, -1);
        }
		else
        {
            // report after every 100 block
            if(blocksLeft % 100 == 0)
            {
                long currentChainHeight = -1; // -1 = no change (by default)
                StoredBlock chainHead = chain.getChainHead();
                if(chainHead != null)
                {
                    currentChainHeight = chainHead.getHeight();
                }
                
                double progress = (double)downloadedSoFar / (double)blocksToDownload;
                onSynchronizationUpdate(progress, currentChainHeight, -1);
            }
        }
	}
	
	public void onChainDownloadStarted(Peer peer, int blocksLeft)
	{
        long currentChainHeight = -1; // -1 = no change (by default)
        StoredBlock chainHead = chain.getChainHead();
        if(chainHead != null)
        {
            currentChainHeight = chainHead.getHeight();
        }
        
		blocksToDownload = blocksLeft;
		if (blocksToDownload == 0)
			onSynchronizationUpdate(1.0, currentChainHeight, -1);
		else
			onSynchronizationUpdate(0.0, -1, -1);
	}
	
	public void onPeerConnected(Peer peer, int peerCount)
	{
	}
	
	public void onPeerDisconnected(Peer peer, int peerCount)
	{
	}
	
	public Message onPreMessageReceived(Peer peer, Message m)
	{
		return m;
	}
	
	public void onTransaction(Peer peer, Transaction t)
	{
		
	}
    
    /* --- TransactionConfidence.Listener --- */
    
    private void trackPendingTransactions(Wallet wallet)
    {
        // we won't receive onCoinsReceived again for transactions that we already know about,
        // so we need to listen to confidence changes again after a restart
        for (Transaction tx : wallet.getPendingTransactions())
        {
            trackTransaction(tx);
        }
    }
    
    private void trackTransaction(Transaction tx)
    {
        if (!trackedTransactions.contains(tx))
        {
            log.debug("Tracking transaction " + tx.getHashAsString());
            
            tx.getConfidence().addEventListener(this);
            trackedTransactions.add(tx);
        }
    }
    
    private void stopTrackingTransaction(Transaction tx)
    {
        if (trackedTransactions.contains(tx))
        {
            log.debug("Stopped tracking transaction " + tx.getHashAsString());
            
            tx.getConfidence().removeEventListener(this);
            trackedTransactions.remove(tx);
        }
    }
    
    public void onConfidenceChanged(final Transaction tx, TransactionConfidence.Listener.ChangeReason reason)
    {
        if (!tx.isPending())
        {
            // coins were confirmed (appeared in a block) - we don't need to listen anymore
            stopTrackingTransaction(tx);
        }
        
        // update the UI
        onTransactionChanged(tx.getHashAsString());
    }
	
	public List<Message> getData(Peer peer, GetDataMessage m)
	{
		return null;
	}
}
