use core::starknet::{ContractAddress, ClassHash};
use crate::QuestFactory::QuestFactory::{QuestType};

#[starknet::interface]
pub trait IQuestFactory<TContractState> {
    fn create_quest(
        ref self: TContractState, quest_type: QuestType, salt: felt252
    ) -> ContractAddress;
    fn gem_contract(self: @TContractState) -> ContractAddress;
    fn sbt_contract(self: @TContractState) -> ContractAddress;
    fn quest_class_hash(self: @TContractState) -> ClassHash;
    fn quest_count(self: @TContractState) -> u256;
}

#[starknet::contract]
pub mod QuestFactory {
    use core::hash::{HashStateTrait, HashStateExTrait};
    use core::num::traits::Zero;
    use core::poseidon::PoseidonTrait;
    use core::starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use core::starknet::{
        ClassHash, ContractAddress, SyscallResultTrait, syscalls::deploy_syscall, get_caller_address
    };
    use crate::Gem::{IGemDispatcher, IGemDispatcherTrait};
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::utils::serde::SerializedAppend;
    use super::IQuestFactory;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        quest_count: u256,
        gem_contract: ContractAddress,
        sbt_contract: ContractAddress,
        quest_class_hash: ClassHash,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        QuestCreated: QuestCreated,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    pub struct QuestCreated {
        pub quest_address: ContractAddress,
        pub quest_type: QuestType
    }

    #[derive(Copy, Drop, Serde, starknet::Store)]
    pub enum QuestType {
        SportsFitness,
        NutritionHealth,
        Arts,
        Education,
        Environment
    }

    pub mod Errors {
        pub const INVALID_ADDRESS: felt252 = 'Invalid address';
        pub const INVALID_CLASS_HASH: felt252 = 'Invalid class hash';
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        gem_contract: ContractAddress,
        sbt_contract: ContractAddress,
        quest_class_hash: ClassHash
    ) {
        assert(gem_contract.is_non_zero(), Errors::INVALID_ADDRESS);
        assert(sbt_contract.is_non_zero(), Errors::INVALID_ADDRESS);
        assert(quest_class_hash.is_non_zero(), Errors::INVALID_CLASS_HASH);

        self.ownable.initializer(owner);
        self.gem_contract.write(gem_contract);
        self.sbt_contract.write(sbt_contract);
        self.quest_class_hash.write(quest_class_hash);
    }

    #[abi(embed_v0)]
    impl QuestFactory of IQuestFactory<ContractState> {
        fn create_quest(
            ref self: ContractState, quest_type: QuestType, salt: felt252
        ) -> ContractAddress {
            self.ownable.assert_only_owner();
            let owner = get_caller_address();

            let gem_contract = self.gem_contract.read();
            let sbt_contract = self.sbt_contract.read();

            let mut constructor_calldata = array![];
            constructor_calldata.append_serde(owner);
            constructor_calldata.append_serde(gem_contract);
            constructor_calldata.append_serde(sbt_contract);
            constructor_calldata.append_serde(quest_type);

            // Create quest
            let (quest_address, _) = deploy_syscall(
                self.quest_class_hash.read(),
                PoseidonTrait::new().update_with(owner).update_with(salt).finalize(),
                constructor_calldata.span(),
                false
            )
                .unwrap_syscall();

            // Increment counter
            let quest_count = self.quest_count.read();
            self.quest_count.write(quest_count + 1);

            self.emit(QuestCreated { quest_address, quest_type });

            // Approve minter
            let gem_dispatcher = IGemDispatcher { contract_address: self.gem_contract.read() };
            gem_dispatcher.approve_minter(quest_address);

            quest_address
        }

        fn gem_contract(self: @ContractState) -> ContractAddress {
            self.gem_contract.read()
        }

        fn sbt_contract(self: @ContractState) -> ContractAddress {
            self.sbt_contract.read()
        }

        fn quest_class_hash(self: @ContractState) -> ClassHash {
            self.quest_class_hash.read()
        }

        fn quest_count(self: @ContractState) -> u256 {
            self.quest_count.read()
        }
    }
}
