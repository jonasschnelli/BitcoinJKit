package com.hive.bitcoinkit;

import static com.google.bitcoin.core.Utils.bytesToHexString;

import com.google.bitcoin.core.*;
import com.google.bitcoin.crypto.KeyCrypterException;
import com.google.bitcoin.discovery.DnsDiscovery;
import com.google.bitcoin.params.MainNetParams;
import com.google.bitcoin.params.RegTestParams;
import com.google.bitcoin.params.TestNet3Params;
import com.google.bitcoin.script.Script;
import com.google.bitcoin.store.BlockStore;
import com.google.bitcoin.store.SPVBlockStore;
import com.google.bitcoin.store.UnreadableWalletException;
import com.google.bitcoin.utils.BriefLogFormatter;
import com.google.common.util.concurrent.*;

import org.spongycastle.util.encoders.Base64;

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

public class BitcoinManager implements PeerEventListener {
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
    
    private Wallet.SendRequest pendingSendRequest;
    
    
    
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
            Wallet.CoinSelector coinSelector = new Wallet.AllowUnconfirmedCoinSelector();
            
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
                    onTransactionChanged(pendingSendRequest.tx.getHashAsString());
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
	public String createSendRequest(String amount, final String sendToAddressString)
	{
        clearSendRequest();
        
        try {
            BigInteger value = new BigInteger(amount);
            Address sendToAddress = new Address(networkParams, sendToAddressString);

            pendingSendRequest = Wallet.SendRequest.to(sendToAddress, value);
            if (!wallet.completeTx(pendingSendRequest))
            {
              // return empty string as sign of a failed transaction preparation
              return "";
            }
            else
            {
              return pendingSendRequest.fee.toString();
          }
        } catch (Exception e) {
           return "";
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
     * start the bitcoinj app layer
     */
	public void start(String walletStreamAsBase64String) throws Exception
	{
        storedChainHeight = 0;
        
        File chainFile = new File(dataDirectory + "/" + appName + ".spvchain");

        // Try to read the wallet from storage, create a new one if not possible.
        wallet = null;
        
        if(walletStreamAsBase64String == null || walletStreamAsBase64String.length() == 0)
        {
            walletFile = new File(dataDirectory + "/"+ appName +".wallet");
            
            System.err.println("+++ using file wallet ("+dataDirectory + "/"+ appName +".wallet)");
            
            try {
                if (walletFile.exists())
                {
                    wallet = Wallet.loadFromFile(walletFile);
                    if(!chainFile.exists())
                    {
                        wallet.clearTransactions(0);
                    }
                }
            } catch (UnreadableWalletException e) {
                // TODO: error case
            }
            
            if (wallet == null) {
                // if there is no wallet, create one and add a ec key
                wallet = new Wallet(networkParams);
                wallet.addKey(new ECKey());
                wallet.saveToFile(walletFile);
                
                //make wallet autosave
                wallet.autosaveToFile(walletFile, 1, TimeUnit.SECONDS, null);
            }
        }
        else
        {
            System.err.println("+++ using keychain base64 wallet...");
            int len = walletStreamAsBase64String.length() / 4 * 3;
            ByteArrayOutputStream bOut = new ByteArrayOutputStream(len);
            try
            {
                Base64.decode(walletStreamAsBase64String, bOut);
                ByteArrayInputStream bis = new ByteArrayInputStream(bOut.toByteArray());
                wallet = Wallet.loadFromFileStream(bis);
                System.err.println("+++ base64 wallet loaded");
            }
            catch (UnreadableWalletException e)
            {
                System.err.println("+++ unreable wallet");
                throw new RuntimeException("exception decoding base64 string: " + e);
            }
            catch (IOException e)
            {
                System.err.println("+++ ioexeption");
                throw new RuntimeException("exception decoding base64 string: " + e);
            }

            // base64 wallet
            if (wallet == null) {
                System.err.println("+++ wallet was EMPTY <!");
                // if there is no wallet, create one and add a ec key
                wallet = new Wallet(networkParams);
                wallet.addKey(new ECKey());
            }
        }
        

        
        

        // Fetch the first key in the wallet (should be the only key).
        ECKey key = wallet.getKeys().iterator().next();
        
        // Load the block chain, if there is one stored locally. If it's going to be freshly created, checkpoint it.
        boolean chainExistedAlready = chainFile.exists();
        blockStore = new SPVBlockStore(networkParams, chainFile);
        if (!chainExistedAlready) {
            File checkpointsFile = new File(dataDirectory + "/bitcoinkit.checkpoints");
            if (checkpointsFile.exists()) {
                FileInputStream stream = new FileInputStream(checkpointsFile);
                CheckpointManager.checkpoint(networkParams, stream, blockStore, key.getCreationTimeSeconds());
            }
        }
     
        chain = new BlockChain(networkParams, wallet, blockStore);
        // Connect to the localhost node. One minute timeout since we won't try any other peers

        peerGroup = new PeerGroup(networkParams, chain);
        if (networkParams == RegTestParams.get()) {
            peerGroup.addAddress(InetAddress.getLocalHost());
        } else {
            peerGroup.addPeerDiscovery(new DnsDiscovery(networkParams));
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
        

        // We want to know when the balance changes.
        wallet.addEventListener(new AbstractWalletEventListener() {
            @Override
            public void onCoinsReceived(Wallet w, Transaction tx, BigInteger prevBalance, BigInteger newBalance) {
                assert !newBalance.equals(BigInteger.ZERO);
                
                // TODO: check if the isPending thing is required
                if (!tx.isPending()) return;
                
                onTransactionChanged(tx.getHashAsString());
            }
        });
        
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
    
	public native void onSynchronizationUpdate(double progress, long blockCount, long blockHeight);
	
	public native void onPeerCountChanged(int peersConnected);
	
	public native void onBalanceChanged();
	
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
                double progress = (double)downloadedSoFar / (double)blocksToDownload;
                onSynchronizationUpdate(progress, storedChainHeight+downloadedSoFar, -1);
            }
        }
	}
	
	public void onChainDownloadStarted(Peer peer, int blocksLeft)
	{
		blocksToDownload = blocksLeft;
		if (blocksToDownload == 0)
			onSynchronizationUpdate(1.0, storedChainHeight+blocksToDownload, -1);
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
	
	public List<Message> getData(Peer peer, GetDataMessage m)
	{
		return null;
	}
}
