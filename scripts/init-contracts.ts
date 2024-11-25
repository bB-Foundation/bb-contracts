import path from "path";
import { green, red, yellow } from "./helpers/colorize-log";
import deployedContracts from "../tmp/deployedContracts";
import dotenv from "dotenv";

import { Contract, RpcProvider, Account } from "starknet";

dotenv.config();

async function main() {
  // Configuration
  const preferredChain = process.env.NETWORK;
  console.log(yellow(`Using ${preferredChain} network`));

  const rpcUrl = preferredChain === "devnet" ? "http://localhost:5050" : process.env.RPC_URL_SEPOLIA;
  console.log(yellow(`Using ${rpcUrl} as RPC URL`));

  const deployerPrivateKey = preferredChain === "devnet" ? "0x564104eda6342ba54f2a698c0342b22b" : process.env.PRIVATE_KEY_SEPOLIA;
  const deployerAddress = preferredChain === "devnet" ? "0x6e1665171388ee560b46a9c321446734fefd29e9c94f969d6ecd0ca21db26aa" : process.env.ACCOUNT_ADDRESS_SEPOLIA;

  // Connect to provider and account
  const provider = new RpcProvider({ nodeUrl: rpcUrl });
  const account = new Account(provider, deployerAddress, deployerPrivateKey);
  console.log(green('Account connected successfully'));

  // Load deployed contract addresses

  const loomiAddress = deployedContracts[preferredChain].Loomi.address;
  const loomiAbi = deployedContracts[preferredChain].Loomi.abi;
  const gemAddress = deployedContracts[preferredChain].Gem.address;
  const gemAbi = deployedContracts[preferredChain].Gem.abi;
  const sbtAddress = deployedContracts[preferredChain].SBT.address;
  const sbtAbi = deployedContracts[preferredChain].SBT.abi;
  const questFactoryAddress = deployedContracts[preferredChain].QuestFactory.address;
  const questFactoryAbi = deployedContracts[preferredChain].QuestFactory.abi;
  
  // Create contract instances
  const gemContract = new Contract(gemAbi, gemAddress, account);

  try {
    // Register affiliates
    console.log(yellow('Adding trusted handler...'));
  
    console.log(green(`Adding QuestFactory (${questFactoryAddress}) as a trusted handler to the Gem contract.`));
    // Populate the transaction to add the trusted handler
    const gemAddTrustedHandlerTx = gemContract.populate('add_trusted_handler', [questFactoryAddress]);

    console.log(green('Sending transactions...'));

    const result = await account.execute([
      gemAddTrustedHandlerTx
    ]);

    console.log(green(`Waiting for transaction ${result.transaction_hash} to be included in a block...`));
    const txReceipt = await provider.waitForTransaction(result.transaction_hash);

    console.log(green('Initialization completed successfully!'));
  } catch (error) {
    console.error(red('Error during initialization:'), error);
    process.exit(1);
  }

  // Create contract instances
  const loomiContract = new Contract(loomiAbi, loomiAddress, account);

  try {
    // Register affiliates
    console.log(yellow('Approving minter...'));
  
    console.log(green(`Adding Gem (${gemAddress}) as a approved minter to the Loomi contract.`));
    // Populate the transaction to approve minter
    const loomiApproveMinterTx = loomiContract.populate('approve_minter', [gemAddress]);

    console.log(green('Sending transactions...'));

    const result = await account.execute([
      loomiApproveMinterTx
    ]);

    console.log(green(`Waiting for transaction ${result.transaction_hash} to be included in a block...`));
    const txReceipt = await provider.waitForTransaction(result.transaction_hash);

    console.log(green('Initialization completed successfully!'));
  } catch (error) {
    console.error(red('Error during initialization:'), error);
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
