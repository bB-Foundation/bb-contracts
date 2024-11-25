import {
  deployContract,
  executeDeployCalls,
  exportDeployments,
  deployer,
  declareContract,
} from "./deploy-contract";
import { green } from "./helpers/colorize-log";

/**
 * Deploy a contract using the specified parameters.
 *
 * @example (deploy contract with contructorArgs)
 * const deployScript = async (): Promise<void> => {
 *   await deployContract(
 *     {
 *       contract: "YourContract",
 *       contractName: "YourContractExportName",
 *       constructorArgs: {
 *         owner: deployer.address,
 *       },
 *       options: {
 *         maxFee: BigInt(1000000000000)
 *       }
 *     }
 *   );
 * };
 *
 * @example (deploy contract without contructorArgs)
 * const deployScript = async (): Promise<void> => {
 *   await deployContract(
 *     {
 *       contract: "YourContract",
 *       contractName: "YourContractExportName",
 *       options: {
 *         maxFee: BigInt(1000000000000)
 *       }
 *     }
 *   );
 * };
 *
 *
 * @returns {Promise<void>}
 */
const deployScript = async (): Promise<void> => {
  // Deploy Loomi
  const { address: loomiAddress } = await deployContract({
    contract: "Loomi",
    constructorArgs: {
      owner: deployer.address,
      base_uri: "https://example.com/api/lomi",
    },
  });

  const { address: gemAddress } = await deployContract({
    contract: "Gem",
    constructorArgs: {
      owner: deployer.address,
      loomi_address: loomiAddress,
      base_uri: "https://example.com/api/gem",
    },
  });

  const { address: sbtAddress } = await deployContract({
    contract: "SBT",
    constructorArgs: {
      owner: deployer.address,
      base_uri: "https://example.com/api/sbt",
    },
  });

  const { classHash: questClassHash } = await declareContract({
    contract: "QuestFactory",
    constructorArgs: {
      owner: deployer.address,
      gem_address: gemAddress,
      sbt_address: sbtAddress,
      base_uri: "https://example.com/api/sbt",
    },
  });

  const { address: questFactoryAddress } = await deployContract({
    contract: "QuestFactory",
    constructorArgs: {
      owner: deployer.address,
      gem_contract: gemAddress,
      sbt_contract: sbtAddress,
      quest_class_hash: questClassHash
    },
  });
};

deployScript()
  .then(async () => {
    executeDeployCalls()
      .then(() => {
        exportDeployments();
        console.log(green("All Setup Done"));
      })
      .catch((e) => {
        console.error(e);
        process.exit(1); // exit with error so that non subsequent scripts are run
      });
  })
  .catch(console.error);
